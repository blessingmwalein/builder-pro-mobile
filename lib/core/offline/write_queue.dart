import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../errors/app_exception.dart';
import 'app_database.dart';

/// Where one queued write stands.
abstract final class WriteStatus {
  /// Not sent yet.
  static const pending = 'pending';

  /// Sent, and no answer came back. It may or may not have been recorded, so it
  /// is never sent again until the server has been asked.
  static const unconfirmed = 'unconfirmed';

  /// The server refused it (or it cannot be sent as it stands). It waits for
  /// the person and holds back the writes after it in its stream.
  static const attention = 'attention';
}

enum Readiness { ready, wait, refuse }

/// Whether a write can be sent right now.
class ReadyCheck {
  const ReadyCheck(this.readiness, [this.message]);
  static const ready = ReadyCheck(Readiness.ready);
  static const wait = ReadyCheck(Readiness.wait);

  /// It can never be sent as it is (for example the clock-in it depended on was
  /// discarded). [message] is shown to the person.
  const ReadyCheck.refuse(String this.message) : readiness = Readiness.refuse;

  final Readiness readiness;
  final String? message;
}

/// What the server holds for an earlier attempt that got no answer.
class WriteArrival {
  const WriteArrival.found([this.resultId]) : arrived = true;
  const WriteArrival.missing() : arrived = false, resultId = null;

  /// The server recorded it.
  final bool arrived;

  /// The record's id on the server, when the next writes need it.
  final String? resultId;
}

/// One kind of write: how to send it and how to tell whether it already
/// arrived.
abstract class WriteHandler {
  String get kind;

  /// Whether [write] can go now. [all] is everything queued for this person.
  Future<ReadyCheck> readiness(QueuedWrite write, List<QueuedWrite> all);

  /// Sends it once. Returns the id of what the server recorded, when later
  /// writes need it. Throws [AppException].
  Future<String?> send(QueuedWrite write);

  /// Asks the server whether an earlier, unanswered attempt arrived. Throws
  /// [AppException] when the server cannot be asked.
  Future<WriteArrival> arrived(QueuedWrite write);
}

enum _Outcome { notSent, unknown, refused }

/// Events recorded without a connection that must reach the server exactly
/// once, sent oldest first.
///
/// The server has no way to tell a repeat from a second event, so a write is
/// sent again only when it is certain the first attempt did not land:
///
/// * a connection that never opened (offline, connect timeout, 429, 401) means
///   nothing was delivered: it stays `pending` and is tried later;
/// * a timeout after sending, a 5xx or an unreadable reply means it may have
///   been recorded: it becomes `unconfirmed`, waits out [cooldown] (so a slow
///   first request can finish) and is then looked up on the server, by the
///   exact moment it happened, before anything is sent again;
/// * a refusal (400, 403, 404…) is an answer, not a failure: it needs the
///   person and is never retried on its own.
///
/// A stream holds its writes in order, so a clock-out is never sent before its
/// clock-in, and one that needs attention holds back what follows it.
class WriteQueue {
  WriteQueue({
    required this._db,
    required this.userId,
    required List<WriteHandler> handlers,
    this.cooldown = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _handlers = {for (final h in handlers) h.kind: h},
       _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String userId;
  final Map<String, WriteHandler> _handlers;

  /// How long an unanswered write is left alone before the server is asked.
  final Duration cooldown;
  final DateTime Function() _now;

  final _sent = StreamController<String>.broadcast();

  /// The kind of each write the server recorded, so screens can refresh.
  Stream<String> get sent => _sent.stream;

  bool _flushing = false;
  bool _again = false;
  bool _disposed = false;
  Timer? _wake;

  Stream<List<QueuedWrite>> watch() => _db.watchQueuedWrites(userId);

  Future<List<QueuedWrite>> all() => _db.queuedWritesFor(userId);

  /// Saves a write. [payload] must carry the moment the event happened.
  Future<QueuedWrite> enqueue({
    required String kind,
    required String stream,
    required Map<String, dynamic> payload,
    String? id,
  }) async {
    final writeId = id ?? const Uuid().v4();
    await _db.addQueuedWrite(
      id: writeId,
      userId: userId,
      kind: kind,
      stream: stream,
      payload: jsonEncode(payload),
    );
    final saved = (await all()).where((w) => w.id == writeId);
    return saved.first;
  }

  /// Puts a write that needed attention back in the queue (the person chose to
  /// try again) and sends what can go.
  Future<void> retry(String id) async {
    await _db.setQueuedStatus(id, WriteStatus.pending);
    await flush();
  }

  /// Gives up on a write, and on the writes that depend on it. Returns how many
  /// were removed.
  Future<int> discard(String id) async {
    var removed = 0;
    final queued = await all();
    final ids = <String>{id};
    // Anything that waits for this write's result goes with it.
    var grew = true;
    while (grew) {
      grew = false;
      for (final w in queued) {
        if (ids.contains(w.id)) continue;
        if (ids.contains(_decode(w.payload)['dependsOn'])) {
          ids.add(w.id);
          grew = true;
        }
      }
    }
    for (final w in queued) {
      if (ids.contains(w.id)) {
        await _db.removeQueuedWrite(w.id);
        removed++;
      }
    }
    return removed;
  }

  /// Sends what can be sent, in order. Safe to call at any time and from
  /// several places: overlapping calls run one after the other.
  Future<void> flush() async {
    if (_disposed) return;
    if (_flushing) {
      _again = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _again = false;
        await _flushOnce();
      } while (_again && !_disposed);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushOnce() async {
    final queued = await all();
    final held = <String>{};
    Duration? wakeIn;

    for (final w in queued) {
      if (_disposed) return;
      if (held.contains(w.stream)) continue;
      if (w.status == WriteStatus.attention) {
        held.add(w.stream);
        continue;
      }
      final handler = _handlers[w.kind];
      if (handler == null) {
        held.add(w.stream);
        continue;
      }

      final check = await handler.readiness(w, queued);
      if (check.readiness == Readiness.refuse) {
        await _db.setQueuedStatus(
          w.id,
          WriteStatus.attention,
          error: check.message,
        );
        held.add(w.stream);
        continue;
      }
      if (check.readiness == Readiness.wait) {
        held.add(w.stream);
        continue;
      }

      if (w.status == WriteStatus.unconfirmed) {
        final left = _cooldownLeft(w);
        if (left > Duration.zero) {
          held.add(w.stream);
          wakeIn = _sooner(wakeIn, left);
          continue;
        }
        try {
          final seen = await handler.arrived(w);
          if (seen.arrived) {
            await _recorded(w, seen.resultId);
            continue;
          }
          // Asked, and it is not there: safe to send again.
        } on AppException catch (e) {
          if (_stopsEverything(e)) return;
          // Could not even ask: it stays unconfirmed, and so does what follows.
          held.add(w.stream);
          continue;
        }
      }

      await _db.recordQueuedAttempt(w.id);
      try {
        final resultId = await handler.send(w);
        await _recorded(w, resultId);
      } on AppException catch (e) {
        switch (_classify(e)) {
          case _Outcome.notSent:
            // Nothing was delivered. Stop: the rest cannot go either.
            await _db.setQueuedStatus(w.id, WriteStatus.pending);
            return;
          case _Outcome.unknown:
            await _db.setQueuedStatus(
              w.id,
              WriteStatus.unconfirmed,
              error: e.message,
              attempted: true,
            );
            held.add(w.stream);
            wakeIn = _sooner(wakeIn, cooldown);
          case _Outcome.refused:
            await _db.setQueuedStatus(
              w.id,
              WriteStatus.attention,
              error: e.message,
            );
            held.add(w.stream);
        }
      }
    }
    if (wakeIn != null) _scheduleWake(wakeIn);
  }

  /// A write the server recorded: remove it, and hand its result to the writes
  /// that were waiting for it (a clock-out needs the clock-in's entry id).
  Future<void> _recorded(QueuedWrite w, String? resultId) async {
    await _db.removeQueuedWrite(w.id);
    if (resultId != null) {
      for (final other in await all()) {
        final payload = _decode(other.payload);
        if (payload['dependsOn'] == w.id) {
          payload['dependsOnResult'] = resultId;
          await _db.updateQueuedPayload(other.id, jsonEncode(payload));
          // This round's snapshot still has the old copy of that write, so
          // run once more now that it can go.
          _again = true;
        }
      }
    }
    if (!_sent.isClosed) _sent.add(w.kind);
  }

  Duration _cooldownLeft(QueuedWrite w) {
    final last = w.lastAttemptAt ?? w.createdAt;
    return last.add(cooldown).difference(_now());
  }

  Duration _sooner(Duration? a, Duration b) => (a == null || b < a) ? b : a;

  void _scheduleWake(Duration after) {
    _wake?.cancel();
    if (_disposed) return;
    // A little extra so the cool-down has certainly passed when it fires.
    _wake = Timer(after + const Duration(seconds: 1), flush);
  }

  /// Errors after which sending anything else this round is pointless.
  bool _stopsEverything(AppException e) =>
      e.isNetwork ||
      e.kind == AppErrorKind.unauthorized ||
      e.kind == AppErrorKind.subscription ||
      e.kind == AppErrorKind.rateLimited;

  _Outcome _classify(AppException e) {
    if (_stopsEverything(e)) return _Outcome.notSent;
    if (e.outcomeUnknown ||
        e.kind == AppErrorKind.server ||
        e.kind == AppErrorKind.malformed) {
      return _Outcome.unknown;
    }
    return _Outcome.refused;
  }

  void dispose() {
    _disposed = true;
    _wake?.cancel();
    _sent.close();
  }

  static Map<String, dynamic> _decode(String payload) {
    try {
      final v = jsonDecode(payload);
      return v is Map<String, dynamic> ? v : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
