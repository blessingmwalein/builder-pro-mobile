import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/destinations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../finance/application/finance_providers.dart';
import '../../messaging/presentation/start_chat.dart';
import '../application/clients_providers.dart';
import '../data/client_models.dart';

/// One client: how to reach them (call, email), their projects, and their
/// quotes and invoices when the user may see those.
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(clientDetailProvider(clientId));
    return Scaffold(
      appBar: AppBar(title: Text(detail.value?.summary.name ?? 'Client')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Space.gutter),
            child: SkeletonList(rows: 3, rowHeight: 110),
          ),
          error: (e, _) => ErrorPanel(
            error: e,
            onRetry: () => ref.invalidate(clientDetailProvider(clientId)),
          ),
          data: (d) => _Body(
            detail: d,
            onRefresh: () async {
              ref.invalidate(clientDetailProvider(clientId));
              try {
                await ref.read(clientDetailProvider(clientId).future);
              } catch (_) {
                // The error state is shown by the screen itself.
              }
            },
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail, required this.onRefresh});
  final ClientDetail detail;
  final Future<void> Function() onRefresh;

  Future<void> _open(
    BuildContext context,
    Future<bool> Function() action,
    String failure,
  ) async {
    final ok = await action();
    if (!ok && context.mounted) Snack.show(context, failure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final perms = ref.watch(permissionsProvider);
    final currency = ref.watch(currencyProvider);
    final launcher = ref.watch(contactLauncherProvider);
    final d = detail;
    final k = d.summary;
    final canSeeQuotes = perms.hasAny(Feature.quotes);
    final canSeeInvoices = perms.hasAny(Feature.invoices);
    final canOpenProjects = projectsDestination.allowedFor(perms);
    final canOpenInvoices = invoicesDestination.allowedFor(perms);

    return PageBody(
      onRefresh: onRefresh,
      children: [
        Text(k.name, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Text(
          [
            if (k.contactPerson != null) k.contactPerson!,
            clientTypeLabel(k.type),
          ].join(' · '),
          style: AppType.body.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        if (k.phone != null || k.email != null || d.address != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (k.phone != null)
                  _ContactRow(
                    icon: Icons.phone_outlined,
                    value: k.phone!,
                    actionLabel: 'Call',
                    onAction: () => _open(
                      context,
                      () => launcher.call(k.phone!),
                      'Could not open the phone app. The number is ${k.phone}.',
                    ),
                  ),
                if (k.email != null)
                  _ContactRow(
                    icon: Icons.mail_outline_rounded,
                    value: k.email!,
                    actionLabel: 'Email',
                    onAction: () => _open(
                      context,
                      () => launcher.email(k.email!),
                      'Could not open the mail app. The address is ${k.email}.',
                    ),
                  ),
                if (d.address != null)
                  _ContactRow(
                    icon: Icons.place_outlined,
                    value: d.address!,
                    actionLabel: 'Copy',
                    onAction: () async {
                      await Clipboard.setData(ClipboardData(text: d.address!));
                      if (context.mounted) {
                        Snack.show(context, 'Address copied.');
                      }
                    },
                  ),
              ],
            ),
          )
        else
          AppCard(
            child: Text(
              'No phone number, email or address is recorded for this client.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          ),
        if (perms.hasAny(Feature.clientPortal) &&
            perms.hasAny(Feature.messagingSend))
          _ChatSection(clientId: k.id),
        if (d.notes != null) ...[
          const SectionHeader('NOTES'),
          Text(d.notes!, style: AppType.body.copyWith(color: c.text)),
        ],
        SectionHeader('PROJECTS ${d.projects.length}'),
        if (d.projects.isEmpty)
          AppCard(
            child: Text(
              'No projects for this client yet.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          )
        else
          for (final p in d.projects)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                onTap: canOpenProjects
                    ? () => context.push('/projects/${p.id}')
                    : null,
                child: AdaptiveRow(
                  start: Text(
                    p.code == null ? p.name : '${p.code} · ${p.name}',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: StatusBadge.status(p.status, dense: true),
                ),
              ),
            ),
        if (canSeeQuotes && d.quotes.isNotEmpty) ...[
          SectionHeader('RECENT QUOTES ${d.quotes.length}'),
          for (final q in d.quotes)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                child: AdaptiveRow(
                  start: Text(
                    q.number,
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: Wrap(
                    spacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        Fmt.money(q.total, currency),
                        style: AppType.amount.copyWith(color: c.text),
                      ),
                      StatusBadge.status(q.status, dense: true),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (canSeeInvoices && d.invoices.isNotEmpty) ...[
          SectionHeader('RECENT INVOICES ${d.invoices.length}'),
          for (final i in d.invoices)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                onTap: canOpenInvoices
                    ? () => context.push('/invoices/${i.id}')
                    : null,
                child: AdaptiveRow(
                  start: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        i.number,
                        style: AppType.bodyStrong.copyWith(color: c.text),
                      ),
                      if (i.balance != null && i.balance! > 0)
                        Text(
                          '${Fmt.money(i.balance!, currency)} due',
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
                    ],
                  ),
                  end: Wrap(
                    spacing: Space.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        Fmt.money(i.total, currency),
                        style: AppType.amount.copyWith(color: c.text),
                      ),
                      StatusBadge.status(i.status, dense: true),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if ((!canSeeQuotes && k.quoteCount > 0) ||
            (!canSeeInvoices && k.invoiceCount > 0))
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Text(
              '${[if (!canSeeQuotes && k.quoteCount > 0) '${k.quoteCount} ${k.quoteCount == 1 ? 'quote' : 'quotes'}', if (!canSeeInvoices && k.invoiceCount > 0) '${k.invoiceCount} ${k.invoiceCount == 1 ? 'invoice' : 'invoices'}'].join(' and ')} on file. Your role does not include their amounts.',
              style: AppType.helper.copyWith(color: c.textMuted),
            ),
          ),
        const SizedBox(height: Space.xl),
        if (perms.hasAny(Feature.crmManage))
          AppButton(
            label: 'Edit client',
            icon: Icons.edit_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: () => context.push('/clients/${k.id}/edit'),
          )
        else
          Text(
            'Changing client details needs permission to manage clients.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.value,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String value;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: AdaptiveRow(
        start: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: Sizes.iconMd, color: c.textMuted),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(value, style: AppType.body.copyWith(color: c.text)),
            ),
          ],
        ),
        end: AppButton(
          label: actionLabel,
          compact: true,
          expand: false,
          variant: AppButtonVariant.secondary,
          onPressed: onAction,
        ),
      ),
    );
  }
}

/// Chat with the people who have a portal login for this client. A client with no
/// login has no account to message, so the section says so.
class _ChatSection extends ConsumerStatefulWidget {
  const _ChatSection({required this.clientId});
  final String clientId;

  @override
  ConsumerState<_ChatSection> createState() => _ChatSectionState();
}

class _ChatSectionState extends ConsumerState<_ChatSection> {
  String? _opening;

  Future<void> _message(ClientPortalUser u) async {
    if (_opening != null) return;
    setState(() => _opening = u.userId);
    try {
      await openChatWith(context, ref, u.userId);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final users = ref.watch(clientPortalUsersProvider(widget.clientId));
    return users.when(
      loading: () => const SizedBox.shrink(),
      // Not allowed or not reachable: the section is simply left out.
      error: (e, _) => const SizedBox.shrink(),
      data: (list) {
        final active = list.where((u) => u.isActive).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('CHAT'),
            if (active.isEmpty)
              AppCard(
                child: Text(
                  'This client has no portal login, so there is no account to chat with. Use the phone or email above.',
                  style: AppType.body.copyWith(color: c.textMuted),
                ),
              )
            else
              for (final u in active)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: AppCard(
                    child: AdaptiveRow(
                      start: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u.name,
                            style: AppType.bodyStrong.copyWith(color: c.text),
                          ),
                          if (u.email != null)
                            Text(
                              u.email!,
                              style: AppType.helper.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                        ],
                      ),
                      end: AppButton(
                        label: 'Message',
                        icon: Icons.chat_bubble_outline_rounded,
                        compact: true,
                        expand: false,
                        loading: _opening == u.userId,
                        onPressed: () => _message(u),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
