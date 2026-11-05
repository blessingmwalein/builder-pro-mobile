import 'package:flutter/foundation.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/json.dart';
import '../../notifications/data/push_models.dart' show safeAppRoute;

/// `Mary Moyo` → `MM`; one word gives its first two letters.
String chatInitials(String name) {
  final words = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}

/// Photos a chat accepts (the server takes these four; a HEIC photo is refused).
const chatImageMimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

/// Documents a chat accepts from the phone's files.
const chatFileMimeTypes = {
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'txt': 'text/plain',
  'csv': 'text/csv',
};

/// The server refuses chat files above 20 MB.
const maxChatFileBytes = 20 * 1024 * 1024;

/// How many files one message may carry.
const maxChatFiles = 10;

/// The type the server accepts for this file name, or null when it takes none.
String? chatMimeFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return chatImageMimeTypes[ext] ?? chatFileMimeTypes[ext];
}

/// What a chat message with only an attachment is called in a list or a quote.
String attachmentLabel(String? contentType) {
  if (contentType == null || contentType.isEmpty) return '';
  if (contentType.startsWith('audio/')) return 'Voice message';
  if (contentType.startsWith('image/')) return 'Photo';
  return 'File';
}

/// Someone in a chat.
@immutable
class ChatPerson {
  const ChatPerson({required this.id, required this.name, this.avatarUrl});

  final String id;
  final String name;
  final String? avatarUrl;

  String get initials => chatInitials(name);

  static ChatPerson? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final name = '${J.strOr(m['firstName'])} ${J.strOr(m['lastName'])}'.trim();
    return ChatPerson(
      id: id,
      name: name.isEmpty ? J.strOr(m['name'], 'Team member') : name,
      avatarUrl: J.str(m['avatarUrl']),
    );
  }

  @override
  bool operator ==(Object other) => other is ChatPerson && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A file that was sent in a chat: a photo, a document or a voice message.
@immutable
class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.url,
    this.fileKey,
    this.durationMs,
  });

  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String? url;
  final String? fileKey;

  /// How long a voice message lasts, when the server kept it.
  final int? durationMs;

  bool get isImage => contentType.startsWith('image/');
  bool get isAudio => contentType.startsWith('audio/');
  String get sizeLabel => Fmt.bytes(sizeBytes);

  /// Where to open it from. The address the server sent is used unless it points
  /// at the server's own `localhost` (which a phone cannot reach); then it is
  /// built from the API host and the file key instead.
  String? addressFor(String origin) {
    final sent = url;
    if (sent != null) {
      final host = Uri.tryParse(sent)?.host ?? '';
      if (host.isNotEmpty && host != 'localhost' && host != '127.0.0.1') {
        return sent;
      }
    }
    final key = fileKey;
    if (key == null || key.isEmpty) return sent;
    return '$origin/uploads/$key';
  }

  static ChatAttachment? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = J.str(m['fileName']);
    if (id == null || name == null) return null;
    return ChatAttachment(
      id: id,
      fileName: name,
      contentType: J.strOr(m['contentType'], 'application/octet-stream'),
      sizeBytes: J.integer(m['sizeBytes']) ?? 0,
      url: J.str(m['url']),
      fileKey: J.str(m['fileKey']),
      durationMs: J.integer(m['durationMs']),
    );
  }
}

/// What the server answers after a file is uploaded, to be named in the message
/// that carries it.
@immutable
class UploadedFile {
  const UploadedFile({
    required this.fileKey,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    this.url,
    this.durationMs,
  });

  final String fileKey;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String? url;
  final int? durationMs;

  UploadedFile withDuration(int? ms) => UploadedFile(
    fileKey: fileKey,
    fileName: fileName,
    contentType: contentType,
    sizeBytes: sizeBytes,
    url: url,
    durationMs: ms,
  );

  Map<String, Object?> toBody() => {
    'fileKey': fileKey,
    'fileName': fileName,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    'durationMs': ?durationMs,
  };

  static UploadedFile? tryParse(Object? raw) {
    final m = J.map(raw);
    final key = J.str(m['fileKey']);
    if (key == null) return null;
    return UploadedFile(
      fileKey: key,
      fileName: J.strOr(m['fileName'], 'file'),
      contentType: J.strOr(m['contentType'], 'application/octet-stream'),
      sizeBytes: J.integer(m['sizeBytes']) ?? 0,
      url: J.str(m['url']),
    );
  }
}

/// A file chosen on the phone, on its way into a message. Once uploaded it keeps
/// the server's answer, so trying a failed message again does not upload it twice.
@immutable
class PendingFile {
  const PendingFile({
    required this.path,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    this.durationMs,
    this.uploaded,
  });

  final String path;
  final String name;
  final String contentType;
  final int sizeBytes;
  final int? durationMs;
  final UploadedFile? uploaded;

  bool get isImage => contentType.startsWith('image/');
  bool get isAudio => contentType.startsWith('audio/');

  PendingFile withUploaded(UploadedFile u) => PendingFile(
    path: path,
    name: name,
    contentType: contentType,
    sizeBytes: sizeBytes,
    durationMs: durationMs,
    uploaded: u.withDuration(durationMs),
  );
}

/// The message being answered, shown as a quote above a reply.
@immutable
class ReplyPreview {
  const ReplyPreview({
    required this.messageId,
    required this.senderName,
    required this.text,
    this.senderId,
    this.attachmentContentType,
  });

  /// Empty for a quote that was written into the text (an older server).
  final String messageId;
  final String senderName;
  final String text;
  final String? senderId;
  final String? attachmentContentType;

  /// The words quoted: the text, or what the attachment is.
  String get snippet {
    final t = text.trim();
    return t.isNotEmpty ? t : attachmentLabel(attachmentContentType);
  }

  /// A quote carried in the text itself, used when the server cannot keep
  /// replies: `> Mary: See you at 8` on its own first line.
  String asTextQuote() {
    final one = snippet.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = one.length > 80 ? '${one.substring(0, 80)}…' : one;
    return '> $senderName: $short\n';
  }

  static ReplyPreview? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    return ReplyPreview(
      messageId: id,
      senderName: J.strOr(m['senderName'], 'Team member'),
      text: J.strOr(m['body']),
      senderId: J.str(m['senderId']),
      attachmentContentType: J.str(m['attachmentContentType']),
    );
  }
}

/// A message body that starts with a quote line (`> Name: words`), split into the
/// quote and what the sender wrote after it. Null when it has none.
({ReplyPreview quote, String rest})? splitTextQuote(String body) {
  if (!body.startsWith('> ')) return null;
  final end = body.indexOf('\n');
  final line = end < 0 ? body.substring(2) : body.substring(2, end);
  final colon = line.indexOf(': ');
  if (colon <= 0) return null;
  final rest = end < 0 ? '' : body.substring(end + 1);
  return (
    quote: ReplyPreview(
      messageId: '',
      senderName: line.substring(0, colon),
      text: line.substring(colon + 2),
    ),
    rest: rest,
  );
}

/// What the server can do beyond plain text. An older server answers 404 to the
/// capabilities call; then nothing beyond plain text is offered.
@immutable
class ChatCapabilities {
  const ChatCapabilities({
    this.attachments = false,
    this.voice = false,
    this.replies = false,
    this.mentions = false,
    this.unread = false,
  });

  static const legacy = ChatCapabilities();

  final bool attachments;
  final bool voice;
  final bool replies;
  final bool mentions;
  final bool unread;

  static ChatCapabilities parse(Object? raw) {
    final m = J.map(raw);
    return ChatCapabilities(
      attachments: J.boolean(m['attachments']),
      voice: J.boolean(m['voice']),
      replies: J.boolean(m['replies']),
      mentions: J.boolean(m['mentions']),
      unread: J.boolean(m['unread']),
    );
  }
}

@immutable
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.type,
    required this.updatedAt,
    this.title,
    this.projectId,
    this.projectName,
    this.participants = const [],
    this.unreadCount = 0,
    this.lastBody,
    this.lastSender,
    this.lastSenderId,
    this.lastAt,
    this.lastAttachmentType,
    this.lastAttachmentCount = 0,
  });

  final String id;

  /// `DIRECT` or `PROJECT` (a group, linked to a project).
  final String type;
  final String? title;
  final String? projectId;
  final String? projectName;
  final DateTime updatedAt;
  final List<ChatPerson> participants;
  final int unreadCount;
  final String? lastBody;
  final String? lastSender;
  final String? lastSenderId;
  final DateTime? lastAt;
  final String? lastAttachmentType;
  final int lastAttachmentCount;

  bool get isProject => type == 'PROJECT';

  /// A group chat (a project channel or a group made for a project).
  bool get isGroup => isProject;

  /// The other person in a direct chat.
  ChatPerson? otherPerson(String? myId) =>
      participants.where((p) => p.id != myId).firstOrNull;

  /// What the conversation is called: its name, or for a direct chat the other
  /// person.
  String titleFor(String? myId) {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    if (isProject) return projectName ?? 'Project channel';
    return otherPerson(myId)?.name ?? lastSender ?? 'Direct message';
  }

  String get displayTitle => titleFor(null);

  /// Second line of a group's row: the project, when the group has its own name.
  String? subtitleFor(String? myId) {
    if (!isProject) return null;
    final t = title?.trim();
    return t != null && t.isNotEmpty && projectName != null
        ? projectName
        : null;
  }

  /// The last message as a line for the list.
  String previewFor(String? myId) {
    var text = (lastBody ?? '').trim();
    final quoted = splitTextQuote(text);
    if (quoted != null) text = quoted.rest.trim();
    if (text.isEmpty && lastAttachmentCount > 0) {
      text = lastAttachmentCount > 1
          ? '$lastAttachmentCount files'
          : attachmentLabel(lastAttachmentType);
    }
    if (text.isEmpty) return 'No messages yet';
    if (lastSenderId != null && lastSenderId == myId) return 'You: $text';
    if (isProject && lastSender != null) return '$lastSender: $text';
    return text;
  }

  ConversationSummary withUnread(int count) => ConversationSummary(
    id: id,
    type: type,
    updatedAt: updatedAt,
    title: title,
    projectId: projectId,
    projectName: projectName,
    participants: participants,
    unreadCount: count,
    lastBody: lastBody,
    lastSender: lastSender,
    lastSenderId: lastSenderId,
    lastAt: lastAt,
    lastAttachmentType: lastAttachmentType,
    lastAttachmentCount: lastAttachmentCount,
  );

  static ConversationSummary? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final last = J.maps(m['messages']).firstOrNull;
    final sender = J.map(last?['sender']);
    final senderName =
        '${J.strOr(sender['firstName'])} ${J.strOr(sender['lastName'])}'.trim();
    final attachments = J.maps(last?['attachments']);
    final project = J.map(m['project']);
    return ConversationSummary(
      id: id,
      type: J.strOr(m['type'], 'DIRECT'),
      title: J.str(m['title']),
      projectId: J.str(m['projectId']) ?? J.str(project['id']),
      projectName: J.str(project['name']),
      updatedAt: J.date(m['updatedAt']) ?? DateTime.now(),
      participants: [
        for (final p in J.maps(m['participants']))
          ?ChatPerson.tryParse(p['user']),
      ],
      unreadCount: J.integer(m['unreadCount']) ?? 0,
      lastBody: last == null ? null : J.str(last['body']),
      lastSender: senderName.isEmpty ? null : senderName,
      lastSenderId: last == null ? null : J.str(last['senderId']),
      lastAt: last == null ? null : J.date(last['createdAt']),
      lastAttachmentType: attachments.isEmpty
          ? null
          : J.str(attachments.first['contentType']),
      lastAttachmentCount: attachments.length,
    );
  }
}

enum SendState {
  /// Saved by the server.
  sent,

  /// On the phone, request in progress.
  sending,

  /// The request failed; nothing (or maybe something) was saved.
  failed,
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.attachments = const [],
    this.replyTo,
    this.mentionedUserIds = const [],
    this.pending = const [],
    this.progress,
    this.state = SendState.sent,
    this.error,
    this.maybeSent = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;
  final List<ChatAttachment> attachments;
  final ReplyPreview? replyTo;
  final List<String> mentionedUserIds;

  /// Files still on this phone while the message is being sent.
  final List<PendingFile> pending;

  /// How much of the upload is done (0 to 1), while sending.
  final double? progress;
  final SendState state;
  final String? error;

  /// A failed send whose outcome is unknown: it may already be on the server.
  final bool maybeSent;

  bool get isLocal => state != SendState.sent;
  int get attachmentCount => attachments.length + pending.length;

  ChatMessage copyWith({
    SendState? state,
    String? error,
    bool? maybeSent,
    List<PendingFile>? pending,
    double? progress,
    bool clearError = false,
    bool clearProgress = false,
  }) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    senderName: senderName,
    body: body,
    createdAt: createdAt,
    attachments: attachments,
    replyTo: replyTo,
    mentionedUserIds: mentionedUserIds,
    pending: pending ?? this.pending,
    progress: clearProgress ? null : (progress ?? this.progress),
    state: state ?? this.state,
    error: clearError ? null : (error ?? this.error),
    maybeSent: maybeSent ?? this.maybeSent,
  );

  static ChatMessage? tryParse(
    Map<String, dynamic> m, {
    String? conversationId,
  }) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final sender = J.map(m['sender']);
    final name =
        '${J.strOr(sender['firstName'])} ${J.strOr(sender['lastName'])}'.trim();
    var body = J.strOr(m['body']);
    var reply = ReplyPreview.tryParse(m['replyTo']);
    if (reply == null) {
      // A reply sent through a server that cannot keep them carries its quote in
      // the text.
      final quoted = splitTextQuote(body);
      if (quoted != null) {
        reply = quoted.quote;
        body = quoted.rest;
      }
    }
    return ChatMessage(
      id: id,
      conversationId: J.strOr(m['conversationId'], conversationId ?? ''),
      senderId: J.strOr(m['senderId'], J.strOr(sender['id'])),
      senderName: name.isEmpty ? 'Team member' : name,
      body: body,
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      attachments: [
        for (final a in J.maps(m['attachments'])) ?ChatAttachment.tryParse(a),
      ],
      replyTo: reply,
      mentionedUserIds: [
        for (final v in J.list(m['mentionedUserIds'])) ?J.str(v),
      ],
    );
  }
}

@immutable
class MessagePage {
  const MessagePage(this.messages, {required this.page, required this.hasMore});

  /// Oldest first within the page.
  final List<ChatMessage> messages;
  final int page;

  /// An older page exists.
  final bool hasMore;
}

/// The kind of alert a notification belongs to when the server did not say (an
/// older server): worked out from its `type`.
String? notificationCategoryForType(String? type) {
  if (type == null) return null;
  if (type.startsWith('TASK_')) return 'tasks';
  if (type.startsWith('INVOICE_') ||
      type.startsWith('QUOTE_') ||
      type == 'BUDGET_THRESHOLD') {
    return 'finance';
  }
  if (type == 'TIMESHEET_APPROVAL_REQUIRED') return 'time';
  if (type == 'STOCK_LOW') return 'materials';
  if (type == 'PROJECT_DEADLINE' || type == 'PROJECT_INVITE') return 'projects';
  return null;
}

@immutable
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    this.route,
    this.type,
    this.category,
    this.event,
    this.entityType,
    this.entityId,
    this.projectId,
    this.actorName,
  });

  final String id;
  final String title;
  final String body;
  final bool isRead;
  final DateTime createdAt;

  /// The app screen it is about (the server's `metadata.route`), checked to be
  /// an in-app path.
  final String? route;

  /// The server's own kind (`TASK_ASSIGNED`, `GENERAL`...).
  final String? type;

  /// Which switch it belongs to (`tasks`, `time`, `finance`...): the server's
  /// `metadata.category`, or worked out from [type] on an older server.
  final String? category;

  /// What happened (`time.submitted`...), when the server says.
  final String? event;
  final String? entityType;
  final String? entityId;
  final String? projectId;

  /// Who did it, when the server says.
  final String? actorName;

  NotificationItem asRead() => NotificationItem(
    id: id,
    title: title,
    body: body,
    isRead: true,
    createdAt: createdAt,
    route: route,
    type: type,
    category: category,
    event: event,
    entityType: entityType,
    entityId: entityId,
    projectId: projectId,
    actorName: actorName,
  );

  static NotificationItem? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final meta = J.map(m['metadata']);
    final type = J.str(m['type']);
    return NotificationItem(
      id: id,
      title: J.strOr(m['title'], 'Notification'),
      body: J.strOr(m['body']),
      isRead: J.boolean(m['isRead']),
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      route: safeAppRoute(J.str(meta['route'])),
      type: type,
      category: J.str(meta['category']) ?? notificationCategoryForType(type),
      event: J.str(meta['event']),
      entityType: J.str(meta['entityType']),
      entityId: J.str(meta['entityId']),
      projectId: J.str(meta['projectId']),
      actorName: J.str(meta['actorName']),
    );
  }
}

/// One page of the server's notification list.
@immutable
class NotificationPage {
  const NotificationPage(
    this.items, {
    required this.page,
    required this.hasMore,
  });
  final List<NotificationItem> items;
  final int page;

  /// A later page exists.
  final bool hasMore;
}

/// One kind of alert's switches: whether it is kept in the app's list and
/// whether it is sent to the phone.
@immutable
class NotificationPreference {
  const NotificationPreference({
    required this.category,
    required this.label,
    this.inApp = true,
    this.push = true,
  });

  final String category;
  final String label;
  final bool inApp;
  final bool push;

  NotificationPreference copyWith({bool? inApp, bool? push}) =>
      NotificationPreference(
        category: category,
        label: label,
        inApp: inApp ?? this.inApp,
        push: push ?? this.push,
      );

  static NotificationPreference? tryParse(Map<String, dynamic> m) {
    final category = J.str(m['category']);
    if (category == null) return null;
    return NotificationPreference(
      category: category,
      label: J.strOr(m['label'], category),
      inApp: J.boolean(m['inApp'], fallback: true),
      push: J.boolean(m['push'], fallback: true),
    );
  }
}

/// The switches the server keeps for the signed-in person. [supported] is false
/// when the server has no place to keep them yet (an older server, or the
/// database update has not been run): everything is on.
@immutable
class NotificationPreferences {
  const NotificationPreferences({
    required this.supported,
    required this.categories,
  });

  static const unsupported = NotificationPreferences(
    supported: false,
    categories: [],
  );

  final bool supported;
  final List<NotificationPreference> categories;

  NotificationPreferences withCategory(NotificationPreference next) =>
      NotificationPreferences(
        supported: supported,
        categories: [
          for (final c in categories) c.category == next.category ? next : c,
        ],
      );

  static NotificationPreferences parse(Object? raw) {
    final m = J.map(raw);
    final list = [
      for (final c in J.maps(m['categories']))
        ?NotificationPreference.tryParse(c),
    ];
    return NotificationPreferences(
      supported: J.boolean(m['supported'], fallback: list.isNotEmpty),
      categories: list,
    );
  }
}
