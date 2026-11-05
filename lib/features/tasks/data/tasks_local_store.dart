import 'dart:convert';

import '../../../core/offline/app_database.dart';
import 'task_models.dart';

/// The last tasks the server sent, kept per user so the worker can still open
/// their list and task details with no signal.
class TasksLocalStore {
  TasksLocalStore(this._db, this.userId);

  final AppDatabase _db;
  final String userId;

  static const queueScope = 'task';
  static const detailScope = 'task_detail';

  Future<void> saveQueue(List<TaskItem> tasks) => _db.replaceCache(
    userId,
    queueScope,
    [for (final t in tasks) (key: t.id, json: jsonEncode(t.raw))],
  );

  /// Null when nothing has ever been cached for this user.
  Future<({List<TaskItem> tasks, DateTime fetchedAt})?> readQueue() async {
    final rows = await _db.readCache(userId, queueScope);
    if (rows.isEmpty) return null;
    final tasks = <TaskItem>[];
    for (final r in rows) {
      final t = _decode(r.json);
      if (t != null) tasks.add(t);
    }
    return (tasks: tasks, fetchedAt: rows.first.fetchedAt);
  }

  Future<void> saveDetail(TaskItem task) =>
      _db.putCache(userId, detailScope, task.id, jsonEncode(task.raw));

  Future<TaskItem?> readDetail(String id) async {
    final row = await _db.getCache(userId, detailScope, id);
    return row == null ? null : _decode(row.json);
  }

  TaskItem? _decode(String json) {
    try {
      return TaskItem.tryParse(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }
}
