import '../data/task_models.dart';

enum TaskGroup {
  overdue('Overdue'),
  today('Today'),
  upcoming('Upcoming'),
  noDate('No due date');

  const TaskGroup(this.title);
  final String title;
}

TaskGroup groupOf(TaskItem t, DateTime now) {
  final due = t.dueDate?.toLocal();
  if (due == null) return TaskGroup.noDate;
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(due.year, due.month, due.day);
  if (day.isBefore(today)) return TaskGroup.overdue;
  if (day == today) return TaskGroup.today;
  return TaskGroup.upcoming;
}

/// Overdue → Today → Upcoming → No due date, keeping the server's order inside
/// each group (it already sorts by priority then due date). Empty groups are
/// left out. Done tasks are not shown on the worker's list.
List<(TaskGroup, List<TaskItem>)> groupTasks(
  List<TaskItem> tasks,
  DateTime now, {
  String? status,
}) {
  final buckets = {for (final g in TaskGroup.values) g: <TaskItem>[]};
  for (final t in tasks) {
    if (t.isDone) continue;
    if (status != null && t.status != status) continue;
    buckets[groupOf(t, now)]!.add(t);
  }
  return [
    for (final g in TaskGroup.values)
      if (buckets[g]!.isNotEmpty) (g, buckets[g]!),
  ];
}
