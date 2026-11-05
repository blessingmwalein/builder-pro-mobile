import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../notifications/application/push_providers.dart';
import '../../notifications/data/notification_categories.dart';
import '../application/messaging_providers.dart';

/// Whether an inbox line belongs in the list for [f]. The server narrows the list
/// too, but an older one ignores the filter, so it is applied here as well.
bool notificationAllowed(NotificationFilter f, InboxItem i) =>
    (!f.unreadOnly || !i.isRead) &&
    (f.category == null || i.category == f.category);

/// The person's notifications: the server's list together with the alerts this
/// phone received, filtered by kind, with "mark all as read", removal with undo,
/// the switch for getting alerts on this phone, and a way to the notification
/// settings.
///
/// Until the backend change that opens `/notifications/me` to every user is
/// deployed, workers get HTTP 403 from the server's list; that is shown as a
/// plain note, and alerts kept on this phone are still listed.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(serverUnreadCountProvider);
    ref.invalidate(notificationsProvider);
    try {
      await ref.read(notificationsProvider.future);
    } catch (_) {
      // The list shows its own error.
    }
  }

  Future<void> _markAll(
    BuildContext context,
    WidgetRef ref,
    NotificationFilter filter,
  ) async {
    try {
      await ref
          .read(notificationsProvider.notifier)
          .markAllRead(category: filter.category);
    } on AppException catch (e) {
      if (context.mounted) Snack.error(context, e);
    }
  }

  /// Takes a notification out of the list now and sends the delete when the
  /// "Undo" bar has gone, unless Undo was tapped.
  void _remove(BuildContext context, WidgetRef ref, InboxItem n) {
    final controller = ref.read(notificationsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final item = controller.removeLocally(n.id);
    if (item == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: const Text('Notification removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => controller.restore(item),
          ),
        ),
      ).closed.then((reason) async {
        if (reason == SnackBarClosedReason.action) return;
        final problem = await controller.commitDelete(item);
        if (problem != null) {
          messenger.showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(problem.fullMessage),
            ),
          );
        }
      });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    final filter = ref.watch(notificationFilterProvider);
    final paging = ref.watch(notificationsPagingProvider);
    final unread = ref.watch(unreadAlertsProvider);
    final scope = filter.category == null
        ? 'Mark all as read'
        : 'Mark all ${NotificationCategories.labelFor(filter.category).toLowerCase()} as read';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: scope,
            onPressed: unread > 0 ? () => _markAll(context, ref, filter) : null,
            icon: const Icon(Icons.done_all_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: PageBody(
          onRefresh: () => _refresh(ref),
          children: [
            const _AlertsCard(),
            const _SettingsRow(),
            _Filters(filter: filter),
            const SizedBox(height: Space.md),
            ...inbox.when(
              loading: () => const [SkeletonList(rows: 4, rowHeight: 72)],
              error: (e, _) => [
                ErrorPanel(
                  error: e,
                  compact: true,
                  onRetry: () => _refresh(ref),
                ),
              ],
              data: (state) => _list(context, ref, state, filter, paging),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _list(
    BuildContext context,
    WidgetRef ref,
    InboxState state,
    NotificationFilter filter,
    NotificationsPaging paging,
  ) {
    if (state.items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: Space.x3),
          child: state.serverUnavailable
              ? const EmptyState(
                  icon: Icons.notifications_off_outlined,
                  title: 'Nothing here yet',
                  message: 'The notification list is not turned on for your account yet. Alerts that reach this phone will appear here. Nothing is wrong with your phone.',
                )
              : const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications yet',
                  message: 'Updates about your tasks, projects and approvals will appear here.',
                ),
        ),
      ];
    }
    final items = [
      for (final i in state.items)
        if (notificationAllowed(filter, i)) i,
    ];
    final widgets = <Widget>[
      if (state.serverUnavailable)
        const _Note(
          'The full notification list is not turned on for your account yet. Showing the alerts that reached this phone.',
        ),
      if (state.serverError != null)
        const _Note(
          'Could not refresh the full list. Showing what this phone has.',
        ),
    ];
    if (items.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.x3),
          child: Column(
            children: [
              EmptyState(
                icon: Icons.filter_list_off_rounded,
                title: 'Nothing here',
                message: filter.unreadOnly
                    ? 'You have read everything in this list.'
                    : 'No notifications of this kind yet.',
              ),
              const SizedBox(height: Space.md),
              AppButton(
                label: 'Show all',
                variant: AppButtonVariant.secondary,
                expand: false,
                onPressed: () => ref
                    .read(notificationFilterProvider.notifier)
                    .select(const NotificationFilter()),
              ),
            ],
          ),
        ),
      );
    }

    DateTime? lastDay;
    for (final n in items) {
      final at = n.createdAt.toLocal();
      final day = DateTime(at.year, at.month, at.day);
      if (day != lastDay) {
        widgets.add(_DayHeader(day));
        lastDay = day;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: _Row(
            item: n,
            onTap: () async {
              await markInboxRead(ref, n);
              if (n.route != null && context.mounted) context.go(n.route!);
            },
            onMarkRead: () => markInboxRead(ref, n),
            onRemove: n.fromServer ? () => _remove(context, ref, n) : null,
          ),
        ),
      );
    }

    if (paging.error != null) {
      widgets.add(_Note('Could not load more. ${paging.error!.message}'));
    }
    if (paging.hasMore) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: AppButton(
            label: 'Load more',
            variant: AppButtonVariant.secondary,
            loading: paging.loadingMore,
            onPressed: () =>
                ref.read(notificationsProvider.notifier).loadMore(),
          ),
        ),
      );
    }
    return widgets;
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});
  final NotificationFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatusFilterRow(
      options: [
        (null, 'All'),
        ('unread', 'Unread'),
        for (final c in NotificationCategories.all) (c.key, c.label),
      ],
      selected: filter.unreadOnly ? 'unread' : filter.category,
      onSelected: (v) => ref
          .read(notificationFilterProvider.notifier)
          .select(
            v == null
                ? const NotificationFilter()
                : v == 'unread'
                ? const NotificationFilter(unreadOnly: true)
                : NotificationFilter(category: v),
          ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.md),
    child: Text(
      text,
      style: AppType.bodySmall.copyWith(color: context.colors.textMuted),
    ),
  );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.day);
  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md, bottom: Space.sm),
    child: Text(
      Fmt.relativeDay(day).toUpperCase(),
      style: AppType.overline.copyWith(color: context.colors.textMuted),
    ),
  );
}

/// The way into choosing which kinds of alert to get.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: AppCard(
        onTap: () => context.push('/more/notifications/settings'),
        semanticLabel: 'Notification settings. Choose which updates you get',
        child: Row(
          children: [
            Icon(Icons.tune_rounded, color: c.primary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Notification settings',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  Text(
                    'Choose which updates you get',
                    style: AppType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Getting alerts on this phone: off, on, or refused by the phone's settings.
class _AlertsCard extends ConsumerWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final status = ref.watch(pushControllerProvider).status;
    final controller = ref.read(pushControllerProvider.notifier);
    switch (status) {
      case PushStatus.unavailable:
        return const SizedBox.shrink();
      case PushStatus.off:
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Get alerts on this phone',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Be told when a task is assigned to you, a message arrives or something is waiting for your decision, even when the app is closed. You can turn it off at any time.',
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: Space.md),
                AppButton(
                  label: 'Turn on alerts',
                  icon: Icons.notifications_active_outlined,
                  onPressed: controller.enable,
                ),
              ],
            ),
          ),
        );
      case PushStatus.blocked:
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Alerts are blocked on this phone',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  "Turn on notifications for ownit2buildit in your phone's settings, then try again.",
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: Space.md),
                AppButton(
                  label: 'Try again',
                  variant: AppButtonVariant.secondary,
                  onPressed: controller.enable,
                ),
              ],
            ),
          ),
        );
      case PushStatus.on:
        return Padding(
          padding: const EdgeInsets.only(bottom: Space.lg),
          child: AppCard(
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_rounded,
                  color: c.success,
                  size: 22,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'Alerts are on for this phone',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                ),
                TextButton(
                  onPressed: controller.disable,
                  child: const Text('Turn off'),
                ),
              ],
            ),
          ),
        );
    }
  }
}

enum _RowAction { markRead, remove }

class _Row extends StatelessWidget {
  const _Row({
    required this.item,
    required this.onTap,
    required this.onMarkRead,
    required this.onRemove,
  });
  final InboxItem item;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  /// Null for an alert that is only on this phone (nothing on the server to
  /// remove).
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tappable = !item.isRead || item.route != null;
    final meta = [
      if (item.actorName != null) item.actorName!,
      Fmt.ago(item.createdAt),
    ].join(' · ');
    final hasMenu = !item.isRead || onRemove != null;
    return AppCard(
      onTap: tappable ? onTap : null,
      semanticLabel:
          '${item.isRead ? '' : 'Unread. '}${item.title}${item.body.isEmpty ? '' : '. ${item.body}'}${item.route == null ? '' : ', tap to open'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              NotificationCategories.iconFor(item.category),
              size: 20,
              color: c.primaryText,
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!item.isRead)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: Space.sm),
                        child: Icon(Icons.circle, size: 9, color: c.primary),
                      ),
                    Expanded(
                      child: Text(
                        item.title,
                        style:
                            (item.isRead
                                    ? AppType.body.copyWith(
                                        fontWeight: FontWeight.w500,
                                      )
                                    : AppType.bodyStrong)
                                .copyWith(color: c.text),
                      ),
                    ),
                  ],
                ),
                if (item.body.isNotEmpty)
                  Text(
                    item.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodySmall.copyWith(color: c.textMuted),
                  ),
                const SizedBox(height: Space.xs),
                Text(meta, style: AppType.helper.copyWith(color: c.textMuted)),
              ],
            ),
          ),
          if (hasMenu)
            PopupMenuButton<_RowAction>(
              tooltip: 'More actions',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_vert_rounded, color: c.textMuted),
              onSelected: (a) => switch (a) {
                _RowAction.markRead => onMarkRead(),
                _RowAction.remove => onRemove?.call(),
              },
              itemBuilder: (_) => [
                if (!item.isRead)
                  const PopupMenuItem(
                    value: _RowAction.markRead,
                    child: Text('Mark as read'),
                  ),
                if (onRemove != null)
                  const PopupMenuItem(
                    value: _RowAction.remove,
                    child: Text('Remove'),
                  ),
              ],
            )
          else if (item.route != null)
            Icon(Icons.chevron_right_rounded, color: c.textMuted),
        ],
      ),
    );
  }
}
