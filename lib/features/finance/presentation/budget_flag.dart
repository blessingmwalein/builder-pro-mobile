import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../data/finance_models.dart';

/// The alert level used when a budget line has none of its own (the server's
/// default).
const defaultAlertPercent = 80;

/// A flag for a budget that is over, or at the level where it should be looked at.
/// Colour is never the only signal: it has an icon and words.
class BudgetFlagChip extends StatelessWidget {
  const BudgetFlagChip({super.key, required this.over, required this.label});

  /// A flag for a line, or null when it is on track.
  static Widget? forLine(BudgetLine l) {
    if (l.isOver) return BudgetFlagChip(over: true, label: 'Over budget');
    if (l.isWarning) {
      return BudgetFlagChip(
        over: false,
        label:
            '${l.percentUsed}% · alert at ${l.thresholdPct ?? defaultAlertPercent}%',
      );
    }
    return null;
  }

  /// A flag for a status word the server uses for a project, or null when on
  /// track or nothing is budgeted.
  static Widget? forStatus(
    String status, {
    String? overLabel,
    String? warningLabel,
  }) {
    if (status == BudgetStatus.overBudget) {
      return BudgetFlagChip(over: true, label: overLabel ?? 'Over budget');
    }
    if (status == BudgetStatus.warning) {
      return BudgetFlagChip(
        over: false,
        label: warningLabel ?? 'Near its limit',
      );
    }
    return null;
  }

  final bool over;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = c.tone(over ? StatusTone.danger : StatusTone.warning);
    return Semantics(
      label: over ? 'Over budget: $label' : 'Budget alert: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(Corners.sm),
          border: Border.all(color: tone.foreground.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              over ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
              size: 14,
              color: tone.foreground,
            ),
            const SizedBox(width: Space.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.badge.copyWith(color: tone.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The colour of a budget's figures: danger when over, warning at the alert
/// level, otherwise the muted text colour.
Color budgetTone(AppColors c, {required bool over, required bool warning}) =>
    over ? c.danger : (warning ? c.warning : c.textMuted);
