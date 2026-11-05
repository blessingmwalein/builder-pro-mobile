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
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/metric_tile.dart';
import '../../../shared/components/states.dart';
import '../application/finance_providers.dart';
import 'budget_flag.dart';
import 'finance_widgets.dart';
import '../../notifications/presentation/notification_bell.dart';

/// Money owed to the company and the company's money in and out. Each section
/// is shown only if its data is permitted, and loads and fails on its own.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    final canInvoices = perms.hasAny(Feature.invoices);
    final canFinancials = perms.hasAny(Feature.financials);

    Future<void> refresh() async {
      ref.invalidate(agingReportProvider);
      ref.invalidate(financeSummaryProvider);
      ref.invalidate(companyDashboardProvider);
    }

    return PageBody(
      onRefresh: refresh,
      children: [
        PageTitle(
          'Finance',
          subtitle: 'Amounts in ${ref.watch(currencyProvider)}',
          trailing: const NotificationBell(),
        ),
        if (canInvoices) const _OwedSection(),
        if (canFinancials) const _SummarySection(),
        if (canFinancials) const _AlertsSection(),
        if (!canInvoices && !canFinancials)
          const Padding(
            padding: EdgeInsets.only(top: Space.x3),
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nothing to show yet',
              message: 'Your role does not include any finance figures.',
            ),
          ),
      ],
    );
  }
}

class _OwedSection extends ConsumerWidget {
  const _OwedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final aging = ref.watch(agingReportProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('OWED TO YOU'),
        aging.when(
          loading: () => const SkeletonBox(height: 160, radius: Corners.card),
          error: (e, _) => ErrorPanel(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(agingReportProvider),
          ),
          data: (a) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'UNPAID',
                        value: Fmt.money(a.total, currency),
                        caption: '${a.entries.length} invoices',
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: MetricTile(
                        label: 'OVERDUE',
                        value: Fmt.money(a.overdue, currency),
                        caption: a.overdue > 0 ? 'Needs chasing' : 'None late',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.sm),
              AppCard(
                child: Column(
                  children: [
                    _AgeRow('Not due yet', a.notDue, currency),
                    _AgeRow('1–30 days late', a.days1to30, currency),
                    _AgeRow('31–60 days late', a.days31to60, currency),
                    _AgeRow('61–90 days late', a.days61to90, currency),
                    _AgeRow(
                      'Over 90 days late',
                      a.over90,
                      currency,
                      last: true,
                    ),
                  ],
                ),
              ),
              if (a.entries.any((e) => e.isOverdue)) ...[
                const SectionHeader('MOST OVERDUE'),
                for (final e in a.entries.where((e) => e.isOverdue).take(5))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: AppCard(
                      onTap: () => context.push('/invoices/${e.invoiceId}'),
                      semanticLabel:
                          '${e.number}, ${e.clientName}, ${e.daysOverdue} days late, ${Fmt.money(e.balance, currency)}',
                      child: AdaptiveRow(
                        start: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.clientName,
                              style: AppType.bodyStrong.copyWith(color: c.text),
                            ),
                            Text(
                              '${e.number} · ${e.daysOverdue} days late',
                              style: AppType.helper.copyWith(color: c.danger),
                            ),
                          ],
                        ),
                        end: Text(
                          Fmt.money(e.balance, currency),
                          style: AppType.amount.copyWith(color: c.text),
                        ),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: Space.sm),
              AppButton(
                label: 'See all invoices',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.go(invoicesDestination.path),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AgeRow extends StatelessWidget {
  const _AgeRow(this.label, this.amount, this.currency, {this.last = false});
  final String label;
  final double amount;
  final String currency;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : Space.sm),
      child: AdaptiveRow(
        start: Text(label, style: AppType.body.copyWith(color: c.textMuted)),
        end: Text(
          Fmt.money(amount, currency),
          style: AppType.amount.copyWith(
            color: amount > 0 ? c.text : c.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Projects whose budget has reached its alert level or gone over, worst first.
/// Each opens the project.
class _AlertsSection extends ConsumerWidget {
  const _AlertsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final dash = ref.watch(companyDashboardProvider);
    return dash.when(
      loading: () => const SizedBox.shrink(),
      // Nothing to flag is better than a second error panel on this page.
      error: (e, _) => const SizedBox.shrink(),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            d.alerts.isEmpty
                ? 'BUDGET ALERTS'
                : 'BUDGET ALERTS ${d.alerts.length}',
          ),
          if (d.alerts.isEmpty)
            AppCard(
              child: Text(
                'No project budget is at its alert level.',
                style: AppType.bodySmall.copyWith(color: c.textMuted),
              ),
            ),
          for (final a in d.alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                onTap: () => context.push('/projects/${a.projectId}'),
                semanticLabel:
                    '${a.projectName}, ${a.isOver ? 'over budget' : 'budget alert'}, ${a.percentUsed}% used',
                child: AdaptiveRow(
                  start: Text(
                    a.projectName,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: BudgetFlagChip(
                    over: a.isOver,
                    label: a.isOver
                        ? 'Over budget · ${a.percentUsed}%'
                        : '${a.percentUsed}% used',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummarySection extends ConsumerWidget {
  const _SummarySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final summary = ref.watch(financeSummaryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('MONEY IN AND OUT'),
        summary.when(
          loading: () => const SkeletonBox(height: 190, radius: Corners.card),
          error: (e, _) => ErrorPanel(
            error: e,
            compact: true,
            onRetry: () => ref.invalidate(financeSummaryProvider),
          ),
          data: (s) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'COLLECTED',
                        value: Fmt.money(s.collected, currency),
                        caption: 'Paid by clients',
                        onTap: () => context.push('/finance/detail/collected'),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: MetricTile(
                        label: 'COSTS',
                        value: Fmt.money(s.actualCost, currency),
                        caption: 'Spent so far',
                        onTap: () => context.push('/finance/detail/costs'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.md),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'PROFIT',
                        value: Fmt.money(s.profit, currency),
                        caption: 'Collected minus costs',
                        onTap: () => context.push('/finance/detail/profit'),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: MetricTile(
                        label: 'BUDGET LEFT',
                        value: Fmt.money(s.budgetLeft, currency),
                        caption: 'of ${Fmt.money(s.budgetPlanned, currency)}',
                        onTap: () => context.push('/finance/detail/budget'),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  'Based on money received and costs recorded across all projects. Tap a figure to see what it is made of, by day, month or date range, and by project.',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
