import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../messaging/application/messaging_providers.dart';
import '../../messaging/data/messaging_models.dart';
import '../application/push_providers.dart';
import '../data/notification_categories.dart';

/// Which kinds of update the person gets: for each, whether it is kept in their
/// notification list and whether it is sent to their phone. The server keeps the
/// switches (so the web app shares them); a server that cannot yet says so and
/// everything stays on.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPreferencesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: SafeArea(
        child: prefs.when(
          // Keep what is shown (and the switches) while it is read again.
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 5, rowHeight: 96),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
          data: (p) => PageBody(
            onRefresh: () async {
              ref.invalidate(notificationPreferencesProvider);
              try {
                await ref.read(notificationPreferencesProvider.future);
              } catch (_) {
                // The screen shows its own error.
              }
            },
            children: [
              const _Intro(),
              const SizedBox(height: Space.lg),
              if (!p.supported)
                const _Unsupported()
              else
                for (final c in p.categories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: _CategoryCard(preference: c),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends ConsumerWidget {
  const _Intro();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = ref.watch(pushControllerProvider).status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose which updates you get. "In the app" keeps them in your notification list. "On this phone" also sends them as alerts.',
          style: AppType.bodySmall.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.sm),
        Text(
          status == PushStatus.on
              ? 'Your phone\'s own notification setting for ownit2buildit also decides whether alerts are shown.'
              : 'Alerts on this phone are not turned on, so nothing is sent here yet. Turn them on in Notifications. Your phone\'s own notification setting also decides whether alerts are shown.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

class _Unsupported extends StatelessWidget {
  const _Unsupported();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_sync_outlined, color: c.textMuted),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Notification settings need an update on the server. Everything is on for now.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.preference});
  final NotificationPreference preference;

  Future<void> _set(
    BuildContext context,
    WidgetRef ref, {
    bool? inApp,
    bool? push,
  }) async {
    try {
      await ref
          .read(notificationPreferencesProvider.notifier)
          .setSwitch(preference.category, inApp: inApp, push: push);
    } on AppException catch (e) {
      if (context.mounted) Snack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final known = NotificationCategories.byKey(preference.category);
    final label = known?.label ?? preference.label;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                NotificationCategories.iconFor(preference.category),
                color: c.primary,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    if (known != null)
                      Text(
                        known.description,
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('In the app'),
            value: preference.inApp,
            onChanged: (v) => _set(context, ref, inApp: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('On this phone'),
            value: preference.push,
            onChanged: (v) => _set(context, ref, push: v),
          ),
        ],
      ),
    );
  }
}
