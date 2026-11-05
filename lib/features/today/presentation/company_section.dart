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
import '../../finance/application/finance_providers.dart';

/// The company at a glance for owners and managers: active projects, what is
/// owed to the company (and how much of it is overdue), and the projects whose
/// budget has reached its alert level.
///
/// Each part is shown only to someone who may see the data behind it, and each
/// loads (and fails) on its own. Money figures that the API adds up from draft
/// and void invoices are deliberately not used (backend-gaps G41).
class CompanySection extends ConsumerWidget {
  const CompanySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final canDashboard = perms.hasAny(Feature.financials);
    final canOwed = perms.hasAny(Feature.invoices);
    if (!canDashboard && !canOwed) return const SizedBox.shrink();

    final tiles = <Widget>[
      if (canDashboard)
        _ProjectsTile(allowedToOpen: projectsDestination.allowedFor(perms)),
      if (canOwed)
        _OwedTile(allowedToOpen: financeDestination.allowedFor(perms)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('COMPANY'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: Space.md),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        ),
        if (canDashboard) ...[
          const SizedBox(height: Space.sm),
          _AlertsCard(allowedToOpen: projectsDestination.allowedFor(perms)),
        ],
      ],
    );
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
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

class _ProjectsTile extends ConsumerWidget {
  const _ProjectsTile({required this.allowedToOpen});
  final bool allowedToOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(companyDashboardProvider);
    return dash.when(
      loading: () => const SkeletonBox(height: 96, radius: Corners.card),
      error: (e, _) => _Tappable(
        onTap: () => ref.invalidate(companyDashboardProvider),
        child: const MetricTile(
          label: 'ACTIVE PROJECTS',
          value: '—',
          caption: 'Could not load. Tap to retry',
        ),
      ),
      data: (d) => _Tappable(
        onTap: allowedToOpen
            ? () => context.go(projectsDestination.path)
            : null,
        child: MetricTile(
          label: 'ACTIVE PROJECTS',
          value: '${d.activeProjects}',
          caption: allowedToOpen ? 'Tap to see them' : null,
        ),
      ),
    );
  }
}

class _OwedTile extends ConsumerWidget {
  const _OwedTile({required this.allowedToOpen});
  final bool allowedToOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aging = ref.watch(agingReportProvider);
    final currency = ref.watch(currencyProvider);
    return aging.when(
      loading: () => const SkeletonBox(height: 96, radius: Corners.card),
      error: (e, _) => _Tappable(
        onTap: () => ref.invalidate(agingReportProvider),
        child: const MetricTile(
          label: 'OWED TO YOU',
          value: '—',
          caption: 'Could not load. Tap to retry',
        ),
      ),
      data: (r) => _Tappable(
        onTap: allowedToOpen ? () => context.go(financeDestination.path) : null,
        child: MetricTile(
          label: 'OWED TO YOU',
          value: Fmt.money(r.total, currency),
          caption: r.overdue > 0
              ? '${Fmt.money(r.overdue, currency)} overdue'
              : 'Nothing overdue',
        ),
      ),
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  const _AlertsCard({required this.allowedToOpen});
  final bool allowedToOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dash = ref.watch(companyDashboardProvider);
    return dash.when(
      loading: () => const SizedBox.shrink(),
      // The tile above already says it could not load and offers a retry.
      error: (e, _) => const SizedBox.shrink(),
      data: (d) {
        if (d.alerts.isEmpty) {
          return AppCard(
            child: Text(
              'No project budget is at its alert level.',
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          );
        }
        final shown = d.alerts.take(3).toList();
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BUDGET ALERTS ${d.alerts.length}',
                style: AppType.overline.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: Space.sm),
              for (final a in shown)
                _Tappable(
                  onTap: allowedToOpen
                      ? () => context.push('/projects/${a.projectId}')
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: Space.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          a.projectName,
                          style: AppType.bodyStrong.copyWith(color: c.text),
                        ),
                        Text(
                          a.isOver
                              ? 'Over budget · ${a.percentUsed}%'
                              : '${a.percentUsed}% used',
                          style: AppType.bodySmall.copyWith(
                            color: a.isOver ? c.danger : c.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (d.alerts.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    '+ ${d.alerts.length - shown.length} more',
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
