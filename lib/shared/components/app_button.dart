import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';

enum AppButtonVariant { primary, secondary, danger, ghost }

/// The one button used across the app. 52px tall by default (gloved thumbs),
/// 40px when [compact]. Pass `onPressed: null` to disable; [loading] also
/// blocks taps so a slow request can never be submitted twice.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expand;
  final bool compact;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, borderColor) = switch (variant) {
      AppButtonVariant.primary => (c.primary, c.textOnPrimary, c.primary),
      AppButtonVariant.secondary => (c.surface, c.text, c.borderStrong),
      AppButtonVariant.danger => (c.danger, c.textOnPrimary, c.danger),
      AppButtonVariant.ghost => (
        Colors.transparent,
        c.primaryText,
        Colors.transparent,
      ),
    };
    final height = compact ? Sizes.buttonHeightCompact : Sizes.buttonHeight;
    final disabledBg = variant == AppButtonVariant.ghost
        ? Colors.transparent
        : c.surfaceMuted;

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: _enabled ? fg : c.textMuted,
            ),
          )
        else if (icon != null)
          Icon(
            icon,
            size: Sizes.iconSm + 2,
            color: _enabled ? fg : c.textMuted,
          ),
        if (loading || icon != null) const SizedBox(width: Space.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.button.copyWith(
              color: _enabled || loading ? fg : c.textMuted,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: loading ? '$label, in progress' : label,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: height,
          minWidth: expand ? double.infinity : Sizes.touchTarget,
        ),
        child: Material(
          color: _enabled || loading ? bg : disabledBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corners.md),
            side: BorderSide(
              color: _enabled || loading ? borderColor : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _enabled ? onPressed : null,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? Space.lg : Space.xl,
                vertical: Space.sm,
              ),
              child: Center(widthFactor: expand ? null : 1, child: content),
            ),
          ),
        ),
      ),
    );
  }
}
