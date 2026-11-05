import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/providers.dart';
import '../../time/data/time_models.dart';
import '../data/task_models.dart';
import '../data/task_status_outbox.dart';
import '../data/tasks_local_store.dart';
import '../data/tasks_repository.dart';

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(ref.watch(apiClientProvider)),
);

final tasksStoreProvider = Provider<TasksLocalStore?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return TasksLocalStore(ref.watch(appDatabaseProvider), uid);
});

final taskOutboxProvider = Provider<TaskStatusOutbox?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return TaskStatusOutbox(
    ref.watch(appDatabaseProvider),
    ref.watch(tasksRepositoryProvider),
    uid,
  );
});

/// Queued status changes (waiting or refused), live from the local database.
final queuedStatusOpsProvider = StreamProvider<List<OutboxOp>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(appDatabaseProvider)
      .watchOutbox(uid)
      .map((ops) => ops.where((o) => o.kind == TaskStatusOutbox.kind).toList());
});

String? _statusIn(String payload) {
  try {
    final m = jsonDecode(payload);
    return m is Map ? m['status'] as String? : null;
  } catch (_) {
    return null;
  }
}

/// taskId → status the worker set offline that has not reached the server yet.
final pendingStatusProvider = Provider<Map<String, String>>((ref) {
  final ops = ref.watch(queuedStatusOpsProvider).value ?? const [];
  final pending = <String, String>{};
  for (final o in ops) {
    final s = o.status == 'pending' ? _statusIn(o.payload) : null;
    if (s != null) pending[o.targetId] = s;
  }
  return pending;
});

/// Changes the server refused (task removed, permission lost…); the worker is told.
final failedStatusOpsProvider = Provider<List<OutboxOp>>((ref) {
  final ops = ref.watch(queuedStatusOpsProvider).value ?? const [];
  return ops.where((o) => o.status == 'failed').toList();
});

class TasksSnapshot {
  const TasksSnapshot(this.tasks, {this.fromCache = false, this.fetchedAt});

  final List<TaskItem> tasks;

  /// True when the server could not be reached and this is the saved copy.
  final bool fromCache;
  final DateTime? fetchedAt;

  TasksSnapshot withStatus(String taskId, String status) => TasksSnapshot(
    [
      for (final t in tasks)
        if (t.id == taskId) t.copyWith(status: status) else t,
    ],
    fromCache: fromCache,
    fetchedAt: fetchedAt,
  );
}

/// The worker's task queue (`GET /tasks/my-queue`) with an offline fallback.
class TasksController extends AsyncNotifier<TasksSnapshot> {
  @override
  Future<TasksSnapshot> build() async {
    final uid = ref.watch(currentUserIdProvider);
    if (uid == null) return const TasksSnapshot([]);

    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      if (prev?.value == false && next.value == true) refresh();
    });
    ref.listen<int>(appResumeProvider, (_, _) => refresh());

    final repo = ref.read(tasksRepositoryProvider);
    final store = ref.read(tasksStoreProvider);
    // Send offline changes first so the list we fetch already reflects them.
    final outbox = ref.read(taskOutboxProvider);
    await outbox?.flush();
    if (outbox?.networkBlocked == true) {
      // The server just proved unreachable: do not make the worker wait out a
      // second timeout, show what is saved. Pull-to-refresh or reconnecting
      // tries again.
      final cached = await store?.readQueue();
      if (cached != null) {
        return TasksSnapshot(
          cached.tasks,
          fromCache: true,
          fetchedAt: cached.fetchedAt,
        );
      }
    }
    try {
      final tasks = await repo.myQueue();
      await store?.saveQueue(tasks);
      return TasksSnapshot(tasks, fetchedAt: DateTime.now());
    } on AppException catch (e) {
      if (!e.isRetryable) rethrow;
      final cached = await store?.readQueue();
      if (cached == null) rethrow;
      return TasksSnapshot(
        cached.tasks,
        fromCache: true,
        fetchedAt: cached.fetchedAt,
      );
    }
  }

  /// Reloads from the server while keeping the current list on screen.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// A status change succeeded or was queued: reflect it in the list and cache.
  Future<void> applyStatus(String taskId, String status) async {
    final current = state.value;
    if (current == null) return;
    final next = current.withStatus(taskId, status);
    state = AsyncData(next);
    await ref.read(tasksStoreProvider)?.saveQueue(next.tasks);
  }
}

final tasksProvider = AsyncNotifierProvider<TasksController, TasksSnapshot>(
  TasksController.new,
);

/// Task with any status the worker set offline applied on top.
TaskItem withPendingStatus(TaskItem t, Map<String, String> pending) {
  final s = pending[t.id];
  return s == null || s == t.status ? t : t.copyWith(status: s);
}

/// Projects the worker can pick (clock in, log materials): the ones on their own
/// assigned tasks. Empty until the task list has loaded.
final workProjectsProvider = Provider<List<ProjectRef>>((ref) {
  final tasks = ref.watch(tasksProvider).value?.tasks ?? const [];
  final seen = <String>{};
  return [
    for (final t in tasks)
      if (t.project.id.isNotEmpty && seen.add(t.project.id)) t.project,
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
});

enum StatusOutcome {
  /// The server has it.
  sent,

  /// Saved on the phone; will be sent when the connection is back.
  queued,
}

/// Changing a task's status, online or offline.
class TaskActions {
  TaskActions(this._ref);
  final Ref _ref;

  Future<StatusOutcome> setStatus(String taskId, String status) async {
    final repo = _ref.read(tasksRepositoryProvider);
    final outbox = _ref.read(taskOutboxProvider);
    try {
      await repo.updateStatus(taskId, status);
      await outbox?.discardFor(taskId);
      await _ref.read(tasksProvider.notifier).applyStatus(taskId, status);
      return StatusOutcome.sent;
    } on AppException catch (e) {
      // Only trouble reaching the server is queued; a refusal is shown at once.
      if (!e.isRetryable || outbox == null) rethrow;
      await outbox.queue(taskId, status);
      await _ref.read(tasksProvider.notifier).applyStatus(taskId, status);
      return StatusOutcome.queued;
    }
  }
}

final taskActionsProvider = Provider<TaskActions>((ref) => TaskActions(ref));

// ---- single task ----------------------------------------------------------

class TaskDetailState {
  const TaskDetailState(
    this.task, {
    this.attachments = const [],
    this.fromCache = false,
  });

  final TaskItem task;
  final List<TaskAttachment> attachments;
  final bool fromCache;

  TaskDetailState copyWith({
    TaskItem? task,
    List<TaskAttachment>? attachments,
  }) => TaskDetailState(
    task ?? this.task,
    attachments: attachments ?? this.attachments,
    fromCache: fromCache,
  );
}

class TaskDetailController extends AsyncNotifier<TaskDetailState> {
  TaskDetailController(this.id);
  final String id;

  final Set<String> _togglesInFlight = {};

  @override
  Future<TaskDetailState> build() async {
    ref.watch(currentUserIdProvider);
    final repo = ref.read(tasksRepositoryProvider);
    final store = ref.read(tasksStoreProvider);
    try {
      // Started together for speed. Not combined with Future.wait: that wraps
      // errors, and the offline fallback below needs the original AppException.
      final attachmentsFuture = _attachmentsOrEmpty(repo);
      final task = await repo.detail(id);
      final attachments = await attachmentsFuture;
      await store?.saveDetail(task);
      return TaskDetailState(task, attachments: attachments);
    } on AppException catch (e) {
      if (!e.isRetryable) rethrow;
      final cached = await store?.readDetail(id);
      if (cached == null) rethrow;
      return TaskDetailState(cached, fromCache: true);
    }
  }

  /// A missing attachment list must not hide the task itself.
  Future<List<TaskAttachment>> _attachmentsOrEmpty(TasksRepository repo) async {
    try {
      return await repo.attachments(id);
    } on AppException {
      return const [];
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Flips a checklist item. Shown immediately; undone if the server refuses.
  /// A flip is not idempotent, so after an uncertain failure the server state is
  /// re-read instead of the request being repeated.
  Future<void> toggleItem(String checklistId, String itemId) async {
    final current = state.value;
    if (current == null || !_togglesInFlight.add(itemId)) return;
    final before = current.task;
    final item = before.checklists
        .where((c) => c.id == checklistId)
        .expand((c) => c.items)
        .where((i) => i.id == itemId)
        .firstOrNull;
    if (item == null) {
      // The list changed under the tap (reloaded); there is nothing to flip.
      _togglesInFlight.remove(itemId);
      return;
    }
    _set(
      current.copyWith(
        task: _withItem(before, checklistId, itemId, !item.isDone),
      ),
    );
    try {
      await ref
          .read(tasksRepositoryProvider)
          .toggleChecklistItem(
            taskId: id,
            checklistId: checklistId,
            itemId: itemId,
          );
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        try {
          final fresh = await ref.read(tasksRepositoryProvider).detail(id);
          _set(state.value!.copyWith(task: fresh));
        } on AppException {
          _set(state.value!.copyWith(task: before));
        }
      } else {
        _set(state.value!.copyWith(task: before));
      }
      rethrow;
    } finally {
      _togglesInFlight.remove(itemId);
    }
  }

  TaskItem _withItem(
    TaskItem t,
    String checklistId,
    String itemId,
    bool done,
  ) => t.copyWith(
    checklists: [
      for (final c in t.checklists)
        if (c.id == checklistId) c.withItem(itemId, done) else c,
    ],
  );

  final Set<String> _assigning = {};

  /// Adds or removes one person on this task. Shown at once and undone if the
  /// server refuses. Assigning only sets membership, so after an uncertain
  /// failure it is sent once more; if that fails too the change is undone.
  Future<void> setAssigned(
    TaskAssignee person, {
    required bool assigned,
  }) async {
    final current = state.value;
    if (current == null || !_assigning.add(person.id)) return;
    final before = current.task.assignees;
    try {
      if (before.any((a) => a.id == person.id) == assigned) return;
      _set(
        current.copyWith(
          task: current.task.copyWith(
            assignees: assigned
                ? [...before, person]
                : before.where((a) => a.id != person.id).toList(),
          ),
        ),
      );
      final repo = ref.read(tasksRepositoryProvider);
      Future<void> send() => assigned
          ? repo.addAssignee(id, person.id)
          : repo.removeAssignee(id, person.id);
      try {
        try {
          await send();
        } on AppException catch (e) {
          if (!e.outcomeUnknown) rethrow;
          await send();
        }
      } on AppException {
        final now = state.value;
        if (now != null) {
          _set(now.copyWith(task: now.task.copyWith(assignees: before)));
        }
        rethrow;
      }
    } finally {
      _assigning.remove(person.id);
    }
  }

  Future<void> addComment(String content) async {
    final comment = await ref
        .read(tasksRepositoryProvider)
        .addComment(id, content.trim());
    final current = state.value;
    if (current == null) return;
    _set(
      current.copyWith(
        task: current.task.copyWith(
          comments: [...current.task.comments, comment],
          commentCount: current.task.commentCount + 1,
        ),
      ),
    );
  }

  Future<void> uploadPhoto({
    required String path,
    required String fileName,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    final attachment = await ref
        .read(tasksRepositoryProvider)
        .uploadAttachment(
          taskId: id,
          path: path,
          fileName: fileName,
          contentType: contentType,
          onProgress: onProgress,
        );
    final current = state.value;
    if (current == null) return;
    _set(
      current.copyWith(
        task: current.task.copyWith(
          attachmentCount: current.task.attachmentCount + 1,
        ),
        attachments: [...current.attachments, attachment],
      ),
    );
  }

  /// Mirrors a status change made through [TaskActions] onto this screen.
  void applyStatus(String status) {
    final current = state.value;
    if (current == null) return;
    _set(current.copyWith(task: current.task.copyWith(status: status)));
  }

  void _set(TaskDetailState s) {
    if (ref.mounted) state = AsyncData(s);
  }
}

final taskDetailProvider =
    AsyncNotifierProvider.family<TaskDetailController, TaskDetailState, String>(
      TaskDetailController.new,
    );
