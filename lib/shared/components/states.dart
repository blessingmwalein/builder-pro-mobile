import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';
import '../../core/errors/app_exception.dart';
import 'app_button.dart';

/// Centred message with an optional action. Empty states say what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: Sizes.iconLg, color: c.textMuted),
            ),
            const SizedBox(height: Space.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppType.sectionTitle.copyWith(color: c.text),
            ),
            if (message != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: c.textMuted),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: Space.xl),
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error with a plain-language message and a retry when retrying is sensible.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ex = error is AppException ? error as AppException : null;
    final icon = switch (ex?.kind) {
      AppErrorKind.offline || AppErrorKind.timeout => Icons.cloud_off_rounded,
      AppErrorKind.forbidden => Icons.lock_outline_rounded,
      AppErrorKind.notFound => Icons.search_off_rounded,
      _ => Icons.error_outline_rounded,
    };
    final message = ex?.message ?? 'Something went wrong. Please try again.';
    final canRetry =
        onRetry != null &&
        (ex == null || ex.isRetryable || ex.kind == AppErrorKind.unknown);

    if (compact) {
      return Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: c.tone(StatusTone.danger).background,
          borderRadius: BorderRadius.circular(Corners.card),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: c.tone(StatusTone.danger).foreground,
              size: Sizes.iconMd,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                message,
                style: AppType.bodySmall.copyWith(
                  color: c.tone(StatusTone.danger).foreground,
                ),
              ),
            ),
            if (canRetry)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    return EmptyState(
      icon: icon,
      title: ex?.isNetwork == true ? 'No connection' : 'Something went wrong',
      message: message,
      actionLabel: canRetry ? 'Try again' : null,
      onAction: onRetry,
    );
  }
}

/// Shimmer-free skeleton block (static tint, respects reduced motion).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = Corners.sm,
  });
  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: context.colors.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Placeholder list rows while the first page loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5, this.rowHeight = 76});
  final int rows;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: SkeletonBox(height: rowHeight, radius: Corners.card),
              ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown while offline or when queued changes are waiting.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.icon = Icons.cloud_off_rounded,
    this.tone = StatusTone.warning,
    this.action,
  });

  final String message;
  final IconData icon;
  final StatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = context.colors.tone(tone);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.sm + 2,
        ),
        color: t.background,
        child: Row(
          children: [
            Icon(icon, size: Sizes.iconSm, color: t.foreground),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                message,
                style: AppType.bodySmall.copyWith(
                  color: t.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
