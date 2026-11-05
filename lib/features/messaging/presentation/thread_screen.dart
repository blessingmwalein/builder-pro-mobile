import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/messaging_providers.dart';
import '../data/messaging_models.dart';
import 'chat_widgets.dart';
import 'thread_composer.dart';

/// One conversation: newest message at the bottom, composer below. Photos, files
/// and voice messages, replies, and tagging people with @ in a group.
class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  ReplyPreview? _reply;

  void _send(String text, List<PendingFile> files, List<String> mentions) {
    ref
        .read(threadProvider(widget.conversationId).notifier)
        .send(text, files: files, replyTo: _reply, mentionIds: mentions);
    if (_reply != null) setState(() => _reply = null);
  }

  void _replyTo(ChatMessage m) {
    setState(() {
      _reply = ReplyPreview(
        messageId: m.isLocal ? '' : m.id,
        senderName: m.senderName,
        text: m.body,
        senderId: m.senderId,
        attachmentContentType:
            m.attachments.firstOrNull?.contentType ??
            m.pending.firstOrNull?.contentType,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final myId = ref.watch(currentUserIdProvider);
    final thread = ref.watch(threadProvider(widget.conversationId));
    final conv = ref
        .watch(conversationsProvider)
        .value
        ?.where((x) => x.id == widget.conversationId)
        .firstOrNull;
    final canSend = ref
        .watch(permissionsProvider)
        .hasAny(Feature.messagingSend);
    final caps =
        ref.watch(chatCapabilitiesProvider).value ?? ChatCapabilities.legacy;
    final people = ref.watch(chatPeopleProvider(widget.conversationId));
    final isGroup = conv?.isGroup ?? true;
    final title = conv?.titleFor(myId) ?? 'Conversation';
    final other = isGroup ? null : conv?.otherPerson(myId);
    final live = thread.value?.live ?? false;
    final subtitle = [
      if (isGroup)
        conv != null && conv.participants.isNotEmpty
            ? '${conv.participants.length} people'
            : (conv?.projectName ?? 'Group'),
      live ? 'Live' : 'Updates every few seconds',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ChatAvatar(
              name: title,
              url: other?.avatarUrl,
              size: 38,
              group: isGroup,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  if (thread.value != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: thread.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 5, rowHeight: 56),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () =>
                ref.invalidate(threadProvider(widget.conversationId)),
          ),
          data: (state) => Column(
            children: [
              Expanded(
                child: _MessageList(
                  state: state,
                  isGroup: isGroup,
                  conversationId: widget.conversationId,
                  names: [
                    for (final p in people) p.name,
                    ?ref.watch(sessionProvider).me?.user.fullName,
                  ],
                  canReply: canSend,
                  onReply: _replyTo,
                ),
              ),
              if (canSend)
                ThreadComposer(
                  isGroup: isGroup,
                  people: people,
                  caps: caps,
                  reply: _reply,
                  onClearReply: () => setState(() => _reply = null),
                  onSend: _send,
                )
              else
                Padding(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Text(
                    'You can read this conversation but not send messages.',
                    style: AppType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _Item {}

class _DayItem extends _Item {
  _DayItem(this.day);
  final DateTime day;
}

class _MessageItem extends _Item {
  _MessageItem(this.message, {required this.firstOfRun});
  final ChatMessage message;

  /// The first message of a run from the same person: the one that carries the
  /// name and picture in a group.
  final bool firstOfRun;
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.state,
    required this.isGroup,
    required this.conversationId,
    required this.names,
    required this.canReply,
    required this.onReply,
  });

  final ThreadState state;
  final bool isGroup;
  final String conversationId;
  final List<String> names;
  final bool canReply;
  final ValueChanged<ChatMessage> onReply;

  List<_Item> _items() {
    final items = <_Item>[];
    DateTime? lastDay;
    String? lastSender;
    for (final m in state.messages) {
      final local = m.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day != lastDay) {
        items.add(_DayItem(day));
        lastDay = day;
        lastSender = null;
      }
      items.add(_MessageItem(m, firstOfRun: m.senderId != lastSender));
      lastSender = m.senderId;
    }
    return items;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final myId = ref.watch(currentUserIdProvider);
    if (state.messages.isEmpty) {
      return const EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No messages yet',
        message: 'Say hello to start the conversation.',
      );
    }
    final items = _items();
    final extra = state.hasOlder ? 1 : 0;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
        child: ListView.builder(
          reverse: true,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.md,
          ),
          itemCount: items.length + extra,
          itemBuilder: (context, i) {
            // The list is reversed: index 0 is the newest message.
            if (i == items.length) {
              return Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Center(
                  child: state.loadingOlder
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : TextButton(
                          onPressed: () => ref
                              .read(threadProvider(conversationId).notifier)
                              .loadOlder(),
                          child: const Text('Load earlier messages'),
                        ),
                ),
              );
            }
            final item = items[items.length - 1 - i];
            return switch (item) {
              _DayItem(:final day) => Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.md,
                      vertical: Space.xs,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceMuted,
                      borderRadius: BorderRadius.circular(Corners.pill),
                    ),
                    child: Text(
                      Fmt.relativeDay(day),
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                  ),
                ),
              ),
              _MessageItem(:final message, :final firstOfRun) => _Bubble(
                message: message,
                mine: message.senderId == myId,
                isGroup: isGroup,
                firstOfRun: firstOfRun,
                conversationId: conversationId,
                names: names,
                canReply: canReply,
                onReply: onReply,
              ),
            };
          },
        ),
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.isGroup,
    required this.firstOfRun,
    required this.conversationId,
    required this.names,
    required this.canReply,
    required this.onReply,
  });

  final ChatMessage message;
  final bool mine;
  final bool isGroup;
  final bool firstOfRun;
  final String conversationId;
  final List<String> names;
  final bool canReply;
  final ValueChanged<ChatMessage> onReply;

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final failed = message.state == SendState.failed;
    final actions = <(IconData, String, VoidCallback)>[
      if (canReply && !message.isLocal)
        (Icons.reply_rounded, 'Reply', () => onReply(message)),
      if (message.body.isNotEmpty)
        (
          Icons.copy_rounded,
          'Copy text',
          () async {
            await Clipboard.setData(ClipboardData(text: message.body));
            if (context.mounted) Snack.show(context, 'Copied.');
          },
        ),
      if (failed)
        (
          Icons.refresh_rounded,
          'Try again',
          () => ref
              .read(threadProvider(conversationId).notifier)
              .retry(message.id),
        ),
      if (failed)
        (
          Icons.delete_outline_rounded,
          'Delete',
          () => ref
              .read(threadProvider(conversationId).notifier)
              .discard(message.id),
        ),
    ];
    if (actions.isEmpty) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++)
              ListTile(
                leading: Icon(actions[i].$1),
                title: Text(actions[i].$2),
                onTap: () => Navigator.of(ctx).pop(i),
              ),
            const SizedBox(height: Space.sm),
          ],
        ),
      ),
    );
    if (picked != null) actions[picked].$3();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final failed = message.state == SendState.failed;
    final sending = message.state == SendState.sending;
    final bg = mine ? c.primary : c.surface;
    final fg = mine ? c.textOnPrimary : c.text;
    final soft = mine ? c.textOnPrimary.withValues(alpha: 0.82) : c.textMuted;
    final tint = c.seriesAt(message.senderName.hashCode.abs());
    final hasText = message.body.isNotEmpty;
    final hasFiles = message.attachmentCount > 0;
    const avatar = 32.0;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.78;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Semantics(
        container: true,
        label:
            '${mine ? 'You' : message.senderName}, ${Fmt.time(message.createdAt)}: ${message.body.isEmpty ? (message.attachmentCount > 0 ? 'attachment' : '') : message.body}${sending ? ', sending' : ''}${failed ? ', not sent' : ''}',
        excludeSemantics: true,
        child: Opacity(
          opacity: sending ? 0.75 : 1,
          child: GestureDetector(
            onLongPress: () => _actions(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(Corners.lg),
                  topRight: const Radius.circular(Corners.lg),
                  bottomLeft: Radius.circular(mine ? Corners.lg : 4),
                  bottomRight: Radius.circular(mine ? 4 : Corners.lg),
                ),
                border: mine ? null : Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isGroup && !mine && firstOfRun)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.xxs),
                      child: Text(
                        message.senderName,
                        style: AppType.helper.copyWith(
                          color: tint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (message.replyTo != null)
                    ReplyQuote(
                      reply: message.replyTo!,
                      textColor: mine ? c.textOnPrimary : c.textMuted,
                      accent: mine ? c.textOnPrimary : c.primary,
                      background: mine
                          ? Colors.black.withValues(alpha: 0.16)
                          : null,
                    ),
                  if (hasFiles)
                    Padding(
                      padding: EdgeInsets.only(bottom: hasText ? Space.xs : 0),
                      child: MessageAttachments(
                        message: message,
                        foreground: fg,
                      ),
                    ),
                  if (hasText)
                    MentionText(
                      message.body,
                      names: names,
                      style: AppType.body.copyWith(color: fg),
                      mentionStyle: AppType.body.copyWith(
                        color: mine ? c.textOnPrimary : c.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: Space.xxs),
                  Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: Text(
                      sending ? 'Sending…' : Fmt.time(message.createdAt),
                      style: AppType.helper.copyWith(color: soft),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: Space.xs + 2,
        top: firstOfRun ? Space.xs : 0,
      ),
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: mine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isGroup && !mine)
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: firstOfRun
                      ? ChatAvatar(name: message.senderName, size: avatar)
                      : const SizedBox(width: avatar, height: avatar),
                ),
              Flexible(child: bubble),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      message.error ?? 'Not sent.',
                      style: AppType.helper.copyWith(color: c.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(threadProvider(conversationId).notifier)
                        .retry(message.id),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(threadProvider(conversationId).notifier)
                        .discard(message.id),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
