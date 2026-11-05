import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../projects/application/projects_providers.dart';
import '../../today/application/today_providers.dart';
import '../data/task_list_repository.dart';
import '../data/task_models.dart';
import 'tasks_providers.dart';

/// What the worker typed on the "new task" form.
class NewTaskInput {
  const NewTaskInput({
    required this.projectId,
    required this.title,
    this.description,
    this.priority = 'MEDIUM',
    this.dueDate,
    this.estimatedHours,
    this.assigneeIds = const [],
    this.stageId,
  });

  final String projectId;
  final String title;
  final String? description;
  final String priority;
  final DateTime? dueDate;
  final double? estimatedHours;
  final List<String> assigneeIds;

  /// The timeline stage to link the task to, if any.
  final String? stageId;
}

class CreatedTask {
  const CreatedTask(this.task, {this.note});
  final TaskItem task;

  /// Explains a recovered outcome (the first reply never arrived).
  final String? note;
}

/// Creating and editing tasks.
class TaskAuthoring {
  TaskAuthoring(this._ref);
  final Ref _ref;

  /// Creates a task. Creating is not repeatable (a second call makes a second
  /// task), so after a timeout the project is searched for a task with the same
  /// title created just now before anything is offered again.
  Future<CreatedTask> create(NewTaskInput input) async {
    final repo = _ref.read(tasksRepositoryProvider);
    final startedAt = DateTime.now();
    try {
      final task = await repo.createTask(
        projectId: input.projectId,
        title: input.title,
        description: input.description,
        priority: input.priority,
        dueDate: input.dueDate,
        estimatedHours: input.estimatedHours,
        assigneeIds: input.assigneeIds,
        stageId: input.stageId,
      );
      _refreshLists(input.projectId);
      return CreatedTask(task);
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      TaskPage? page;
      try {
        // New tasks start as TO DO, so that list is the smallest place to look.
        page = await _ref
            .read(taskListRepositoryProvider)
            .list(projectId: input.projectId, status: TaskStatus.todo);
      } on AppException {
        page = null;
      }
      // Could not even look: the outcome stays unknown.
      if (page == null) rethrow;
      final since = startedAt.subtract(const Duration(minutes: 2));
      for (final t in page.items) {
        final created = t.createdAt;
        if (t.title == input.title &&
            created != null &&
            created.isAfter(since)) {
          _refreshLists(input.projectId);
          return CreatedTask(
            t,
            note: 'The task was created. The confirmation was slow, so we checked.',
          );
        }
      }
      if (page.truncated) {
        // Too many open tasks to see them all: not safe to say it was not created.
        throw const AppException(
          AppErrorKind.uncertain,
          'We could not tell whether the task was created. Check the project before adding it again.',
        );
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and no task was created. Please try again.",
      );
    }
  }

  /// Changes a task's details. It only sets fields, so after an uncertain
  /// failure it is sent once more; a second failure is reported.
  Future<void> update(
    String taskId, {
    String? title,
    String? description,
    String? priority,
    DateTime? dueDate,
    double? estimatedHours,
    String? stageId,
    bool setStage = false,
  }) async {
    final repo = _ref.read(tasksRepositoryProvider);
    Future<void> send() => repo.updateTask(
      taskId,
      title: title,
      description: description,
      priority: priority,
      dueDate: dueDate,
      estimatedHours: estimatedHours,
      stageId: stageId,
      setStage: setStage,
    );
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _ref.invalidate(openTasksProvider);
    try {
      await _ref.read(tasksProvider.notifier).refresh();
    } catch (_) {
      // The list screen shows its own error if the reload fails.
    }
  }

  void _refreshLists(String projectId) {
    _ref.invalidate(projectTasksProvider(projectId));
    _ref.invalidate(projectDetailProvider(projectId));
    _ref.invalidate(openTasksProvider);
    _ref.invalidate(tasksProvider);
  }
}

final taskAuthoringProvider = Provider<TaskAuthoring>(
  (ref) => TaskAuthoring(ref),
);
