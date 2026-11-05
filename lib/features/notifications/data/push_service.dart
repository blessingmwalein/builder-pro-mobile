import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_models.dart';

/// Whether this phone may show alerts.
enum PushPermission { unsupported, notAsked, granted, denied }

/// Firebase Cloud Messaging behind a small interface, so screens and the
/// controller can be tested without the platform plugin, and so the app still
/// runs (with alerts reported as unavailable) when Firebase is not set up.
abstract class PushService {
  /// False when Firebase could not start on this build.
  bool get available;

  Future<PushPermission> permission();

  /// Asks the phone's permission to show alerts (a prompt on Android 13+ and
  /// iOS).
  Future<PushPermission> requestPermission();

  /// This install's address for alerts, or null when it cannot be had.
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// Alerts that arrive while the app is open.
  Stream<PushMessage> get foreground;

  /// An alert tapped while the app was in the background.
  Stream<PushMessage> get opened;

  /// The alert that was tapped to start the app, if any.
  Future<PushMessage?> launchedBy();

  /// Forgets this install's address, so alerts stop arriving on it (used when
  /// someone signs out).
  Future<void> deleteToken();
}

class NoPushService implements PushService {
  const NoPushService();

  @override
  bool get available => false;
  @override
  Future<PushPermission> permission() async => PushPermission.unsupported;
  @override
  Future<PushPermission> requestPermission() async =>
      PushPermission.unsupported;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Stream<PushMessage> get foreground => const Stream.empty();
  @override
  Stream<PushMessage> get opened => const Stream.empty();
  @override
  Future<PushMessage?> launchedBy() async => null;
  @override
  Future<void> deleteToken() async {}
}

/// Uses the classic FCM registration token (`getToken`, `onTokenRefresh`,
/// `deleteToken`). The plugin now marks these deprecated in favour of
/// `register()` / `onRegistered`, which hand out a Firebase *Installation ID*
/// for direct sending instead. The backend sends with the Firebase Admin SDK
/// and a registration token, and this has not been verified to accept an
/// installation id, so the working calls are kept on purpose.
class FirebasePushService implements PushService {
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  @override
  bool get available => true;

  PushPermission _map(AuthorizationStatus s) => switch (s) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notAsked,
  };

  @override
  Future<PushPermission> permission() async =>
      _map((await _m.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async => _map(
    (await _m.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    )).authorizationStatus,
  );

  @override
  Future<String?> token() async {
    try {
      // ignore: deprecated_member_use
      return await _m.getToken();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes =>
      // ignore: deprecated_member_use
      _m.onTokenRefresh;

  PushMessage _convert(RemoteMessage m) => PushMessage.fromParts(
    messageId: m.messageId,
    title: m.notification?.title,
    body: m.notification?.body,
    data: m.data,
  );

  @override
  Stream<PushMessage> get foreground =>
      FirebaseMessaging.onMessage.map(_convert);

  @override
  Stream<PushMessage> get opened =>
      FirebaseMessaging.onMessageOpenedApp.map(_convert);

  @override
  Future<PushMessage?> launchedBy() async {
    final m = await _m.getInitialMessage();
    return m == null ? null : _convert(m);
  }

  @override
  Future<void> deleteToken() async {
    try {
      // ignore: deprecated_member_use
      await _m.deleteToken();
    } catch (_) {
      // Signing out must never fail over this.
    }
  }
}
