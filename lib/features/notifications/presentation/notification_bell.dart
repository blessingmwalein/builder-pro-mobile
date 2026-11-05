import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_guard.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/tokens.dart';
import '../application/push_providers.dart';

/// The bell at the top right of a home screen, with the number of notifications
/// not read yet. An outlined, softly rounded button (the outline is the faded
/// border colour, like the cards'); opens the Notifications screen.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final count = ref.watch(unreadAlertsProvider);
    final label = count > 99 ? '99+' : '$count';
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Corners.card),
      side: BorderSide(color: c.border, width: Sizes.cardBorderWidth + 0.25),
    );
    return Semantics(
      button: true,
      label: count == 0 ? 'Notifications' : 'Notifications, $count unread',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Notifications',
        child: Material(
          color: c.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: shape,
            onTap: () => context.push(Routes.notifications),
            child: SizedBox(
              width: Sizes.touchTarget,
              height: Sizes.touchTarget,
              child: Center(
                child: Badge(
                  isLabelVisible: count > 0,
                  label: Text(label),
                  backgroundColor: c.primary,
                  textColor: Colors.white,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: c.text,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
