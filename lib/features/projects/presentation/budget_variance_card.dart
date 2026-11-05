import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/states.dart';
import '../../finance/application/finance_providers.dart';
import '../../finance/data/finance_models.dart';
import '../../finance/presentation/budget_flag.dart';
import 'projects_screen.dart' show ProgressLine;

/// The project's budget at a glance, on its Overview: spent against planned, the
/// variance (under or over), the alert flags, and the lines that are closest to or
/// past their limit. Tapping it opens the Budget tab. For people who may read
/// financials.
class BudgetVarianceCard extends ConsumerWidget {
  const BudgetVarianceCard({
    super.key,
    required this.projectId,
    required this.onOpen,
  });
  final String projectId;
  final VoidCallback onOpen;

  /// How many lines are listed under the totals.
  static const shownLines = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = ref.watch(projectBudgetProvider(projectId));
    final currency = ref.watch(currencyProvider);
    final canSet = ref
        .watch(permissionsProvider)
        .hasAny(Feature.financialsManage);
    return budget.when(
      loading: () => const SkeletonBox(height: 150, radius: Corners.card),
      error: (e, _) => ErrorPanel(
        error: e,
        compact: true,
        onRetry: () => ref.invalidate(projectBudgetProvider(projectId)),
      ),
      data: (b) {
        if (b.isEmpty) {
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BUDGET',
                  style: AppType.overline.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'No budget has been set for this project, so there is nothing to compare spending with.',
                  style: AppType.body.copyWith(color: context.colors.textMuted),
                ),
                if (canSet) ...[
                  const SizedBox(height: Space.md),
                  AppButton(
                    label: 'Set the budget',
                    variant: AppButtonVariant.secondary,
                    onPressed: () =>
                        context.push('/projects/$projectId/budget'),
                  ),
                ],
              ],
            ),
          );
        }
        return _Card(budget: b, currency: currency, onOpen: onOpen);
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.budget,
    required this.currency,
    required this.onOpen,
  });
  final ProjectBudget budget;
  final String currency;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = budget;
    // Over first, then the ones closest to their limit.
    final lines = [...b.lines]
      ..sort((x, y) => y.percentUsed.compareTo(x.percentUsed));
    final shown = lines.take(BudgetVarianceCard.shownLines).toList();
    final variance = b.remaining;
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
      onTap: onOpen,
      semanticLabel:
          'Budget: ${Fmt.money(b.totalActual, currency)} spent of ${Fmt.money(b.totalPlanned, currency)}, ${b.percentUsed}% used'
          '${b.needsAttention ? ', needs attention' : ''}. Tap for the budget',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              'BUDGET VARIANCE',
              style: AppType.overline.copyWith(color: c.textMuted),
            ),
            end: Icon(Icons.chevron_right_rounded, color: c.textMuted),
          ),
          const SizedBox(height: Space.sm),
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
            variance < 0
                ? 'Over budget by ${Fmt.money(-variance, currency)}'
                : '${Fmt.money(variance, currency)} under budget',
            style: AppType.bodySmall.copyWith(
              color: variance < 0 ? c.danger : c.textMuted,
              fontWeight: variance < 0 ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.sm, runSpacing: Space.xs, children: flags),
          ],
          if (shown.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Divider(height: 1, color: c.borderSoft),
            for (final l in shown) _LineRow(line: l, currency: currency),
            if (b.lines.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  '+ ${b.lines.length - shown.length} more ${b.lines.length - shown.length == 1 ? 'line' : 'lines'}',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.currency});
  final BudgetLine line;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = line;
    final flag = BudgetFlagChip.forLine(l);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdaptiveRow(
            start: Text(
              l.categoryName,
              style: AppType.label.copyWith(color: c.text),
            ),
            end:
                flag ??
                Text(
                  '${l.percentUsed}%',
                  style: AppType.label.copyWith(color: c.textMuted),
                ),
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (l.percentUsed.clamp(0, 100)) / 100,
              minHeight: 6,
              color: l.isOver
                  ? c.danger
                  : (l.isWarning ? c.warning : c.primary),
              backgroundColor: c.surfaceMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${Fmt.money(l.actual, currency)} of ${Fmt.money(l.planned, currency)}',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
        ],
      ),
    );
  }
}
