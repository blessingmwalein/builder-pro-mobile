import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/offline/app_database.dart';
import 'tasks_repository.dart';

/// Task status changes made while offline, replayed when the connection is back.
///
/// Only status changes go through here: setting a status is idempotent, so
/// replaying (even twice) is harmless. Non-idempotent writes (clock in/out,
/// material usage, checklist toggles) are never queued.
class TaskStatusOutbox {
  TaskStatusOutbox(this._db, this._repo, this.userId);

  final AppDatabase _db;
  final TasksRepository _repo;
  final String userId;

  static const kind = 'task_status';
  static const _uuid = Uuid();

  bool _flushing = false;

  /// True when the last [flush] stopped because the server could not be
  /// reached. Callers use it to skip a second doomed request on a bad network.
  bool networkBlocked = false;

  Future<void> queue(String taskId, String status) => _db.enqueue(
    id: _uuid.v4(),
    userId: userId,
    kind: kind,
    targetId: taskId,
    payload: jsonEncode({'status': status}),
  );

  Future<void> discard(String opId) => _db.removeOp(opId);

  /// A direct write just succeeded for this task, so older queued ones are stale.
  Future<void> discardFor(String taskId) =>
      _db.removeOpsFor(userId, kind, taskId);

  /// Moves a refused change back to the queue and tries it again.
  Future<void> retry(String opId) async {
    await _db.markPending(opId);
    await flush();
  }

  /// Sends queued changes oldest first. Returns how many reached the server.
  ///
  /// Network trouble, 5xx and rate limits stop the run and leave the rest queued
  /// for the next attempt. A definite refusal (task gone, no permission, invalid)
  /// marks that change `failed` so the user is told instead of it looping.
  Future<int> flush() async {
    if (_flushing) return 0;
    _flushing = true;
    networkBlocked = false;
    var sent = 0;
    try {
      final ops = (await _db.outboxFor(userId))
          .where((o) => o.kind == kind && o.status == 'pending')
          .toList();
      for (final op in ops) {
        final status = _statusOf(op.payload);
        if (status == null) {
          await _db.markFailed(op.id, 'Unreadable queued change.');
          continue;
        }
        try {
          await _repo.updateStatus(op.targetId, status);
          await _db.removeOp(op.id);
          sent++;
        } on AppException catch (e) {
          await _db.recordAttempt(op.id);
          if (e.isNetwork || e.outcomeUnknown) networkBlocked = true;
          if (_shouldRetryLater(e)) break;
          await _db.markFailed(op.id, e.message);
        }
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  bool _shouldRetryLater(AppException e) =>
      e.isRetryable ||
      e.kind == AppErrorKind.unauthorized ||
      e.kind == AppErrorKind.subscription ||
      e.kind == AppErrorKind.cancelled;

  String? _statusOf(String payload) {
    try {
      final m = jsonDecode(payload);
      return m is Map ? m['status'] as String? : null;
    } catch (_) {
      return null;
    }
  }
}
