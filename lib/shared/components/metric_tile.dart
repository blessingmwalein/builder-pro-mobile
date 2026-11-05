import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';

/// A big number with a small label, for "Today" / "This week" style summaries.
/// With [onTap] it opens something and shows a small arrow; [selected] marks the
/// one that is open (for tiles that act as tabs).
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.onTap,
    this.selected = false,
  });

  final String label;
  final String value;
  final String? caption;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppType.overline.copyWith(
                    color: selected ? c.primaryText : c.textMuted,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, size: 16, color: c.textMuted),
            ],
          ),
          const SizedBox(height: Space.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppType.kpi.copyWith(color: c.text)),
          ),
          if (caption != null) ...[
            const SizedBox(height: Space.xs),
            Text(caption!, style: AppType.helper.copyWith(color: c.textMuted)),
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      button: onTap != null,
      selected: selected,
      label: '$label: $value${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.card),
          side: BorderSide(
            color: selected ? c.primary : c.borderSoft,
            width: selected ? 1.5 : Sizes.cardBorderWidth,
          ),
        ),
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
