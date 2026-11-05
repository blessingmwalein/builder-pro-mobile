import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../messaging/presentation/start_chat.dart';
import '../application/team_providers.dart';
import '../data/team_models.dart';

/// The company's people with their phone numbers and emails, so a manager can
/// call or write to someone straight from the app. Inviting people and managing
/// their records stays on the web app.
class TeamScreen extends ConsumerStatefulWidget {
  const TeamScreen({super.key});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// The search text as a filter: none when it is blank.
  String? _filterFor(String text) {
    final t = text.trim();
    return t.isEmpty ? null : t;
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(teamCatalogProvider.notifier).setFilter(_filterFor(text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(teamCatalogProvider);
    final notifier = ref.read(teamCatalogProvider.notifier);
    final searching = state.filter != null;
    return PageBody(
      onRefresh: notifier.refresh,
      children: [
        const PageTitle('Team'),
        AppTextField(
          label: 'Search people',
          controller: _search,
          hint: 'Name or email',
          prefixIcon: Icons.search_rounded,
          textInputAction: TextInputAction.search,
          onChanged: _onSearch,
          onSubmitted: (t) => notifier.setFilter(_filterFor(t)),
        ),
        const SizedBox(height: Space.md),
        ...pagedRows<TeamMember>(
          context,
          state: state,
          onRefresh: notifier.refresh,
          onLoadMore: notifier.loadMore,
          emptyIcon: Icons.groups_outlined,
          emptyTitle: searching ? 'No one matches' : 'No people yet',
          emptyMessage: searching
              ? 'Try a different name or email.'
              : 'People are invited on the web app.',
          rowBuilder: (m) => _MemberCard(member: m),
        ),
      ],
    );
  }
}

class _MemberCard extends ConsumerStatefulWidget {
  const _MemberCard({required this.member});
  final TeamMember member;

  @override
  ConsumerState<_MemberCard> createState() => _MemberCardState();
}

class _MemberCardState extends ConsumerState<_MemberCard> {
  bool _opening = false;

  Future<void> _open(Future<bool> Function() action, String failure) async {
    final ok = await action();
    if (!ok && mounted) Snack.show(context, failure);
  }

  Future<void> _message() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openChatWith(context, ref, widget.member.id);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.member;
    final launcher = ref.watch(contactLauncherProvider);
    final canChat = canMessage(ref, m.id);
    final hasContact = m.phone != null || m.email != null;
    return AppCard(
      semanticLabel: m.roles.isEmpty ? m.name : '${m.name}, ${m.roleLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodyStrong.copyWith(color: c.text),
          ),
          if (m.roles.isNotEmpty)
            Text(
              m.roleLabel,
              style: AppType.bodySmall.copyWith(color: c.textMuted),
            ),
          if (hasContact) ...[
            const SizedBox(height: Space.sm),
            if (m.phone != null)
              Text(m.phone!, style: AppType.body.copyWith(color: c.text)),
            if (m.email != null)
              Text(
                m.email!,
                style: AppType.bodySmall.copyWith(color: c.textMuted),
              ),
          ],
          if (hasContact || canChat) ...[
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                if (canChat)
                  AppButton(
                    label: 'Message',
                    icon: Icons.chat_bubble_outline_rounded,
                    compact: true,
                    expand: false,
                    loading: _opening,
                    onPressed: _message,
                  ),
                if (m.phone != null)
                  AppButton(
                    label: 'Call',
                    icon: Icons.phone_outlined,
                    compact: true,
                    expand: false,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => _open(
                      () => launcher.call(m.phone!),
                      'Could not open the phone app. The number is ${m.phone}.',
                    ),
                  ),
                if (m.email != null)
                  AppButton(
                    label: 'Email',
                    icon: Icons.mail_outline_rounded,
                    compact: true,
                    expand: false,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => _open(
                      () => launcher.email(m.email!),
                      'Could not open the mail app. The address is ${m.email}.',
                    ),
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                'No phone number or email recorded.',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}
