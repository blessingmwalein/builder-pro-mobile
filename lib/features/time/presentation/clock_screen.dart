import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/clock_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/components/tick_builder.dart';
import '../../../core/network/server_features.dart';
import '../../sync/data/queued_write_models.dart';
import '../../sync/presentation/queued_writes_panel.dart';
import '../../tasks/application/tasks_providers.dart';
import '../../tasks/data/task_models.dart';
import '../application/clock_location.dart';
import '../application/time_providers.dart';
import '../data/time_models.dart';
import 'clock_out_sheet.dart';
import '../../notifications/presentation/notification_bell.dart';

/// The worker's clock: start/stop work on a project and see today and this week.
class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});

  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  ProjectRef? _project;
  TaskItem? _task;
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(weekSummaryProvider);
    ref.invalidate(recentEntriesProvider);
    ref.invalidate(tasksProvider);
    await ref.read(clockProvider.notifier).reload();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() => _busy = true);
    try {
      final note = await action();
      HapticFeedback.mediumImpact();
      if (note != null && mounted) Snack.show(context, note);
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockIn(ProjectRef project) => _run(
    () => ref
        .read(clockProvider.notifier)
        .clockIn(project, taskId: _task?.id, taskTitle: _task?.title),
  );

  Future<void> _clockOut(TimeEntry entry) async {
    final minutes = await showClockOutSheet(context, entry);
    if (minutes == null || !mounted) return;
    await _run(
      () => ref.read(clockProvider.notifier).clockOut(breakMinutes: minutes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clock = ref.watch(clockProvider);
    return clock.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.gutter),
        child: SkeletonList(rows: 3, rowHeight: 120),
      ),
      error: (e, _) => ErrorPanel(
        error: e,
        onRetry: () => ref.read(clockProvider.notifier).reload(),
      ),
      data: (state) => Column(
        children: [
          if (state.lastKnown)
            StatusBanner(
              message: ref.watch(offlineWritesSupportedProvider)
                  ? 'No connection. Showing your last known clock status. Clocking in or out is saved on this phone and sent when you are back online.'
                  : 'No connection. Showing your last known clock status. Clocking in or out needs a connection.',
            ),
          Expanded(child: _content(state)),
        ],
      ),
    );
  }

  Widget _content(ClockState state) {
    final active = state.active;
    // Without a connection the clock still works once the server has said it
    // can take the time an event really happened: it is saved and sent later.
    final canSaveOffline = ref.watch(offlineWritesSupportedProvider);
    final canAct = !state.lastKnown || canSaveOffline;
    return PageBody(
      onRefresh: _refresh,
      children: [
        PageTitle(
          'Clock',
          subtitle: Fmt.day(DateTime.now()),
          trailing: const NotificationBell(),
        ),
        if (active == null)
          _ClockInCard(
            busy: _busy,
            project: _project,
            task: _task,
            lastKnown: !canAct,
            onProject: (p) => setState(() {
              _project = p;
              _task = null;
            }),
            onTask: (t) => setState(() => _task = t),
            onClockIn: _clockIn,
          )
        else
          _ClockedInCard(
            entry: active,
            busy: _busy,
            canAct: canAct,
            savedOnPhone: state.savedOnPhone,
            onClockOut: () => _clockOut(active),
          ),
        const QueuedWritesPanel(kinds: WriteKind.timeKinds),
        const SizedBox(height: Space.lg),
        _Totals(active: active),
        const SectionHeader('Recent time'),
        const _RecentEntries(),
        const SizedBox(height: Space.xl),
        const _LocationSwitch(),
      ],
    );
  }
}

/// "Record my location when I clock in or out": off until the person turns it
/// on, and never needed to clock in. Turning it on asks the phone for
/// permission.
class _LocationSwitch extends ConsumerWidget {
  const _LocationSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final on = ref.watch(clockLocationProvider).value ?? false;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.my_location_rounded, color: c.textMuted),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Record my location',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                Text(
                  'Saves where you are when you clock in or out. If it cannot be found, you still clock in.',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: (value) async {
              final problem = await ref
                  .read(clockLocationProvider.notifier)
                  .setEnabled(value);
              if (problem != null && context.mounted) {
                Snack.show(context, problem);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ---- not clocked in ----------------------------------------------------------

class _ClockInCard extends ConsumerWidget {
  const _ClockInCard({
    required this.busy,
    required this.project,
    required this.task,
    required this.lastKnown,
    required this.onProject,
    required this.onTask,
    required this.onClockIn,
  });

  final bool busy;
  final ProjectRef? project;
  final TaskItem? task;
  final bool lastKnown;
  final ValueChanged<ProjectRef> onProject;
  final ValueChanged<TaskItem?> onTask;
  final Future<void> Function(ProjectRef) onClockIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final work = ref.watch(workProjectsProvider);
    final recent = ref.watch(recentEntriesProvider).value ?? const [];
    final tasksLoading = ref.watch(tasksProvider).isLoading;

    // Projects the worker is assigned to, plus ones they have clocked on before.
    final seen = <String>{};
    final projects = [
      ...work,
      ...recent.map((e) => e.project),
    ].where((p) => p.id.isNotEmpty && seen.add(p.id)).toList();

    final effective =
        project ??
        (recent.isNotEmpty && seen.contains(recent.first.projectId)
            ? recent.first.project
            : (projects.isEmpty ? null : projects.first));

    final tasks = (ref.watch(tasksProvider).value?.tasks ?? const <TaskItem>[])
        .where((t) => t.project.id == effective?.id && !t.isDone)
        .toList();

    if (projects.isEmpty) {
      return AppCard(
        child: tasksLoading
            ? const SkeletonBox(height: 120)
            : Column(
                children: [
                  Icon(
                    Icons.assignment_late_outlined,
                    color: c.textMuted,
                    size: 36,
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    'No project to clock in on',
                    style: AppType.sectionTitle.copyWith(color: c.text),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'You can clock in on projects where you have a task. Ask your supervisor to assign you one, then pull down to refresh.',
                    textAlign: TextAlign.center,
                    style: AppType.body.copyWith(color: c.textMuted),
                  ),
                ],
              ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusBadge(label: 'Not clocked in', tone: StatusTone.muted),
          ),
          const SizedBox(height: Space.lg),
          PickerField(
            label: 'Project',
            icon: Icons.apartment_rounded,
            value: effective?.label,
            onTap: () async {
              final picked = await pickOne<ProjectRef>(
                context,
                title: 'Choose a project',
                selected: effective,
                options: [
                  for (final p in projects)
                    PickerOption(value: p, title: p.name, subtitle: p.code),
                ],
              );
              if (picked?.value != null) onProject(picked!.value!);
            },
          ),
          if (tasks.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            PickerField(
              label: 'Task (optional)',
              icon: Icons.checklist_rounded,
              value: task?.title,
              placeholder: 'No specific task',
              onTap: () async {
                final picked = await pickOne<TaskItem>(
                  context,
                  title: 'Choose a task',
                  selected: task,
                  clearLabel: 'No specific task',
                  options: [
                    for (final t in tasks)
                      PickerOption(value: t, title: t.title),
                  ],
                );
                if (picked != null) onTask(picked.value);
              },
            ),
          ],
          const SizedBox(height: Space.xxl),
          ClockButton(
            label: 'Clock in',
            icon: Icons.play_arrow_rounded,
            loading: busy,
            onPressed: effective == null || lastKnown
                ? null
                : () => onClockIn(effective),
          ),
          if (lastKnown) ...[
            const SizedBox(height: Space.md),
            Text(
              'Reconnect to clock in.',
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- clocked in --------------------------------------------------------------

class _ClockedInCard extends StatelessWidget {
  const _ClockedInCard({
    required this.entry,
    required this.busy,
    required this.canAct,
    required this.savedOnPhone,
    required this.onClockOut,
  });

  final TimeEntry entry;
  final bool busy;
  final bool canAct;

  /// This shift is saved on the phone and the server does not have it yet.
  final bool savedOnPhone;
  final VoidCallback onClockOut;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(Space.xl),
      child: Column(
        children: [
          // Wrap, not Row: at very large text the time drops to its own line.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.md,
            runSpacing: Space.xs,
            children: [
              StatusBadge(label: 'Clocked in', tone: StatusTone.success),
              Text(
                'Since ${Fmt.time(entry.clockInAt)}',
                style: AppType.label.copyWith(color: c.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          TickBuilder(
            builder: (context, now) => Semantics(
              label: 'Time worked ${Fmt.duration(entry.workedAt(now))}',
              excludeSemantics: true,
              // Scales down instead of overflowing at large accessibility text sizes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Fmt.timer(entry.workedAt(now)),
                  style: AppType.timer.copyWith(color: c.text),
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            entry.project.label,
            textAlign: TextAlign.center,
            style: AppType.bodyStrong.copyWith(color: c.text),
          ),
          if (entry.taskTitle != null)
            Text(
              entry.taskTitle!,
              textAlign: TextAlign.center,
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          if (savedOnPhone) ...[
            const SizedBox(height: Space.sm),
            Text(
              'Saved on this phone. Your clock-in time is kept and sent when there is a connection.',
              textAlign: TextAlign.center,
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
          const SizedBox(height: Space.xxl),
          ClockButton(
            label: 'Clock out',
            icon: Icons.stop_rounded,
            destructive: true,
            loading: busy,
            onPressed: canAct ? onClockOut : null,
          ),
          if (!canAct) ...[
            const SizedBox(height: Space.md),
            Text(
              'Reconnect to clock out.',
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- totals ------------------------------------------------------------------

class _Totals extends ConsumerWidget {
  const _Totals({required this.active});
  final TimeEntry? active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(weekSummaryProvider);
    return TickBuilder(
      interval: const Duration(seconds: 20),
      builder: (context, now) {
        final summary = week.value;
        if (summary == null) {
          return week.hasError
              ? ErrorPanel(
                  error: week.error!,
                  compact: true,
                  onRetry: () => ref.invalidate(weekSummaryProvider),
                )
              : const Row(
                  children: [
                    Expanded(
                      child: SkeletonBox(height: 96, radius: Corners.card),
                    ),
                    SizedBox(width: Space.md),
                    Expanded(
                      child: SkeletonBox(height: 96, radius: Corners.card),
                    ),
                  ],
                );
        }
        final openNow = active?.workedAt(now) ?? Duration.zero;
        final today = DateTime(now.year, now.month, now.day);
        var todayWorked = Duration.zero;
        for (final e in summary.entries) {
          final day = e.clockInAt.toLocal();
          if (DateTime(day.year, day.month, day.day) != today) continue;
          if (!e.isOpen) {
            todayWorked += Duration(minutes: (e.totalHours * 60).round());
          }
        }
        if (active != null) {
          final start = active!.clockInAt.toLocal();
          if (DateTime(start.year, start.month, start.day) == today) {
            todayWorked += openNow;
          }
        }
        final weekWorked =
            Duration(minutes: (summary.totalHours * 60).round()) + openNow;
        // IntrinsicHeight: equal-height tiles inside a scrolling list.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: MetricTile(
                  label: 'TODAY',
                  value: Fmt.duration(todayWorked),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: MetricTile(
                  label: 'THIS WEEK',
                  value: Fmt.duration(weekWorked),
                  caption: summary.totalOvertimeHours > 0
                      ? '${Fmt.hours(summary.totalOvertimeHours)} overtime'
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- recent entries ----------------------------------------------------------

class _RecentEntries extends ConsumerWidget {
  const _RecentEntries();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final recent = ref.watch(recentEntriesProvider);
    return recent.when(
      loading: () => const SkeletonList(rows: 3, rowHeight: 64),
      error: (e, _) => ErrorPanel(
        error: e,
        compact: true,
        onRetry: () => ref.invalidate(recentEntriesProvider),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return AppCard(
            child: Text(
              'No time recorded yet. Your clocked hours will appear here.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          );
        }
        return Column(
          children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _EntryRow(entry: e),
              ),
          ],
        );
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final TimeEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final span = entry.isOpen
        ? '${Fmt.time(entry.clockInAt)} – now'
        : '${Fmt.time(entry.clockInAt)} – ${Fmt.time(entry.clockOutAt!)}';
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      semanticLabel:
          '${Fmt.relativeDay(entry.clockInAt)}, ${entry.project.name}, $span',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.relativeDay(entry.clockInAt),
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                Text(
                  entry.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
                Text(span, style: AppType.helper.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.isOpen ? 'In progress' : Fmt.hours(entry.totalHours),
                style: AppType.amount.copyWith(color: c.text),
              ),
              const SizedBox(height: Space.xs),
              if (!entry.isOpen) StatusBadge.status(entry.status, dense: true),
            ],
          ),
        ],
      ),
    );
  }
}
