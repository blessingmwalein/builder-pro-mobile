import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../finance/application/finance_providers.dart';
import '../../finance/data/finance_models.dart';
import '../../finance/presentation/budget_flag.dart';
import '../../finance/presentation/budget_line_sheet.dart';
import 'projects_screen.dart' show ProgressLine;
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';

/// A project's budget by category and its latest spending, for people who may
/// read financials. Each category opens the items behind it; people who may
/// change finances can also record a cost against it.
class ProjectBudgetSection extends ConsumerWidget {
  const ProjectBudgetSection({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(projectBudgetProvider(projectId));
    final currency = ref.watch(currencyProvider);
    return budget.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: Space.xl),
        child: SkeletonList(rows: 1, rowHeight: 120),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.xl),
        child: ErrorPanel(
          error: e,
          compact: true,
          onRetry: () => ref.invalidate(projectBudgetProvider(projectId)),
        ),
      ),
      data: (b) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'BUDGET',
            trailing:
                ref.watch(permissionsProvider).hasAny(Feature.financialsManage)
                ? TextButton(
                    onPressed: () =>
                        context.push('/projects/$projectId/budget'),
                    child: Text(b.isEmpty ? 'Set budget' : 'Edit budget'),
                  )
                : null,
          ),
          _Actions(projectId: projectId),
          if (b.isEmpty)
            AppCard(
              child: Text(
                'No budget has been set for this project.',
                style: AppType.body.copyWith(color: context.colors.textMuted),
              ),
            )
          else ...[
            _Summary(budget: b, currency: currency),
            for (final line in b.lines)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: _LineCard(
                  line: line,
                  currency: currency,
                  projectId: projectId,
                ),
              ),
          ],
          _Spending(projectId: projectId, currency: currency),
        ],
      ),
    );
  }
}

/// What can be done with this budget from here.
class _Actions extends ConsumerWidget {
  const _Actions({required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRecord = ref
        .watch(permissionsProvider)
        .hasAny(Feature.financialsManage);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          if (canRecord)
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Record a cost'),
              onPressed: () => context.push('/projects/$projectId/costs/new'),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ActionChip(
            avatar: const Icon(Icons.insights_rounded, size: 18),
            label: const Text('Money detail'),
            onPressed: () =>
                context.push('/finance/detail/costs?project=$projectId'),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.budget, required this.currency});
  final ProjectBudget budget;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = budget;
    final flags = <Widget>[
      if (b.isOver)
        BudgetFlagChip(over: true, label: 'Over budget · ${b.percentUsed}%'),
      if (b.overLines > 0)
        BudgetFlagChip(
          over: true,
          label: '${b.overLines} ${b.overLines == 1 ? 'line' : 'lines'} over',
        ),
      if (b.warningLines > 0)
        BudgetFlagChip(
          over: false,
          label:
              '${b.warningLines} ${b.warningLines == 1 ? 'line' : 'lines'} near the limit',
        ),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              'Spent ${Fmt.money(b.totalActual, currency)}',
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: Text(
              'of ${Fmt.money(b.totalPlanned, currency)}',
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
          const SizedBox(height: Space.sm),
          ProgressLine(percent: b.percentUsed.clamp(0, 100)),
          const SizedBox(height: Space.sm),
          Text(
            b.isOver
                ? 'Over budget by ${Fmt.money(-b.remaining, currency)} (${b.percentUsed}% used)'
                : '${Fmt.money(b.remaining, currency)} left (${b.percentUsed}% used)',
            style: AppType.bodySmall.copyWith(
              color: b.isOver ? c.danger : c.textMuted,
            ),
          ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.xs, children: flags),
          ],
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.currency,
    required this.projectId,
  });
  final BudgetLine line;
  final String currency;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = line;
    final flag = BudgetFlagChip.forLine(l);
    return AppCard(
      onTap: () => showBudgetLineSheet(context, projectId: projectId, line: l),
      semanticLabel:
          '${l.categoryName}, ${statusInfo(l.status).label}, ${l.percentUsed}% used. Tap to see what is in it',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              l.categoryName,
              style: AppType.bodyStrong.copyWith(color: c.text),
            ),
            end: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                flag ?? StatusBadge.status(l.status, dense: true),
                const SizedBox(width: Space.xs),
                Icon(Icons.chevron_right_rounded, color: c.textMuted),
              ],
            ),
          ),
          const SizedBox(height: Space.sm),
          ProgressLine(percent: l.percentUsed.clamp(0, 100)),
          const SizedBox(height: Space.xs),
          Text(
            l.isOver
                ? '${Fmt.money(l.actual, currency)} of ${Fmt.money(l.planned, currency)} · over by ${Fmt.money(-l.remaining, currency)}'
                : '${Fmt.money(l.actual, currency)} of ${Fmt.money(l.planned, currency)} · ${Fmt.money(l.remaining, currency)} left',
            style: AppType.helper.copyWith(
              color: budgetTone(c, over: l.isOver, warning: l.isWarning),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spending extends ConsumerWidget {
  const _Spending({required this.projectId, required this.currency});
  final String projectId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final spending = ref.watch(projectSpendingProvider(projectId));
    return spending.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: Space.md),
        child: ErrorPanel(
          error: e,
          compact: true,
          onRetry: () => ref.invalidate(projectSpendingProvider(projectId)),
        ),
      ),
      data: (s) {
        if (s.items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader('RECENT SPENDING ${s.total}'),
            AppCard(
              child: Column(
                children: [
                  for (var i = 0; i < s.items.length; i++) ...[
                    if (i > 0) Divider(height: Space.xl, color: c.border),
                    AdaptiveRow(
                      start: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.items[i].description,
                            style: AppType.bodyStrong.copyWith(color: c.text),
                          ),
                          Text(
                            [
                              Fmt.day(s.items[i].occurredAt),
                              if (s.items[i].vendor != null) s.items[i].vendor!,
                              if (s.items[i].categoryName != null)
                                s.items[i].categoryName!,
                            ].join(' · '),
                            style: AppType.helper.copyWith(color: c.textMuted),
                          ),
                        ],
                      ),
                      end: Text(
                        Fmt.money(s.items[i].amount, currency),
                        style: AppType.amount.copyWith(color: c.text),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (s.total > s.items.length)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: AppButton(
                  label: 'See all ${s.total} costs',
                  icon: Icons.receipt_long_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push('/projects/$projectId/costs'),
                ),
              ),
          ],
        );
      },
    );
  }
}
