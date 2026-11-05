import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../notifications/data/notification_categories.dart';
import '../../projects/application/projects_providers.dart';
import '../data/messaging_models.dart';
import '../data/messaging_repository.dart';
import '../data/realtime_messages.dart';

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => MessagingRepository(ref.watch(apiClientProvider)),
);

/// What the server can do beyond plain text (files, voice, replies, mentions,
/// unread counts). Read each time a chat opens; an older server, or one that
/// cannot be reached, gets plain text only.
final chatCapabilitiesProvider = FutureProvider.autoDispose<ChatCapabilities>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.read(messagingRepositoryProvider).capabilities();
  } on AppException {
    return ChatCapabilities.legacy;
  }
});

/// Live push for the signed-in user. Created when a thread opens and closed
/// when the last thread closes (or on sign-out), so no socket keeps retrying in
/// the background. Tests override it with a fake.
final realtimeMessagesProvider = Provider.autoDispose<RealtimeMessages?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  final api = ref.read(apiClientProvider);
  final socket = SocketIoMessages(
    origin: ref.read(appConfigProvider).socketOrigin,
    tenantSlug: api.tenantSlug,
    tokenProvider: () async {
      // The handshake is the only time the server checks the token, so make
      // sure it is fresh: any authenticated call refreshes an expired one.
      try {
        await api.get('auth/me');
      } on AppException {
        // Use whatever token we have; the connection will simply fail and retry.
      }
      return api.accessToken;
    },
  );
  ref.onDispose(socket.dispose);
  return socket;
});

// ---- conversation list -------------------------------------------------------

class ConversationsController extends AsyncNotifier<List<ConversationSummary>> {
  @override
  Future<List<ConversationSummary>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    ref.listen<int>(appResumeProvider, (_, _) => _quietRefresh());
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      if (prev?.value == false && next.value == true) _quietRefresh();
    });
    return ref.read(messagingRepositoryProvider).conversations();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// The list as it stands now, read fresh (used before starting a chat, so an
  /// existing one is found).
  Future<List<ConversationSummary>> fresh() async {
    final list = await ref.read(messagingRepositoryProvider).conversations();
    if (ref.mounted) state = AsyncData(list);
    return list;
  }

  /// The chat was opened and read: its badge goes at once.
  void clearUnread(String id) {
    final s = state.value;
    if (s == null || !ref.mounted) return;
    if (!s.any((c) => c.id == id && c.unreadCount > 0)) return;
    state = AsyncData([for (final c in s) c.id == id ? c.withUnread(0) : c]);
  }

  Future<void> _quietRefresh() async {
    try {
      final fresh = await ref.read(messagingRepositoryProvider).conversations();
      if (ref.mounted) state = AsyncData(fresh);
    } on AppException {
      // Keep what is showing.
    }
  }
}

final conversationsProvider =
    AsyncNotifierProvider<ConversationsController, List<ConversationSummary>>(
      ConversationsController.new,
    );

/// The people who can be @mentioned in a chat and whose names are highlighted in
/// it: its participants, the people who have written in it, and (for a group
/// linked to a project) the project's team. You are left out.
final chatPeopleProvider = Provider.autoDispose
    .family<List<ChatPerson>, String>((ref, conversationId) {
      final me = ref.watch(currentUserIdProvider);
      final summary = ref
          .watch(conversationsProvider)
          .value
          ?.where((c) => c.id == conversationId)
          .firstOrNull;
      final seen = <String, ChatPerson>{};
      void add(String id, String name) {
        if (id.isEmpty || id == me || name.trim().isEmpty) return;
        seen.putIfAbsent(id, () => ChatPerson(id: id, name: name.trim()));
      }

      for (final p in summary?.participants ?? const <ChatPerson>[]) {
        add(p.id, p.name);
      }
      final messages =
          ref.watch(threadProvider(conversationId)).value?.messages ??
          const <ChatMessage>[];
      for (final m in messages) {
        add(m.senderId, m.senderName);
      }
      final projectId = summary?.projectId;
      if (projectId != null &&
          ref.watch(permissionsProvider).hasAny(Feature.projects)) {
        final members =
            ref.watch(projectDetailProvider(projectId)).value?.members ??
            const [];
        for (final m in members) {
          add(m.id, m.name);
        }
      }
      return seen.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });

// ---- one conversation ---------------------------------------------------------

class ThreadState {
  const ThreadState({
    required this.messages,
    required this.hasOlder,
    this.page = 1,
    this.loadingOlder = false,
    this.live = false,
  });

  /// Oldest first; unsent local messages come last.
  final List<ChatMessage> messages;
  final bool hasOlder;
  final int page;
  final bool loadingOlder;

  /// The realtime connection is up (otherwise the thread polls).
  final bool live;

  ThreadState copyWith({
    List<ChatMessage>? messages,
    bool? hasOlder,
    int? page,
    bool? loadingOlder,
    bool? live,
  }) => ThreadState(
    messages: messages ?? this.messages,
    hasOlder: hasOlder ?? this.hasOlder,
    page: page ?? this.page,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    live: live ?? this.live,
  );
}

class ThreadController extends AsyncNotifier<ThreadState> {
  ThreadController(this.conversationId);
  final String conversationId;

  static const _pollEvery = Duration(seconds: 8);
  static const _uuid = Uuid();

  Timer? _poll;
  ChatCapabilities? _caps;

  @override
  Future<ThreadState> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const ThreadState(messages: [], hasOlder: false);
    final repo = ref.read(messagingRepositoryProvider);
    // Watched (not read) so the socket lives exactly as long as a thread is
    // open, and before the first await as Riverpod requires.
    final socket = ref.watch(realtimeMessagesProvider);
    ref.listen<int>(appResumeProvider, (_, _) => unawaited(refreshLatest()));

    final page = await repo.messages(conversationId);

    if (socket != null) {
      socket
        ..start()
        ..join(conversationId);
      final sub = socket.messages
          .where((m) => m.conversationId == conversationId)
          .listen(_receive);
      final conn = socket.connection.listen((up) => _setLive(up));
      ref.onDispose(() {
        sub.cancel();
        conn.cancel();
      });
    }
    ref.onDispose(() => _poll?.cancel());
    _poll = Timer.periodic(_pollEvery, (_) {
      // The socket pushes when it is up; polling covers the gap (and hosts that
      // cannot hold WebSockets at all).
      if (!(socket?.isConnected ?? false)) unawaited(refreshLatest());
    });

    unawaited(_markRead(repo));
    return ThreadState(
      messages: page.messages,
      hasOlder: page.hasMore,
      live: socket?.isConnected ?? false,
    );
  }

  Future<void> _markRead(MessagingRepository repo) async {
    try {
      await repo.markRead(conversationId);
      if (ref.mounted) {
        ref.read(conversationsProvider.notifier).clearUnread(conversationId);
      }
    } on AppException {
      // Read receipts are best effort.
    }
  }

  Future<ChatCapabilities> _capabilities() async {
    final known = _caps;
    if (known != null) return known;
    try {
      _caps = await ref.read(chatCapabilitiesProvider.future);
    } catch (_) {
      _caps = ChatCapabilities.legacy;
    }
    return _caps!;
  }

  void _setLive(bool up) {
    final s = state.value;
    if (s != null && s.live != up && ref.mounted) {
      state = AsyncData(s.copyWith(live: up));
    }
  }

  /// Merges server messages into the list by id, keeping unsent local ones last.
  void _merge(List<ChatMessage> incoming) {
    final s = state.value;
    if (s == null || !ref.mounted) return;
    final byId = {
      for (final m in s.messages)
        if (!m.isLocal) m.id: m,
    };
    final alreadyKnown = byId.keys.toSet();
    for (final m in incoming) {
      byId[m.id] = m;
    }
    final server = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final local = s.messages.where((m) => m.isLocal).toList();

    // My own message can come back (live push or a poll) before the HTTP reply
    // does. Replace its "sending" copy instead of showing it twice.
    final me = ref.read(currentUserIdProvider);
    for (final m in incoming) {
      if (m.senderId != me || alreadyKnown.contains(m.id)) continue;
      final i = local.indexWhere(
        (l) =>
            l.state == SendState.sending &&
            l.body == m.body &&
            l.pending.length == m.attachments.length,
      );
      if (i >= 0) local.removeAt(i);
    }
    state = AsyncData(s.copyWith(messages: [...server, ...local]));
  }

  void _receive(ChatMessage m) => _merge([m]);

  /// Fetches the newest page and merges it in (used by polling and resume).
  Future<bool> refreshLatest() async {
    try {
      final page = await ref
          .read(messagingRepositoryProvider)
          .messages(conversationId);
      _merge(page.messages);
      return true;
    } on AppException {
      return false;
    }
  }

  Future<void> loadOlder() async {
    final s = state.value;
    if (s == null || s.loadingOlder || !s.hasOlder) return;
    state = AsyncData(s.copyWith(loadingOlder: true));
    try {
      final next = s.page + 1;
      final page = await ref
          .read(messagingRepositoryProvider)
          .messages(conversationId, page: next);
      final cur = state.value ?? s;
      final known = cur.messages.map((m) => m.id).toSet();
      final older = page.messages.where((m) => !known.contains(m.id)).toList();
      final local = cur.messages.where((m) => m.isLocal).toList();
      final server = cur.messages.where((m) => !m.isLocal).toList();
      if (ref.mounted) {
        state = AsyncData(
          cur.copyWith(
            messages: [...older, ...server, ...local],
            hasOlder: page.hasMore,
            page: next,
            loadingOlder: false,
          ),
        );
      }
    } on AppException {
      final cur = state.value;
      if (cur != null && ref.mounted) {
        state = AsyncData(cur.copyWith(loadingOlder: false));
      }
    }
  }

  // ---- sending ----

  /// Adds the message at once (shown as sending, with its files) and then sends
  /// it: the files are uploaded first, then the message that names them.
  /// [replyTo] is the message being answered; [mentionIds] are the people tagged
  /// with @ in the text.
  Future<void> send(
    String text, {
    List<PendingFile> files = const [],
    ReplyPreview? replyTo,
    List<String> mentionIds = const [],
  }) async {
    final body = text.trim();
    final me = ref.read(sessionProvider).me?.user;
    final s = state.value;
    if ((body.isEmpty && files.isEmpty) || me == null || s == null) return;
    final local = ChatMessage(
      id: 'local-${_uuid.v4()}',
      conversationId: conversationId,
      senderId: me.id,
      senderName: me.fullName,
      body: body,
      createdAt: DateTime.now(),
      replyTo: replyTo,
      mentionedUserIds: mentionIds,
      pending: files,
      state: SendState.sending,
    );
    state = AsyncData(s.copyWith(messages: [...s.messages, local]));
    await _deliver(local.id);
  }

  /// Tries a failed message again. Files already uploaded are not uploaded
  /// again. When the last try's outcome was unknown the thread is checked first
  /// so the message is not sent twice.
  Future<void> retry(String localId) async {
    final m = _find(localId);
    if (m == null || m.state == SendState.sending) return;
    _replace(localId, m.copyWith(state: SendState.sending, clearError: true));
    if (m.maybeSent && await _alreadyOnServer(m)) {
      _drop(localId);
      return;
    }
    _replace(localId, m.copyWith(state: SendState.sending, maybeSent: false));
    await _deliver(localId);
  }

  void discard(String localId) => _drop(localId);

  Future<void> _deliver(String localId) async {
    final repo = ref.read(messagingRepositoryProvider);
    final caps = await _capabilities();
    var m = _find(localId);
    if (m == null) return;
    // Past this point a failure may mean the message is already saved.
    var messageRequestSent = false;
    try {
      var files = m.pending;
      final uploaded = <UploadedFile>[];
      for (var i = 0; i < files.length; i++) {
        var f = files[i];
        if (f.uploaded == null) {
          final u = await repo.uploadAttachment(
            f,
            onProgress: (sent, total) {
              if (total <= 0) return;
              _progress(localId, (i + sent / total) / files.length);
            },
          );
          f = f.withUploaded(u);
          files = [...files]..[i] = f;
          final cur = _find(localId);
          if (cur != null) _replace(localId, cur.copyWith(pending: files));
        }
        uploaded.add(f.uploaded!);
      }

      m = _find(localId) ?? m;
      final reply = m.replyTo;
      // A server that keeps replies gets the link; any other gets the quote
      // written into the text so the reply still reads as one.
      final linked =
          reply != null && reply.messageId.isNotEmpty && caps.replies;
      final wireBody = reply != null && !linked
          ? '${reply.asTextQuote()}${m.body}'
          : m.body;
      messageRequestSent = true;
      final sent = await repo.send(
        conversationId,
        wireBody,
        attachments: uploaded,
        replyToId: linked ? reply.messageId : null,
        mentionedUserIds: caps.mentions ? m.mentionedUserIds : const [],
      );
      _drop(localId);
      _merge([sent]);
    } on AppException catch (e) {
      final cur = _find(localId);
      if (cur == null) return;
      if (messageRequestSent && e.outcomeUnknown) {
        // May already be saved. Look before offering a resend.
        final reached = await refreshLatest();
        if (reached && await _alreadyOnServer(cur)) {
          _drop(localId);
          return;
        }
        _replace(
          localId,
          cur.copyWith(
            state: SendState.failed,
            maybeSent: !reached,
            clearProgress: true,
            error: reached
                ? 'Not sent. Tap to try again.'
                : 'May not have sent. Check the thread before sending again.',
          ),
        );
        return;
      }
      _replace(
        localId,
        cur.copyWith(
          state: SendState.failed,
          clearProgress: true,
          error: e.message,
        ),
      );
    }
  }

  /// A message from me with the same text and files, created after this attempt
  /// began.
  Future<bool> _alreadyOnServer(ChatMessage local) async {
    await refreshLatest();
    final s = state.value;
    if (s == null) return false;
    final since = local.createdAt.subtract(const Duration(minutes: 1));
    return s.messages.any(
      (m) =>
          !m.isLocal &&
          m.senderId == local.senderId &&
          m.body == local.body &&
          m.attachments.length == local.pending.length &&
          m.createdAt.isAfter(since),
    );
  }

  void _progress(String id, double value) {
    final m = _find(id);
    if (m == null) return;
    _replace(id, m.copyWith(progress: value.clamp(0.0, 1.0)));
  }

  ChatMessage? _find(String id) {
    final s = state.value;
    if (s == null) return null;
    for (final m in s.messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _replace(String id, ChatMessage next) {
    final s = state.value;
    if (s == null || !ref.mounted) return;
    state = AsyncData(
      s.copyWith(messages: [for (final m in s.messages) m.id == id ? next : m]),
    );
  }

  void _drop(String id) {
    final s = state.value;
    if (s == null || !ref.mounted) return;
    state = AsyncData(
      s.copyWith(messages: s.messages.where((m) => m.id != id).toList()),
    );
  }
}

final threadProvider = AsyncNotifierProvider.autoDispose
    .family<ThreadController, ThreadState, String>(ThreadController.new);

// ---- starting chats -------------------------------------------------------------

/// Opening a chat with someone and making groups.
///
/// A new chat is never made twice: the list is read first and an existing direct
/// chat with that person is opened. After a timeout the list is read again before
/// anything is repeated.
class ChatActions {
  ChatActions(this._ref);
  final Ref _ref;

  MessagingRepository get _repo => _ref.read(messagingRepositoryProvider);

  static ConversationSummary? findDirect(
    List<ConversationSummary> list,
    String personId,
    String? myId,
  ) {
    for (final c in list) {
      if (c.isProject) continue;
      final ids = c.participants.map((p) => p.id).toSet();
      if (ids.contains(personId) && ids.length <= 2 && ids.contains(myId)) {
        return c;
      }
    }
    return null;
  }

  /// The id of the direct chat with [personId], made if there is none yet.
  Future<String> openDirect(String personId) async {
    final me = _ref.read(currentUserIdProvider);
    if (me == null) {
      throw const AppException(
        AppErrorKind.unauthorized,
        'Sign in to send messages.',
      );
    }
    if (personId == me) {
      throw const AppException(
        AppErrorKind.validation,
        'That is you. Choose someone else.',
      );
    }
    final list = await _ref.read(conversationsProvider.notifier).fresh();
    final existing = findDirect(list, personId, me);
    if (existing != null) return existing.id;
    try {
      final created = await _repo.createConversation(
        type: 'DIRECT',
        participantIds: [personId],
      );
      unawaited(_ref.read(conversationsProvider.notifier).refresh());
      return created.id;
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      // The reply was lost: it may have been made.
      try {
        final again = await _ref.read(conversationsProvider.notifier).fresh();
        final made = findDirect(again, personId, me);
        if (made != null) return made.id;
      } on AppException {
        // Fall through to the message below.
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through. Check Messages, then try again.",
      );
    }
  }

  /// Makes a group chat linked to [projectId] (the way the web app does) with
  /// [participantIds], and returns its id.
  Future<String> createGroup({
    required String projectId,
    required List<String> participantIds,
    String? title,
  }) async {
    final startedAt = DateTime.now().subtract(const Duration(minutes: 1));
    try {
      final created = await _repo.createConversation(
        type: 'PROJECT',
        participantIds: participantIds,
        projectId: projectId,
        title: title,
      );
      unawaited(_ref.read(conversationsProvider.notifier).refresh());
      return created.id;
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      try {
        final again = await _ref.read(conversationsProvider.notifier).fresh();
        final wanted = (title ?? '').trim();
        final made = again.where(
          (c) =>
              c.isProject &&
              c.projectId == projectId &&
              (c.title ?? '').trim() == wanted &&
              c.updatedAt.isAfter(startedAt),
        );
        if (made.isNotEmpty) return made.first.id;
      } on AppException {
        // Fall through to the message below.
      }
      throw const AppException(
        AppErrorKind.uncertain,
        "We couldn't tell whether the group was made. Check Messages before trying again, or there may be two.",
      );
    }
  }
}

final chatActionsProvider = Provider<ChatActions>((ref) => ChatActions(ref));

// ---- notifications ------------------------------------------------------------

/// Which notifications the list shows: all of them, only the unread ones, or one
/// kind.
@immutable
class NotificationFilter {
  const NotificationFilter({this.unreadOnly = false, this.category});

  final bool unreadOnly;
  final String? category;

  bool get isAll => !unreadOnly && category == null;

  /// Whether [n] belongs in the list. The server narrows the list too, but an
  /// older one ignores the filter, so the screen applies it again.
  bool allows(NotificationItem n) =>
      (!unreadOnly || !n.isRead) &&
      (category == null || n.category == category);

  @override
  bool operator ==(Object other) =>
      other is NotificationFilter &&
      other.unreadOnly == unreadOnly &&
      other.category == category;

  @override
  int get hashCode => Object.hash(unreadOnly, category);
}

class NotificationFilterController extends Notifier<NotificationFilter> {
  @override
  NotificationFilter build() {
    // Starts over for whoever signs in next.
    ref.watch(currentUserIdProvider);
    return const NotificationFilter();
  }

  void select(NotificationFilter filter) => state = filter;
}

final notificationFilterProvider =
    NotifierProvider<NotificationFilterController, NotificationFilter>(
      NotificationFilterController.new,
    );

/// Whether more of the list can be loaded, and whether that is happening.
@immutable
class NotificationsPaging {
  const NotificationsPaging({
    this.hasMore = false,
    this.loadingMore = false,
    this.error,
  });

  final bool hasMore;
  final bool loadingMore;
  final AppException? error;
}

class NotificationsPagingController extends Notifier<NotificationsPaging> {
  @override
  NotificationsPaging build() => const NotificationsPaging();

  void set(NotificationsPaging next) => state = next;
}

final notificationsPagingProvider =
    NotifierProvider<NotificationsPagingController, NotificationsPaging>(
      NotificationsPagingController.new,
    );

/// The server's own count of unread notifications, which is the true total (the
/// loaded list is only a page). Null when the server cannot say (an older
/// server): the bell then counts what is loaded. Read again when the app comes
/// back to the front.
class ServerUnreadCount extends AsyncNotifier<int?> {
  bool _unsupported = false;

  @override
  Future<int?> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null || _unsupported) return null;
    ref.listen<int>(appResumeProvider, (_, _) => ref.invalidateSelf());
    try {
      final count = await ref.read(messagingRepositoryProvider).unreadCount();
      // A server without the call is not asked again until the app restarts.
      if (count == null) _unsupported = true;
      return count;
    } on AppException {
      return null;
    }
  }

  /// A change answered with the new total.
  void set(int count) {
    if (ref.mounted) state = AsyncData(count);
  }
}

final serverUnreadCountProvider =
    AsyncNotifierProvider<ServerUnreadCount, int?>(ServerUnreadCount.new);

class NotificationsController extends AsyncNotifier<List<NotificationItem>> {
  static const pageSize = 30;

  int _page = 1;

  MessagingRepository get _repo => ref.read(messagingRepositoryProvider);

  @override
  Future<List<NotificationItem>> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const [];
    // A different filter reads the list again from its first page.
    final filter = ref.watch(notificationFilterProvider);
    // Coming back to the app is when new notifications are most likely, so the
    // count on the bell is re-read then (the old list stays until it arrives).
    ref.listen<int>(appResumeProvider, (_, _) => ref.invalidateSelf());
    final page = await _repo.notifications(
      limit: pageSize,
      unread: filter.unreadOnly ? true : null,
      category: filter.category,
    );
    _page = page.page;
    _publish(NotificationsPaging(hasMore: page.hasMore));
    return page.items;
  }

  /// Handed to the paging state after the build, never during it.
  void _publish(NotificationsPaging next) {
    Future.microtask(() {
      if (ref.mounted) ref.read(notificationsPagingProvider.notifier).set(next);
    });
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Reads the next page and adds it to the list.
  Future<void> loadMore() async {
    final current = state.value;
    final paging = ref.read(notificationsPagingProvider);
    if (current == null || !paging.hasMore || paging.loadingMore) return;
    final pagingNotifier = ref.read(notificationsPagingProvider.notifier);
    pagingNotifier.set(
      const NotificationsPaging(hasMore: true, loadingMore: true),
    );
    final filter = ref.read(notificationFilterProvider);
    try {
      final next = await _repo.notifications(
        page: _page + 1,
        limit: pageSize,
        unread: filter.unreadOnly ? true : null,
        category: filter.category,
      );
      if (!ref.mounted) return;
      final cur = state.value ?? current;
      final known = cur.map((n) => n.id).toSet();
      state = AsyncData([
        ...cur,
        ...next.items.where((n) => !known.contains(n.id)),
      ]);
      _page = next.page;
      pagingNotifier.set(NotificationsPaging(hasMore: next.hasMore));
    } on AppException catch (e) {
      if (ref.mounted) {
        pagingNotifier.set(NotificationsPaging(hasMore: true, error: e));
      }
    }
  }

  /// The server's unread total after a change: used when it says, otherwise read
  /// again.
  void _afterChange(int? unread) {
    if (!ref.mounted) return;
    if (unread != null) {
      ref.read(serverUnreadCountProvider.notifier).set(unread);
    } else {
      ref.invalidate(serverUnreadCountProvider);
    }
  }

  /// Marks one read. It shows as read at once; if the server cannot be reached
  /// it goes back to unread, so what is shown is what the server has.
  Future<void> markRead(String id) async {
    final before = state.value;
    if (before != null) {
      state = AsyncData([for (final n in before) n.id == id ? n.asRead() : n]);
    }
    try {
      _afterChange(await _repo.markNotificationRead(id));
    } on AppException {
      if (before != null && ref.mounted) state = AsyncData(before);
    }
  }

  /// Marks every notification (or every one of [category]) read. Goes back
  /// to how it was, and says why, when the server cannot be reached. A server
  /// without "read all" is sent one at a time instead.
  Future<void> markAllRead({String? category}) async {
    final before = state.value;
    bool matches(NotificationItem n) =>
        category == null || n.category == category;
    if (before != null) {
      state = AsyncData([
        for (final n in before) !n.isRead && matches(n) ? n.asRead() : n,
      ]);
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid != null && category == null) {
      await ref.read(appDatabaseProvider).markAllLocalNotificationsRead(uid);
    }
    try {
      _afterChange(await _repo.markAllNotificationsRead(category: category));
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.notFound) {
        await _markEachRead([
          for (final n in before ?? const <NotificationItem>[])
            if (!n.isRead && matches(n)) n.id,
        ]);
        return;
      }
      if (before != null && ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }

  /// For a server that cannot mark everything at once: the loaded unread ones,
  /// one after another (at most 50), best effort.
  Future<void> _markEachRead(List<String> ids) async {
    for (final id in ids.take(50)) {
      try {
        await _repo.markNotificationRead(id);
      } on AppException {
        // The next refresh shows what the server has.
      }
    }
    if (ref.mounted) ref.invalidate(serverUnreadCountProvider);
  }

  // ---- deleting: out of the list now, sent after a moment so it can be undone

  /// Takes [id] out of the list at once and returns it (null when it is not
  /// there), so the screen can offer Undo before [commitDelete].
  NotificationItem? removeLocally(String id) {
    final cur = state.value;
    if (cur == null) return null;
    final item = cur.where((n) => n.id == id).firstOrNull;
    if (item == null) return null;
    state = AsyncData(cur.where((n) => n.id != id).toList());
    return item;
  }

  /// Puts a removed notification back where it belongs (newest first).
  void restore(NotificationItem item) {
    final cur = state.value;
    if (cur == null || !ref.mounted) return;
    if (cur.any((n) => n.id == item.id)) return;
    state = AsyncData(
      [...cur, item]..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    );
  }

  /// Sends the delete. Null when it worked; otherwise the problem, and the
  /// notification is put back. Deleting twice is harmless.
  Future<AppException?> commitDelete(NotificationItem item) async {
    try {
      _afterChange(await _repo.deleteNotification(item.id));
      return null;
    } on AppException catch (e) {
      restore(item);
      if (e.kind == AppErrorKind.notFound || e.statusCode == 405) {
        return const AppException(
          AppErrorKind.notFound,
          'Removing notifications needs an update on the server.',
        );
      }
      return e;
    }
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<NotificationItem>>(
      NotificationsController.new,
    );

// ---- which alerts to get -------------------------------------------------------

/// The person's per-kind switches. A server that cannot keep them yet gives
/// [NotificationPreferences.unsupported] and everything stays on. Changing a
/// switch shows at once and goes back, with the reason, if it cannot be saved.
class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  int _saving = 0;

  /// Every kind the app knows is listed, even one the server did not send yet.
  static NotificationPreferences _complete(NotificationPreferences p) {
    if (!p.supported) return p;
    final have = p.categories.map((c) => c.category).toSet();
    return NotificationPreferences(
      supported: true,
      categories:
          [
            ...p.categories,
            for (final k in NotificationCategories.all)
              if (!have.contains(k.key))
                NotificationPreference(category: k.key, label: k.label),
          ]..sort(
            (a, b) =>
                NotificationCategories.orderOf(a.category)
                    .compareTo(NotificationCategories.orderOf(b.category)),
          ),
    );
  }

  @override
  Future<NotificationPreferences> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return NotificationPreferences.unsupported;
    return _complete(
      await ref.read(messagingRepositoryProvider).notificationPreferences(),
    );
  }

  Future<void> setSwitch(String category, {bool? inApp, bool? push}) async {
    final cur = state.value;
    if (cur == null || !cur.supported) return;
    final previous = cur.categories
        .where((c) => c.category == category)
        .firstOrNull;
    if (previous == null) return;
    final next = previous.copyWith(inApp: inApp, push: push);
    state = AsyncData(cur.withCategory(next));
    _saving++;
    try {
      final saved = await ref
          .read(messagingRepositoryProvider)
          .saveNotificationPreferences((state.value ?? cur).categories);
      // The server's answer replaces the screen's copy only when nothing newer
      // is still on its way.
      if (_saving == 1 && ref.mounted) state = AsyncData(_complete(saved));
    } on AppException {
      if (ref.mounted) {
        final now = state.value;
        if (now != null) state = AsyncData(now.withCategory(previous));
      }
      rethrow;
    } finally {
      _saving--;
    }
  }
}

final notificationPreferencesProvider =
    AsyncNotifierProvider<
      NotificationPreferencesController,
      NotificationPreferences
    >(NotificationPreferencesController.new);
