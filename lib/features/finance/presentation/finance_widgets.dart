import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../data/finance_models.dart';

// Re-exported so the finance screens keep one import for their shared widgets.
export '../../../shared/components/list_widgets.dart';

/// Label / amount line for totals blocks.
class AmountRow extends StatelessWidget {
  const AmountRow(
    this.label,
    this.amount, {
    super.key,
    this.currency = 'USD',
    this.strong = false,
    this.tone,
  });

  final String label;
  final double amount;
  final String currency;
  final bool strong;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = (strong ? AppType.bodyStrong : AppType.body).copyWith(
      color: tone ?? (strong ? c.text : c.textMuted),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: AdaptiveRow(
        start: Text(label, style: style),
        end: Text(
          Fmt.money(amount, currency),
          style: AppType.amount.copyWith(color: tone ?? c.text),
        ),
      ),
    );
  }
}

/// The lines of an invoice or quote.
class LineItemsCard extends StatelessWidget {
  const LineItemsCard({super.key, required this.lines, required this.currency});
  final List<LineItem> lines;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (lines.isEmpty) {
      return AppCard(
        child: Text(
          'No line items.',
          style: AppType.body.copyWith(color: c.textMuted),
        ),
      );
    }
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) Divider(height: Space.xl, color: c.border),
            AdaptiveRow(
              start: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lines[i].description,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  Text(
                    '${Fmt.quantity(lines[i].quantity)}${lines[i].unit == null ? '' : ' ${lines[i].unit}'} × ${Fmt.money(lines[i].unitPrice, currency)}',
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              end: Text(
                Fmt.money(lines[i].total, currency),
                style: AppType.amount.copyWith(color: c.text),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
