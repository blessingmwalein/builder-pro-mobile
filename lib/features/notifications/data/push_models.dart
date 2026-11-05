import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// The app screen an alert opens, or null when the path is not one the app
/// should follow.
///
/// An alert comes from outside the app, so it may only point INTO it: a path
/// that starts with a single slash. Anything with a scheme or host (`https:`,
/// `//evil.test`), a backslash or a control character is dropped, so a crafted
/// alert can never send the app to another address. The router still applies the
/// person's permissions to whatever this returns.
String? safeAppRoute(String? raw) {
  final r = raw?.trim();
  if (r == null || r.isEmpty) return null;
  if (!r.startsWith('/') || r.startsWith('//')) return null;
  if (r.contains('://') ||
      r.contains(r'\') ||
      r.contains(RegExp(r'[\x00-\x1f]'))) {
    return null;
  }
  return r;
}

/// One alert the phone received, from the push service.
@immutable
class PushMessage {
  const PushMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.route,
    this.notificationId,
    this.category,
    this.event,
  });

  /// The server's notification id when the alert carried one (so it is not
  /// listed twice next to the server's own list), else the push message id.
  final String id;
  final String title;
  final String body;
  final DateTime receivedAt;

  /// Already checked with [safeAppRoute].
  final String? route;

  /// The server's notification id, only when the alert carried one: it is what
  /// can be marked read on the server.
  final String? notificationId;

  /// The kind of alert (`tasks`, `time`...) and what happened, when the server
  /// said.
  final String? category;
  final String? event;

  /// Reads the parts a push message is made of. [data] is what the server put
  /// in the message: `notificationId` (its id for this alert) and `route`.
  factory PushMessage.fromParts({
    String? messageId,
    String? title,
    String? body,
    Map<String, dynamic> data = const {},
    DateTime? now,
  }) {
    String? text(Object? v) {
      final s = v?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return PushMessage(
      id: text(data['notificationId']) ?? text(messageId) ?? const Uuid().v4(),
      title: text(title) ?? text(data['title']) ?? 'ownit2buildit',
      body: text(body) ?? text(data['body']) ?? '',
      receivedAt: now ?? DateTime.now(),
      route: safeAppRoute(text(data['route'])),
      notificationId: text(data['notificationId']),
      category: text(data['category']),
      event: text(data['event']),
    );
  }
}
