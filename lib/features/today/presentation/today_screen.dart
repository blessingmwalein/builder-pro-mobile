import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/destinations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/states.dart';
import '../../approvals/application/approvals_providers.dart';
import '../../requests/application/requests_providers.dart';
import '../../tasks/data/task_list_repository.dart';
import '../../tasks/data/task_models.dart';
import '../../tasks/presentation/task_row.dart';
import '../../time/application/time_providers.dart';
import '../../finance/application/finance_providers.dart';
import '../application/today_providers.dart';
import 'company_section.dart';
import '../../notifications/presentation/notification_bell.dart';

/// The supervisor's morning view: what needs attention across projects.
///
/// Every section is shown only if the user's permissions allow the data behind
/// it, and each loads (and fails) on its own.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final me = ref.watch(sessionProvider).me;
    final canSeeTasks = perms.hasAny(Feature.tasks);
    final canApprove = perms.satisfies(Feature.approvals);
    final showCompany =
        perms.hasAny(Feature.financials) || perms.hasAny(Feature.invoices);

    Future<void> refresh() async {
      ref.invalidate(companyDashboardProvider);
      ref.invalidate(agingReportProvider);
      ref.invalidate(openTasksProvider);
      ref.invalidate(approvalsProvider);
      ref.invalidate(clockProvider);
    }

    return PageBody(
      onRefresh: refresh,
      children: [
        PageTitle(
          me == null ? 'Today' : 'Hello, ${me.user.firstName}',
          subtitle: Fmt.day(DateTime.now()),
          trailing: const NotificationBell(),
        ),
        if (perms.hasAny(Feature.requests)) const _RequestsSection(),
        if (showCompany) const CompanySection(),
        if (canApprove) const _TimeSection(),
        if (canSeeTasks) const _TasksSection(),
        if (perms.hasAny(Feature.timesheetsOwn)) const _MyClock(),
        if (!canApprove &&
            !canSeeTasks &&
            !showCompany &&
            !perms.hasAny(Feature.timesheetsOwn))
          const Padding(
            padding: EdgeInsets.only(top: Space.x3),
            child: EmptyState(
              icon: Icons.dashboard_outlined,
              title: 'Nothing to show yet',
              message:
                  'Your role does not include any of the overview sections.',
            ),
          ),
      ],
    );
  }
}

// ---- time --------------------------------------------------------------------

class _TimeSection extends ConsumerWidget {
  const _TimeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final approvals = ref.watch(approvalsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('TIME'),
        approvals.when(
          loading: () => const SkeletonBox(height: 96, radius: Corners.card),
          error: (e, _) => ErrorPanel(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(approvalsProvider),
          ),
          data: (s) {
            final ready = s.ready.length;
            final working = s.working;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _TapTile(
                          onTap: () => context.go(approvalsDestination.path),
                          child: MetricTile(
                            label: 'TO APPROVE',
                            value: '$ready${s.hasMore ? '+' : ''}',
                            caption: ready == 0
                                ? 'All caught up'
                                : 'Tap to review',
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: MetricTile(
                          label: 'WORKING NOW',
                          value: '${working.length}',
                          caption: working.isEmpty ? 'Nobody clocked in' : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (working.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  AppCard(
                    child: Column(
                      children: [
                        for (final e in working.take(5))
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Space.xs,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.workerName,
                                    style: AppType.bodyStrong.copyWith(
                                      color: c.text,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    e.projectName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppType.bodySmall.copyWith(
                                      color: c.textMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (working.length > 5)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              '+ ${working.length - 5} more',
                              style: AppType.helper.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TapTile extends StatelessWidget {
  const _TapTile({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Corners.card),
        child: child,
      ),
    );
  }
}

// ---- tasks -------------------------------------------------------------------

class _TasksSection extends ConsumerWidget {
  const _TasksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final open = ref.watch(openTasksProvider);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('TASKS'),
        open.when(
          loading: () => const SkeletonList(rows: 2, rowHeight: 96),
          error: (e, _) => ErrorPanel(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(openTasksProvider),
          ),
          data: (data) {
            final blocked = data.blocked;
            final overdue = data.overdue(now);
            final today = data.dueToday(now);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'OVERDUE',
                          value: '${overdue.length}',
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: MetricTile(
                          label: 'DUE TODAY',
                          value: '${today.length}',
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: MetricTile(
                          label: 'BLOCKED',
                          value: '${blocked.length}',
                        ),
                      ),
                    ],
                  ),
                ),
                if (data.truncated)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.sm),
                    child: Text(
                      'Showing the first ${TaskListRepository.pageSize} tasks per status. Counts may be higher.',
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                  ),
                _TaskGroup(title: 'BLOCKED', tasks: blocked),
                _TaskGroup(title: 'OVERDUE', tasks: overdue),
                _TaskGroup(title: 'DUE TODAY', tasks: today),
                if (blocked.isEmpty && overdue.isEmpty && today.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: AppCard(
                      child: Row(
                        children: [
                          Icon(Icons.task_alt_rounded, color: c.success),
                          const SizedBox(width: Space.md),
                          Expanded(
                            child: Text(
                              'Nothing is overdue, due today or blocked.',
                              style: AppType.body.copyWith(color: c.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({required this.title, required this.tasks});
  final String title;
  final List<TaskItem> tasks;

  static const _limit = 5;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('$title ${tasks.length}'),
        for (final t in tasks.take(_limit))
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: TaskRow(
              task: t,
              onTap: () => context.push('/tasks/${t.id}'),
            ),
          ),
        if (tasks.length > _limit)
          Text(
            '+ ${tasks.length - _limit} more. Open a project to see them all.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
      ],
    );
  }
}

// ---- my clock ----------------------------------------------------------------

class _MyClock extends ConsumerWidget {
  const _MyClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final clock = ref.watch(clockProvider);
    final active = clock.value?.active;
    final label = clock.isLoading
        ? 'Checking…'
        : (active == null
              ? 'You are not clocked in'
              : 'Clocked in on ${active.project.name} since ${Fmt.time(active.clockInAt)}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('YOUR CLOCK'),
        AppCard(
          onTap: () => context.go(clockDestination.path),
          child: Row(
            children: [
              IconTile(
                Icons.timer_outlined,
                tone: active == null ? null : StatusTone.success,
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Text(
                  label,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- requests ----------------------------------------------------------------

/// A prompt when requests (purchase orders, change requests…) wait for the
/// user's decision. Silent when there are none or the count cannot be read.
class _RequestsSection extends ConsumerWidget {
  const _RequestsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final count = ref.watch(pendingRequestCountProvider).value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('REQUESTS'),
        AppCard(
          onTap: () => context.go(requestsDestination.path),
          semanticLabel:
              '$count ${count == 1 ? 'request is' : 'requests are'} waiting for your decision',
          child: Row(
            children: [
              const IconTile(Icons.approval_outlined, tone: StatusTone.warning),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 request is waiting for your decision'
                      : '$count requests are waiting for your decision',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
      ],
    );
  }
}
