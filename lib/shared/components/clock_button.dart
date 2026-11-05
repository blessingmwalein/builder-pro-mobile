import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';

/// The big round clock-in / clock-out control, sized for a gloved thumb.
/// While [loading] it keeps its size and ignores taps, so a slow request can
/// never be sent twice.
class ClockButton extends StatelessWidget {
  const ClockButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Clock-out uses the danger colour so it cannot be mistaken for clock-in.
  final bool destructive;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null && !loading;
    final bg = destructive ? c.danger : c.primary;
    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? '$label, in progress' : label,
      excludeSemantics: true,
      child: SizedBox(
        width: Sizes.clockButton,
        height: Sizes.clockButton,
        child: Material(
          color: enabled || loading ? bg : c.surfaceMuted,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        color: c.textOnPrimary,
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 44,
                          color: enabled ? c.textOnPrimary : c.textMuted,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          label,
                          style: AppType.button.copyWith(
                            color: enabled ? c.textOnPrimary : c.textMuted,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
