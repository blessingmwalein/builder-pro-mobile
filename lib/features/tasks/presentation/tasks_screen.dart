import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/task_groups.dart';
import '../application/tasks_providers.dart';
import '../application/tasks_view_providers.dart';
import '../data/task_models.dart';
import 'task_gantt.dart';
import 'task_row.dart';
import 'tasks_view_toggle.dart';
import '../../notifications/presentation/notification_bell.dart';

/// The worker's assigned, unfinished tasks grouped by when they are due.
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String? _status;

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    return tasks.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.gutter),
        child: SkeletonList(rows: 5),
      ),
      error: (e, _) => ErrorPanel(
        error: e,
        onRetry: () => ref.read(tasksProvider.notifier).refresh(),
      ),
      data: _content,
    );
  }

  Widget _content(TasksSnapshot snapshot) {
    final c = context.colors;
    final pending = ref.watch(pendingStatusProvider);
    final failed = ref.watch(failedStatusOpsProvider);
    final now = DateTime.now();

    final tasks = [
      for (final t in snapshot.tasks) withPendingStatus(t, pending),
    ];
    final open = tasks.where((t) => !t.isDone).toList();
    final groups = groupTasks(tasks, now, status: _status);
    final view = ref.watch(tasksViewProvider);

    return Column(
      children: [
        if (snapshot.fromCache)
          StatusBanner(
            message: snapshot.fetchedAt == null
                ? 'Offline. Showing saved tasks.'
                : 'Offline. Showing tasks saved at ${Fmt.time(snapshot.fetchedAt!)}.',
          ),
        Expanded(
          child: PageBody(
            onRefresh: () => ref.read(tasksProvider.notifier).refresh(),
            children: [
              PageTitle(
                'My Tasks',
                subtitle: open.isEmpty ? null : '${open.length} open',
                trailing: const NotificationBell(),
              ),
              if (pending.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: AppCard(
                    color: c.tone(StatusTone.warning).background,
                    child: Row(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          color: c.tone(StatusTone.warning).foreground,
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: Text(
                            pending.length == 1
                                ? '1 change is waiting to be sent. It will go as soon as you are back online.'
                                : '${pending.length} changes are waiting to be sent. They will go as soon as you are back online.',
                            style: AppType.bodySmall.copyWith(
                              color: c.tone(StatusTone.warning).foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final op in failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: _FailedChange(
                    opId: op.id,
                    taskId: op.targetId,
                    message: op.lastError,
                    tasks: snapshot.tasks,
                  ),
                ),
              if (open.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: Space.sm),
                  child: TasksViewToggle(),
                ),
              if (open.isNotEmpty) _filters(open),
              if (open.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: Space.x4),
                  child: EmptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'No open tasks',
                    message: 'Tasks assigned to you will appear here. Pull down to refresh.',
                  ),
                )
              else if (groups.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: EmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    title: 'Nothing with that status',
                    actionLabel: 'Show all',
                    onAction: () => setState(() => _status = null),
                  ),
                )
              else if (view.mode == TasksViewMode.gantt)
                TaskGantt(
                  tasks: [for (final (_, items) in groups) ...items],
                  scale: view.scale,
                  onScaleChanged: (s) =>
                      ref.read(tasksViewProvider.notifier).setScale(s),
                  onOpenTask: (t) => context.push('/tasks/${t.id}'),
                )
              else
                for (final (group, items) in groups) ...[
                  SectionHeader(group.title.toUpperCase()),
                  for (final t in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: TaskRow(
                        task: t,
                        pendingSync: pending.containsKey(t.id),
                        onTap: () => context.push('/tasks/${t.id}'),
                      ),
                    ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filters(List<TaskItem> open) {
    const options = [
      (null, 'All'),
      (TaskStatus.todo, 'To do'),
      (TaskStatus.inProgress, 'In progress'),
      (TaskStatus.blocked, 'Blocked'),
      (TaskStatus.review, 'Review'),
    ];
    int count(String? s) =>
        s == null ? open.length : open.where((t) => t.status == s).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (value, label) in options)
              if (value == null || count(value) > 0 || _status == value)
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: ChoiceChip(
                    label: Text('$label ${count(value)}'),
                    selected: _status == value,
                    onSelected: (_) => setState(() => _status = value),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// A queued change the server refused: say so and let the worker retry or drop it.
class _FailedChange extends ConsumerWidget {
  const _FailedChange({
    required this.opId,
    required this.taskId,
    required this.message,
    required this.tasks,
  });

  final String opId;
  final String taskId;
  final String? message;
  final List<TaskItem> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final tone = c.tone(StatusTone.danger);
    final title = tasks
        .where((t) => t.id == taskId)
        .map((t) => t.title)
        .firstOrNull;
    return AppCard(
      color: tone.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, color: tone.foreground),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  'A change to "${title ?? 'a task'}" could not be saved. ${message ?? ''}',
                  style: AppType.bodySmall.copyWith(color: tone.foreground),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: Space.sm,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppButton(
                label: 'Discard',
                compact: true,
                expand: false,
                variant: AppButtonVariant.ghost,
                onPressed: () => ref.read(taskOutboxProvider)?.discard(opId),
              ),
              AppButton(
                label: 'Try again',
                compact: true,
                expand: false,
                variant: AppButtonVariant.secondary,
                onPressed: () async {
                  try {
                    await ref.read(taskOutboxProvider)?.retry(opId);
                    await ref.read(tasksProvider.notifier).refresh();
                  } catch (e) {
                    if (context.mounted) Snack.error(context, e);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
