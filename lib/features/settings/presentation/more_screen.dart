import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/destinations.dart';
import '../../../app/router/route_guard.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../notifications/application/push_providers.dart';
import '../../sync/application/sync_providers.dart';
import 'company_logo.dart';

/// Account, company, overflow destinations and sign-out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final session = ref.watch(sessionProvider);
    final perms = ref.watch(permissionsProvider);
    final me = session.me;
    if (me == null) return const SizedBox.shrink();

    final plan = planNavigation(perms);

    // Modules the user may use in the web app, with the in-app destination that
    // covers them (null = not in the mobile app yet). Listed honestly instead of
    // as dead buttons; a module whose screen the user HAS in the app is not
    // listed (people who can view projects but do not supervise, for example,
    // get no Projects tab and are pointed to the web app for it).
    const modules = <(String, List<String>, String?)>[
      ('Projects', Feature.projects, 'projects'),
      ('Quotes', Feature.quotes, 'quotes'),
      ('Invoices', Feature.invoices, 'invoices'),
      ('Financials', Feature.financials, 'finance'),
      ('Employees and payroll', Feature.employees, null),
      ('Clients (CRM)', Feature.crm, 'clients'),
      ('Documents', Feature.documents, null),
      ('Reports', Feature.reports, 'reports'),
      ('Project templates and company setup', Feature.settings, null),
    ];
    final inApp = {
      for (final d in [...plan.bottom, ...plan.overflow]) d.id,
    };
    final onWeb = [
      for (final (name, keys, destination) in modules)
        if (perms.hasAny(keys) &&
            !(destination != null && inApp.contains(destination)))
          name,
    ];

    return PageBody(
      children: [
        const PageTitle('More'),
        AppCard(
          onTap: () => context.push('/more/profile'),
          semanticLabel: 'Your profile, tap to edit',
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: c.primarySoft,
                child: Text(
                  me.user.initials,
                  style: AppType.bodyStrong.copyWith(color: c.primaryText),
                ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me.user.fullName,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      me.user.email,
                      style: AppType.bodySmall.copyWith(color: c.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (me.user.roleLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          me.user.roleLabel,
                          style: AppType.badge.copyWith(color: c.primaryText),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        AppCard(
          onTap: () => context.push('/more/company'),
          semanticLabel:
              'Company ${me.tenant.name}, tap to open the company profile',
          child: Row(
            children: [
              if (me.tenant.logoUrl == null)
                const IconTile(Icons.apartment_rounded)
              else
                CompanyLogo(
                  name: me.tenant.name,
                  url: me.tenant.logoUrl,
                  size: Sizes.iconContainer,
                ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Company',
                      style: AppType.helper.copyWith(color: c.textMuted),
                    ),
                    Text(
                      me.tenant.name,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                  ],
                ),
              ),
              Text(
                me.tenant.defaultCurrency,
                style: AppType.label.copyWith(color: c.textMuted),
              ),
              const SizedBox(width: Space.xs),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
        if (plan.overflow.isNotEmpty) ...[
          const SectionHeader('Also in the app'),
          for (final d in plan.overflow)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: AppCard(
                onTap: () => context.go(d.path),
                child: Row(
                  children: [
                    IconTile(d.icon),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Text(
                        d.label,
                        style: AppType.bodyStrong.copyWith(color: c.text),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.textMuted),
                  ],
                ),
              ),
            ),
        ],
        const SectionHeader('Notifications'),
        AppCard(
          onTap: () => context.push(Routes.notifications),
          child: Row(
            children: [
              const IconTile(Icons.notifications_none_rounded),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Text(
                  'Notifications',
                  style: AppType.bodyStrong.copyWith(color: c.text),
                ),
              ),
              if (ref.watch(unreadAlertsProvider) > 0)
                Padding(
                  padding: const EdgeInsets.only(right: Space.sm),
                  child: Text(
                    '${ref.watch(unreadAlertsProvider)} new',
                    style: AppType.label.copyWith(color: c.primary),
                  ),
                ),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ],
          ),
        ),
        if (onWeb.isNotEmpty) ...[
          const SectionHeader('On the web app for now'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your role also covers these. They are not in the mobile app yet — use ownit2buildit on the web.',
                  style: AppType.bodySmall.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: Space.md),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final name in onWeb)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                          vertical: Space.xs + 1,
                        ),
                        decoration: BoxDecoration(
                          color: c.surfaceMuted,
                          borderRadius: BorderRadius.circular(Corners.sm),
                        ),
                        child: Text(
                          name,
                          style: AppType.label.copyWith(color: c.text),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ] else if (plan.bottom.isEmpty) ...[
          const SectionHeader('Your access'),
          AppCard(
            child: Text(
              'Your account has no permissions that the mobile app uses yet. Ask your administrator to review your role.',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          ),
        ],
        const SizedBox(height: Space.x3),
        AppButton(
          label: 'Sign out',
          icon: Icons.logout_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: () async {
            // Time and material records saved without a connection are the
            // person's own and must not vanish unnoticed.
            final waiting =
                (ref.read(queuedWritesProvider).value ?? const []).length;
            final ok = await confirmAction(
              context,
              title: 'Sign out?',
              message: waiting == 0
                  ? 'Saved offline information on this phone will be removed.'
                  : '$waiting ${waiting == 1 ? 'entry is' : 'entries are'} saved on this phone and ${waiting == 1 ? 'has' : 'have'} not reached the server yet. '
                        'Signing out now discards ${waiting == 1 ? 'it' : 'them'}. '
                        'Stay signed in and connect to send ${waiting == 1 ? 'it' : 'them'} first.',
              confirmLabel: waiting == 0 ? 'Sign out' : 'Sign out and discard',
              destructive: true,
            );
            if (!ok) return;
            final uid = ref.read(currentUserIdProvider);
            if (waiting > 0 && uid != null) {
              await ref.read(appDatabaseProvider).removeQueuedWritesFor(uid);
            }
            await ref.read(sessionProvider.notifier).logout();
          },
        ),
      ],
    );
  }
}
