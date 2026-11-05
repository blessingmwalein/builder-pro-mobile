import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/states.dart';
import '../application/messaging_providers.dart';
import '../data/messaging_models.dart';
import 'chat_widgets.dart';

/// Which conversations the Messages list shows.
enum ChatFilter { all, direct, groups, unread }

/// The conversations that match the chosen filter and the search words (a name, a
/// project, a person in it, or a word of the last message), in their own order.
List<ConversationSummary> filterConversations(
  List<ConversationSummary> all, {
  required ChatFilter filter,
  required String query,
  String? myId,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final c in all)
      if (switch (filter) {
            ChatFilter.all => true,
            ChatFilter.direct => !c.isGroup,
            ChatFilter.groups => c.isGroup,
            ChatFilter.unread => c.unreadCount > 0,
          } &&
          (q.isEmpty ||
              c.titleFor(myId).toLowerCase().contains(q) ||
              (c.projectName ?? '').toLowerCase().contains(q) ||
              c.participants.any((p) => p.name.toLowerCase().contains(q)) ||
              c.previewFor(myId).toLowerCase().contains(q)))
        c,
  ];
}

/// `14:05` today, `Yesterday`, a weekday within the week, otherwise `3 Oct`.
String chatTime(DateTime t, {DateTime? now}) {
  final at = t.toLocal();
  final today = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final days = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(day).inDays;
  if (days <= 0) return DateFormat('HH:mm').format(at);
  if (days == 1) return 'Yesterday';
  if (days < 7) return DateFormat('EEE').format(at);
  return DateFormat('d MMM').format(at);
}

/// Direct chats and groups, most recent first, with search and filters. People
/// who may send messages can start a chat.
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  final _search = TextEditingController();
  ChatFilter _filter = ChatFilter.all;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _startChat() async {
    await context.push('/messages/new');
    if (!mounted) return;
    ref.invalidate(conversationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conversations = ref.watch(conversationsProvider);
    final myId = ref.watch(currentUserIdProvider);
    final canStart = ref
        .watch(permissionsProvider)
        .hasAny(Feature.messagingSend);
    final all = conversations.value ?? const <ConversationSummary>[];
    final unread = all.fold<int>(0, (s, x) => s + x.unreadCount);
    final shown = filterConversations(
      all,
      filter: _filter,
      query: _search.text,
      myId: myId,
    );

    return PageBody(
      onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
      children: [
        PageTitle(
          'Messages',
          trailing: canStart
              ? IconButton.filledTonal(
                  tooltip: 'Start a new chat',
                  onPressed: _startChat,
                  icon: const Icon(Icons.edit_square),
                )
              : null,
        ),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          style: AppType.body.copyWith(color: c.text),
          decoration: InputDecoration(
            hintText: 'Search chats and people',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear the search',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: Space.md),
        StatusFilterRow(
          options: [
            (ChatFilter.all.name, 'All'),
            (ChatFilter.direct.name, 'Direct'),
            (ChatFilter.groups.name, 'Groups'),
            (ChatFilter.unread.name, unread > 0 ? 'Unread $unread' : 'Unread'),
          ],
          selected: _filter.name,
          onSelected: (v) => setState(
            () => _filter = ChatFilter.values.firstWhere(
              (f) => f.name == v,
              orElse: () => ChatFilter.all,
            ),
          ),
        ),
        const SizedBox(height: Space.md),
        ...conversations.when(
          loading: () => const [SkeletonList(rows: 5, rowHeight: 72)],
          error: (e, _) => [
            ErrorPanel(
              error: e,
              onRetry: () => ref.read(conversationsProvider.notifier).refresh(),
            ),
          ],
          data: (_) {
            if (all.isEmpty) {
              return [
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'No conversations yet',
                    message: canStart
                        ? 'Start a chat with someone on your team, or a group for a project.'
                        : 'Messages from your team will show up here.',
                  ),
                ),
                if (canStart)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.md),
                    child: AppButton(
                      label: 'Start a chat',
                      icon: Icons.edit_square,
                      onPressed: _startChat,
                    ),
                  ),
              ];
            }
            if (shown.isEmpty) {
              return [
                Padding(
                  padding: const EdgeInsets.only(top: Space.x3),
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Nothing found',
                    message: _search.text.trim().isEmpty
                        ? 'There is nothing in this list.'
                        : 'No chat or person matches "${_search.text.trim()}".',
                  ),
                ),
              ];
            }
            return [
              Material(
                color: c.surface,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Corners.card),
                  side: BorderSide(
                    color: c.borderSoft,
                    width: Sizes.cardBorderWidth,
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, indent: 76, color: c.borderSoft),
                      _ConversationRow(
                        conversation: shown[i],
                        myId: myId,
                        onTap: () async {
                          await context.push('/messages/${shown[i].id}');
                          if (!context.mounted) return;
                          // The thread may have new messages that change the
                          // preview and the unread count.
                          ref.invalidate(conversationsProvider);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ];
          },
        ),
      ],
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.myId,
    required this.onTap,
  });
  final ConversationSummary conversation;
  final String? myId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final conv = conversation;
    final title = conv.titleFor(myId);
    final preview = conv.previewFor(myId);
    final unread = conv.unreadCount > 0;
    final subtitle = conv.subtitleFor(myId);
    final when = conv.lastAt ?? conv.updatedAt;
    final other = conv.isGroup ? null : conv.otherPerson(myId);
    return Semantics(
      button: true,
      label: '$title. ${unread ? '${conv.unreadCount} unread. ' : ''}$preview',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.md,
            ),
            child: Row(
              children: [
                ChatAvatar(
                  name: title,
                  url: other?.avatarUrl,
                  size: 48,
                  group: conv.isGroup,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (unread
                                          ? AppType.bodyStrong
                                          : AppType.body.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ))
                                      .copyWith(color: c.text),
                            ),
                          ),
                          const SizedBox(width: Space.sm),
                          Text(
                            chatTime(when),
                            style: AppType.helper.copyWith(
                              color: unread ? c.primaryText : c.textMuted,
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
                      const SizedBox(height: Space.xxs),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.bodySmall.copyWith(
                                color: unread ? c.text : c.textMuted,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: Space.sm),
                            Container(
                              constraints: const BoxConstraints(minWidth: 22),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.primary,
                                borderRadius: BorderRadius.circular(
                                  Corners.pill,
                                ),
                              ),
                              child: Text(
                                conv.unreadCount > 99
                                    ? '99+'
                                    : '${conv.unreadCount}',
                                textAlign: TextAlign.center,
                                style: AppType.badge.copyWith(
                                  color: c.textOnPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
