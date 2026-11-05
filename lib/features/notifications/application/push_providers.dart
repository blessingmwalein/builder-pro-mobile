import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router/app_router.dart';
import '../../../app/router/route_guard.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/storage/preferences_store.dart';
import '../../messaging/application/messaging_providers.dart';
import '../data/device_token_repository.dart';
import '../data/push_models.dart';
import '../data/push_service.dart';

/// Whether Firebase started on this build. Set once at start-up (`main`); when
/// it did not, alerts are reported as unavailable and everything else works.
final firebaseReadyProvider = Provider<bool>((ref) => false);

final pushServiceProvider = Provider<PushService>(
  (ref) => ref.watch(firebaseReadyProvider)
      ? FirebasePushService()
      : const NoPushService(),
);

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => DeviceTokenRepository(ref.watch(apiClientProvider)),
);

/// The latest alert that arrived while the app was open, for the in-app banner.
class IncomingPush extends Notifier<PushMessage?> {
  @override
  PushMessage? build() => null;

  void show(PushMessage message) => state = message;
}

final incomingPushProvider = NotifierProvider<IncomingPush, PushMessage?>(
  IncomingPush.new,
);

enum PushStatus {
  /// Firebase did not start on this build.
  unavailable,

  /// Not turned on for this person on this phone.
  off,

  /// Turned on, the phone allows alerts and this phone is registered.
  on,

  /// The person turned it on but the phone's own setting refuses alerts.
  blocked,
}

class PushState {
  const PushState(this.status);
  final PushStatus status;
}

/// The alert that launched the app is acted on once per run, not once per
/// rebuild of the controller.
bool _launchHandled = false;

/// Alerts on this phone: opt-in, per person.
///
/// * Turning alerts on asks the phone's permission, then tells the server which
///   phone to send this person's alerts to.
/// * An alert that arrives while the app is open is kept in the app (so it can
///   be read later) and shown as a banner.
/// * Tapping an alert opens the screen it is about, which the router still
///   checks against the person's permissions.
/// * Signing out first tells the server to stop sending to this phone, then
///   forgets this phone's address so alerts cannot arrive here even if that
///   could not be done (no signal, expired session).
class PushController extends Notifier<PushState> {
  String? _registered;
  bool _enabled = false;

  PushService get _service => ref.read(pushServiceProvider);

  static String _prefKey(String uid) => 'push_enabled_$uid';

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  @override
  PushState build() {
    final uid = ref.watch(currentUserIdProvider);
    final service = _service;
    if (!service.available) return const PushState(PushStatus.unavailable);
    if (uid == null) return const PushState(PushStatus.off);

    final subscriptions = [
      service.tokenRefreshes.listen((t) => unawaited(_register(t))),
      service.foreground.listen((m) => unawaited(_received(m))),
      service.opened.listen((m) => unawaited(_opened(m))),
    ];
    ref.onDispose(() {
      for (final s in subscriptions) {
        s.cancel();
      }
    });
    ref.listen<int>(appResumeProvider, (_, _) => unawaited(_register()));

    // Captured now: these run during sign-out, when this provider may already
    // be on its way out and `ref` can no longer be used.
    final repo = ref.read(deviceTokenRepositoryProvider);
    final cleanup = ref.read(sessionCleanupProvider);
    cleanup.registerBeforeSignOut('push', () async {
      if (!_enabled) return;
      final token = await service.token();
      if (token != null) await repo.unregister(token);
    });
    cleanup.registerKeyed('push', service.deleteToken);

    unawaited(_start(uid));
    return const PushState(PushStatus.off);
  }

  Future<void> _start(String uid) async {
    final enabled = await ref
        .read(preferencesStoreProvider)
        .readBool(_prefKey(uid));
    if (!ref.mounted) return;
    _enabled = enabled;
    if (enabled) {
      final permission = await _service.permission();
      if (!ref.mounted) return;
      switch (permission) {
        case PushPermission.granted:
          state = const PushState(PushStatus.on);
          unawaited(_register());
        case PushPermission.denied:
          state = const PushState(PushStatus.blocked);
        case PushPermission.notAsked || PushPermission.unsupported:
          state = const PushState(PushStatus.off);
      }
    }
    if (!_launchHandled) {
      _launchHandled = true;
      final launchedBy = await _service.launchedBy();
      if (launchedBy != null && ref.mounted) unawaited(_opened(launchedBy));
    }
  }

  /// Asks the phone's permission and, when given, starts sending this person's
  /// alerts to this phone.
  Future<void> enable() async {
    final uid = ref.read(currentUserIdProvider);
    if (!_service.available || uid == null) return;
    final permission = await _service.requestPermission();
    if (!ref.mounted) return;
    if (permission != PushPermission.granted) {
      _enabled = false;
      await ref.read(preferencesStoreProvider).writeBool(_prefKey(uid), false);
      if (ref.mounted) state = const PushState(PushStatus.blocked);
      return;
    }
    _enabled = true;
    await ref.read(preferencesStoreProvider).writeBool(_prefKey(uid), true);
    if (!ref.mounted) return;
    state = const PushState(PushStatus.on);
    await _register();
  }

  /// Stops alerts on this phone: tells the server, then forgets this phone's
  /// address.
  Future<void> disable() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final service = _service;
    final repo = ref.read(deviceTokenRepositoryProvider);
    _enabled = false;
    await ref.read(preferencesStoreProvider).writeBool(_prefKey(uid), false);
    if (ref.mounted) state = const PushState(PushStatus.off);
    try {
      final token = await service.token();
      if (token != null) await repo.unregister(token);
    } on AppException {
      // The address is forgotten below either way.
    }
    _registered = null;
    await service.deleteToken();
  }

  Future<void> _register([String? given]) async {
    if (!_enabled) return;
    final token = given ?? await _service.token();
    if (token == null || token == _registered || !ref.mounted) return;
    try {
      await ref
          .read(deviceTokenRepositoryProvider)
          .register(token, platform: _platform);
      _registered = token;
    } on AppException {
      // Tried again the next time the app comes to the front.
    }
  }

  /// An alert arrived while the app is open: keep it, and show a banner.
  Future<void> _received(PushMessage m) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    await _keep(uid, m);
    if (!ref.mounted) return;
    ref.read(incomingPushProvider.notifier).show(m);
    // The server may now have a notification row for it too, and the true unread
    // total has changed.
    ref.invalidate(notificationsProvider);
    ref.invalidate(serverUnreadCountProvider);
  }

  /// An alert was tapped: open what it is about, and mark it read here and on the
  /// server, so the web app and the list on this phone agree that it was seen.
  Future<void> _opened(PushMessage m) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid != null) {
      await _keep(uid, m);
      await ref.read(appDatabaseProvider).markLocalNotificationRead(uid, m.id);
    }
    if (!ref.mounted) return;
    // Opened first: marking it read must not hold the person up.
    ref.read(routerProvider).go(m.route ?? Routes.notifications);
    final serverId = m.notificationId;
    if (serverId != null) {
      // Updates the list, rolls back if the server cannot be reached, and keeps
      // the unread total in step.
      await ref.read(notificationsProvider.notifier).markRead(serverId);
    }
  }

  Future<void> _keep(String uid, PushMessage m) => ref
      .read(appDatabaseProvider)
      .saveLocalNotification(
        id: m.id,
        userId: uid,
        title: m.title,
        body: m.body,
        route: m.route,
        receivedAt: m.receivedAt,
      );
}

final pushControllerProvider = NotifierProvider<PushController, PushState>(
  PushController.new,
);

// ---- the in-app inbox ---------------------------------------------------------

/// The alerts kept on this phone, newest first.
final localNotificationsProvider = StreamProvider<List<LocalNotification>>((
  ref,
) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(appDatabaseProvider).watchLocalNotifications(uid);
});

/// One line of the inbox: a notification from the server's list or an alert kept
/// on this phone.
class InboxItem {
  const InboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.fromServer,
    this.route,
    this.category,
    this.actorName,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final bool fromServer;
  final String? route;

  /// The kind of alert (`tasks`, `finance`...), known only for the server's.
  final String? category;

  /// Who did it, when the server says.
  final String? actorName;
}

class InboxState {
  const InboxState(
    this.items, {
    this.serverUnavailable = false,
    this.serverError,
  });

  /// Newest first.
  final List<InboxItem> items;

  /// The server's notification list is not open to this account yet (HTTP 403),
  /// so only alerts kept on this phone are listed.
  final bool serverUnavailable;

  /// The server's list failed for another reason; what is on this phone is
  /// still shown.
  final AppException? serverError;
}

/// The server's notifications and the alerts kept on this phone as one list. An
/// alert the server also lists (same id) is shown once, as the server's.
final inboxProvider = Provider<AsyncValue<InboxState>>((ref) {
  final server = ref.watch(notificationsProvider);
  final local = ref.watch(localNotificationsProvider);

  final kept = local.value ?? const <LocalNotification>[];
  final serverItems = server.value ?? const [];
  final serverIds = serverItems.map((n) => n.id).toSet();

  final items = <InboxItem>[
    for (final n in serverItems)
      InboxItem(
        id: n.id,
        title: n.title,
        body: n.body,
        createdAt: n.createdAt,
        isRead: n.isRead,
        fromServer: true,
        route: n.route,
        category: n.category,
        actorName: n.actorName,
      ),
    for (final l in kept)
      if (!serverIds.contains(l.id))
        InboxItem(
          id: l.id,
          title: l.title,
          body: l.body,
          createdAt: l.receivedAt,
          isRead: l.isRead,
          fromServer: false,
          route: l.route,
        ),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final error = server.error;
  final forbidden =
      error is AppException && error.kind == AppErrorKind.forbidden;
  if (server.isLoading && local.isLoading) return const AsyncLoading();
  if (error != null && !forbidden && items.isEmpty) {
    return AsyncError(error, server.stackTrace ?? StackTrace.current);
  }
  return AsyncData(
    InboxState(
      items,
      serverUnavailable: forbidden,
      serverError: error is AppException && !forbidden ? error : null,
    ),
  );
});

/// How many alerts have not been read: the server's own total when it can say
/// (the list on screen is only a page), otherwise the unread ones in the list.
final unreadAlertsProvider = Provider<int>((ref) {
  final server = ref.watch(serverUnreadCountProvider).value;
  if (server != null) return server;
  return ref.watch(inboxProvider).value?.items.where((i) => !i.isRead).length ??
      0;
});

/// Marks one inbox line as read, on the server when it is the server's.
Future<void> markInboxRead(WidgetRef ref, InboxItem item) async {
  final uid = ref.read(currentUserIdProvider);
  if (uid != null) {
    await ref.read(appDatabaseProvider).markLocalNotificationRead(uid, item.id);
  }
  if (item.fromServer) {
    await ref.read(notificationsProvider.notifier).markRead(item.id);
  }
}
