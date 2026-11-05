import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'messaging_models.dart';

/// `/messaging/*` (REST is the source of truth; the socket only pushes).
class MessagingRepository {
  MessagingRepository(this._api);

  final ApiClient _api;

  static const pageSize = 30;

  /// What the server can do beyond plain text. An older server does not have the
  /// call (404) and gets plain text only.
  Future<ChatCapabilities> capabilities() async {
    try {
      return ChatCapabilities.parse(await _api.get('messaging/capabilities'));
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.notFound) return ChatCapabilities.legacy;
      rethrow;
    }
  }

  /// A plain array, newest activity first.
  Future<List<ConversationSummary>> conversations() async {
    final body = await _api.get('messaging/conversations');
    final rows = body is List ? body : J.list(J.map(body)['items']);
    return J
        .maps(rows)
        .map(ConversationSummary.tryParse)
        .whereType<ConversationSummary>()
        .toList();
  }

  /// Page 1 is the NEWEST messages; each page is already oldest-first.
  Future<MessagePage> messages(String conversationId, {int page = 1}) async {
    final body = await _api.get(
      'messaging/conversations/$conversationId/messages',
      query: {'page': page, 'limit': pageSize},
    );
    final paged = J.paged(body);
    return MessagePage(
      paged.items
          .map((m) => ChatMessage.tryParse(m, conversationId: conversationId))
          .whereType<ChatMessage>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// Sends a file to be named in a message: `POST /messaging/attachments`,
  /// multipart field `file` (a photo, a document or a voice message, at most
  /// 20 MB). Sending the same file twice only stores it twice, so it is safe to
  /// repeat.
  Future<UploadedFile> uploadAttachment(
    PendingFile file, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final body = await _api.postMultipart(
      'messaging/attachments',
      () => FormData.fromMap({
        'file': MultipartFile.fromFileSync(
          file.path,
          filename: file.name,
          contentType: DioMediaType.parse(file.contentType),
        ),
      }),
      onProgress: onProgress,
    );
    final uploaded = UploadedFile.tryParse(body);
    if (uploaded == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server replied, but the reply could not be read.',
      );
    }
    return uploaded.withDuration(file.durationMs);
  }

  /// There is no idempotency key, so a send whose reply never arrived must be
  /// checked against the thread before it is repeated. [replyToId] and
  /// [mentionedUserIds] are only sent to a server that says it keeps them.
  Future<ChatMessage> send(
    String conversationId,
    String body, {
    List<UploadedFile> attachments = const [],
    String? replyToId,
    List<String> mentionedUserIds = const [],
  }) async {
    final reply = await _api.post(
      'messaging/messages',
      body: {
        'conversationId': conversationId,
        'body': body,
        if (attachments.isNotEmpty)
          'attachments': [for (final a in attachments) a.toBody()],
        'replyToId': ?replyToId,
        if (mentionedUserIds.isNotEmpty) 'mentionedUserIds': mentionedUserIds,
      },
    );
    final message = ChatMessage.tryParse(
      J.map(reply),
      conversationId: conversationId,
    );
    if (message == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. Your message may have been sent.',
      );
    }
    return message;
  }

  /// `POST /messaging/conversations` (needs `messaging.send`). A direct chat
  /// needs exactly one other person; a group needs a project. A newer server
  /// answers with the direct chat that already exists instead of making a
  /// second one. Not repeatable on an older server.
  Future<ConversationSummary> createConversation({
    required String type,
    required List<String> participantIds,
    String? projectId,
    String? title,
  }) async {
    final reply = await _api.post(
      'messaging/conversations',
      body: {
        'type': type,
        'participantIds': participantIds,
        'projectId': ?projectId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );
    final created = ConversationSummary.tryParse(J.map(reply));
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The chat may have been started.',
      );
    }
    return created;
  }

  /// Marks every message in the conversation read (one receipt upsert each on
  /// the server, so call it once per open, not per message).
  Future<void> markRead(String conversationId) async {
    await _api.put('messaging/conversations/$conversationId/read');
  }

  // ---- notifications -----------------------------------------------------

  /// One page of the person's notifications, newest first:
  /// `GET /notifications/me`. `page` and `limit` are always sent. [unread] and
  /// [category] narrow the list on a server that supports them; an older server
  /// ignores them, so the screen applies them again to what comes back.
  Future<NotificationPage> notifications({
    int page = 1,
    int limit = 30,
    bool? unread,
    String? category,
  }) async {
    final body = await _api.get(
      'notifications/me',
      query: {
        'page': page,
        'limit': limit,
        'unread': unread == true ? 'true' : null,
        'category': category,
      },
    );
    final paged = J.paged(body);
    return NotificationPage(
      paged.items
          .map(NotificationItem.tryParse)
          .whereType<NotificationItem>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// How many notifications are unread, counted by the server:
  /// `GET /notifications/unread-count`. Null when the server cannot say (an older
  /// server answers 404), so the caller counts what it has loaded instead.
  Future<int?> unreadCount() async {
    try {
      return J.integer(
        J.map(await _api.get('notifications/unread-count'))['count'],
      );
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// The unread total a notification change answers with (`unreadCount`), when
  /// the server sends it.
  static int? _unreadIn(Object? body) => J.integer(J.map(body)['unreadCount']);

  /// Marks one read: `PATCH /notifications/:id/read`. Setting it again is
  /// harmless. Returns the server's unread total when it says.
  Future<int?> markNotificationRead(String id) async => _unreadIn(
    await _api.patch('notifications/$id/read', body: {'isRead': true}),
  );

  /// Marks every notification (or every one of [category]) read:
  /// `PATCH /notifications/read-all`. Harmless to repeat. A server without it
  /// answers 404, which is thrown for the caller to handle.
  Future<int?> markAllNotificationsRead({String? category}) async {
    final reply = await _api.patch(
      category == null
          ? 'notifications/read-all'
          : 'notifications/read-all?category=$category',
    );
    return _unreadIn(reply);
  }

  /// Removes a notification from the person's list:
  /// `DELETE /notifications/:id`. Harmless to repeat. A server without it
  /// answers 404 or 405, which is thrown for the caller to handle.
  Future<int?> deleteNotification(String id) async =>
      _unreadIn(await _api.delete('notifications/$id'));

  /// The person's alert switches: `GET /notifications/preferences`. A server
  /// that does not have them (404) is reported as unsupported.
  Future<NotificationPreferences> notificationPreferences() async {
    try {
      return NotificationPreferences.parse(
        await _api.get('notifications/preferences'),
      );
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.notFound) {
        return NotificationPreferences.unsupported;
      }
      rethrow;
    }
  }

  /// Saves the switches: `PUT /notifications/preferences`. It sets values, so
  /// sending it again is harmless. A server that cannot keep them yet answers 400
  /// with a message (or 404), which is thrown for the caller to show.
  Future<NotificationPreferences> saveNotificationPreferences(
    List<NotificationPreference> preferences,
  ) async => NotificationPreferences.parse(
    await _api.put(
      'notifications/preferences',
      body: {
        'preferences': [
          for (final p in preferences)
            {'category': p.category, 'inApp': p.inApp, 'push': p.push},
        ],
      },
    ),
  );
}
