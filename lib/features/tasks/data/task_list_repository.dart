import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'task_models.dart';

/// A page of tasks from `GET /tasks` (company-wide for users with `tasks.*`).
class TaskPage {
  const TaskPage(this.items, {required this.total});
  final List<TaskItem> items;

  /// Matching tasks on the server (may exceed [items]).
  final int total;

  bool get truncated => total > items.length;
}

/// Tasks that are not finished, across all statuses the app cares about.
class OpenTasks {
  const OpenTasks(this.tasks, {required this.truncated});
  final List<TaskItem> tasks;

  /// More open tasks exist than were loaded (the lists are capped per status).
  final bool truncated;

  List<TaskItem> get blocked =>
      tasks.where((t) => t.status == TaskStatus.blocked).toList();

  List<TaskItem> overdue(DateTime now) =>
      tasks.where((t) => t.isOverdue(now)).toList();

  List<TaskItem> dueToday(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return tasks.where((t) {
      final due = t.dueDate?.toLocal();
      if (due == null || t.isDone) return false;
      return DateTime(due.year, due.month, due.day) == today;
    }).toList();
  }
}

/// Task lists for supervisors and managers. The API has no "not done" or "due"
/// filter, so open work is read one status at a time.
class TaskListRepository {
  TaskListRepository(this._api);

  final ApiClient _api;

  static const pageSize = 100;

  Future<TaskPage> list({
    String? status,
    String? projectId,
    int page = 1,
    int limit = pageSize,
  }) async {
    final body = await _api.get(
      'tasks',
      query: {
        'page': page,
        'limit': limit,
        'status': status,
        'projectId': projectId,
      },
    );
    final paged = J.paged(body);
    return TaskPage(
      paged.items.map(TaskItem.tryParse).whereType<TaskItem>().toList(),
      total: paged.total,
    );
  }

  /// To do, in progress, blocked and in review (everything but done), loaded in
  /// parallel. Any failure fails the whole read, so the screen never shows a
  /// partial picture as if it were complete.
  Future<OpenTasks> open() async {
    const statuses = [
      TaskStatus.blocked,
      TaskStatus.inProgress,
      TaskStatus.review,
      TaskStatus.todo,
    ];
    final pages = await Future.wait([
      for (final s in statuses) list(status: s),
    ]);
    return OpenTasks([
      for (final p in pages) ...p.items,
    ], truncated: pages.any((p) => p.truncated));
  }
}
