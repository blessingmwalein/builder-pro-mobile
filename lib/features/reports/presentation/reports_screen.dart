import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/destinations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../projects/presentation/projects_screen.dart' show ProgressLine;
import '../application/reports_providers.dart';

/// Two read-only reports for owners and managers: which projects are behind, and
/// how far the tasks and hours have got. Neither carries money or pay.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _productivity = false;

  Future<void> _refresh() async {
    if (_productivity) {
      ref.invalidate(productivityReportProvider);
      try {
        await ref.read(productivityReportProvider.future);
      } catch (_) {
        // The error state is shown by the screen itself.
      }
    } else {
      ref.invalidate(delayReportProvider);
      try {
        await ref.read(delayReportProvider.future);
      } catch (_) {
        // The error state is shown by the screen itself.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      onRefresh: _refresh,
      children: [
        const PageTitle('Reports'),
        Wrap(
          spacing: Space.sm,
          children: [
            ChoiceChip(
              label: const Text('Delays'),
              selected: !_productivity,
              onSelected: (_) => setState(() => _productivity = false),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
            ChoiceChip(
              label: const Text('Productivity'),
              selected: _productivity,
              onSelected: (_) => setState(() => _productivity = true),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        if (_productivity)
          const _ProductivityReport()
        else
          const _DelayReport(),
      ],
    );
  }
}

class _DelayReport extends ConsumerWidget {
  const _DelayReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final report = ref.watch(delayReportProvider);
    final canOpen = projectsDestination.allowedFor(
      ref.watch(permissionsProvider),
    );
    return report.when(
      loading: () => const SkeletonList(rows: 3, rowHeight: 110),
      error: (e, _) => ErrorPanel(
        error: e,
        compact: true,
        onRetry: () => ref.invalidate(delayReportProvider),
      ),
      data: (r) {
        if (r.rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: Space.x3),
            child: EmptyState(
              icon: Icons.event_available_rounded,
              title: 'No active projects',
              message: 'Projects that are active or on hold are checked here.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'BEHIND',
                      value: '${r.delayed}',
                      caption: r.delayed == 0 ? 'Nothing is late' : null,
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: MetricTile(label: 'ON TRACK', value: '${r.onTrack}'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            for (final p in r.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: AppCard(
                  onTap: canOpen
                      ? () => context.push('/projects/${p.id}')
                      : null,
                  semanticLabel:
                      '${p.name}, ${p.isDelayed ? '${p.daysDelayed} days past its end date' : 'on track'}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdaptiveRow(
                        start: Text(
                          p.code == null ? p.name : '${p.code} · ${p.name}',
                          style: AppType.bodyStrong.copyWith(color: c.text),
                        ),
                        end: StatusBadge.status(p.status, dense: true),
                      ),
                      const SizedBox(height: Space.sm),
                      ProgressLine(percent: p.completionPercent),
                      const SizedBox(height: Space.sm),
                      Text(
                        p.isDelayed
                            ? '${p.daysDelayed} ${p.daysDelayed == 1 ? 'day' : 'days'} past its end date${p.endDate == null ? '' : ' (${Fmt.day(p.endDate!)})'}'
                            : p.endDate == null
                            ? 'On track'
                            : 'On track · ends ${Fmt.day(p.endDate!)}',
                        style: AppType.bodySmall.copyWith(
                          color: p.isDelayed ? c.danger : c.textMuted,
                        ),
                      ),
                      for (final s in p.overdueStages)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            '${s.name} · ${s.daysOverdue} ${s.daysOverdue == 1 ? 'day' : 'days'} overdue',
                            style: AppType.helper.copyWith(color: c.warning),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (r.generatedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'As of ${Fmt.dayTime(r.generatedAt!)}',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProductivityReport extends ConsumerWidget {
  const _ProductivityReport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final report = ref.watch(productivityReportProvider);
    final canOpen = projectsDestination.allowedFor(
      ref.watch(permissionsProvider),
    );
    return report.when(
      loading: () => const SkeletonList(rows: 3, rowHeight: 110),
      error: (e, _) => ErrorPanel(
        error: e,
        compact: true,
        onRetry: () => ref.invalidate(productivityReportProvider),
      ),
      data: (r) {
        if (r.rows.isEmpty) {
          return const Padding(
            padding: EdgeInsets.only(top: Space.x3),
            child: EmptyState(
              icon: Icons.insights_outlined,
              title: 'Nothing to report yet',
              message: 'Tasks and approved time will appear here.',
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MetricTile(
              label: 'TASKS DONE',
              value: '${r.doneTasks} of ${r.totalTasks}',
              caption: '${r.completionRate}% across all projects',
            ),
            const SizedBox(height: Space.md),
            for (final p in r.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: AppCard(
                  onTap: canOpen
                      ? () => context.push('/projects/${p.projectId}')
                      : null,
                  semanticLabel:
                      '${p.projectName}, ${p.done} of ${p.total} tasks done',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.projectName,
                        style: AppType.bodyStrong.copyWith(color: c.text),
                      ),
                      const SizedBox(height: Space.sm),
                      ProgressLine(percent: p.completionRate),
                      const SizedBox(height: Space.sm),
                      Text(
                        [
                          '${p.done} of ${p.total} done',
                          if (p.inProgress > 0) '${p.inProgress} in progress',
                          if (p.blocked > 0) '${p.blocked} blocked',
                        ].join(' · '),
                        style: AppType.bodySmall.copyWith(color: c.textMuted),
                      ),
                      if (p.estimatedHours > 0 || p.actualHours > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            p.estimatedHours > 0
                                ? '${Fmt.hours(p.actualHours)} worked of ${Fmt.hours(p.estimatedHours)} estimated'
                                : '${Fmt.hours(p.actualHours)} worked',
                            style: AppType.helper.copyWith(color: c.textMuted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
