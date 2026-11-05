import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../../../shared/services/contact_launcher.dart';
import '../../../shared/services/photo_picker.dart';
import '../application/company_providers.dart';
import '../data/company_models.dart';
import 'company_logo.dart';

/// The largest logo the server accepts.
const maxLogoBytes = 2 * 1024 * 1024;

/// The image type for a file name, or null when the server would not take it
/// (it accepts JPEG, PNG, WebP and GIF only).
String? logoContentType(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => null,
  };
}

enum _Tab {
  profile('Profile'),
  business('Business'),
  sectors('Sectors & types'),
  roles('Team roles'),
  workflows('Workflows'),
  settings('Settings');

  const _Tab(this.label);
  final String label;
}

/// The company's profile, as on the web app's Settings: its logo and contact
/// details, business details, sectors and project types, team roles, workflows
/// and business settings. Someone holding `settings.*` sees all of it and can edit
/// the profile, the business details and the settings, and change the logo.
/// Everyone else sees what their sign-in already carries: the name, currency and
/// time zone.
class CompanyProfileScreen extends ConsumerStatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  ConsumerState<CompanyProfileScreen> createState() =>
      _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends ConsumerState<CompanyProfileScreen> {
  _Tab _tab = _Tab.profile;
  bool _uploading = false;

  Future<void> _changeLogo() async {
    if (_uploading) return;
    final source = await pickOne<PhotoSource>(
      context,
      title: 'Change the logo',
      options: const [
        PickerOption(value: PhotoSource.camera, title: 'Take a photo'),
        PickerOption(
          value: PhotoSource.gallery,
          title: 'Choose from the gallery',
        ),
      ],
    );
    final chosen = source?.value;
    if (chosen == null || !mounted) return;

    final PickedPhoto? photo;
    try {
      photo = await ref.read(photoPickerProvider).pick(chosen);
    } catch (_) {
      if (mounted) {
        Snack.show(
          context,
          chosen == PhotoSource.camera
              ? 'The camera could not be opened. Check that the app may use it.'
              : 'The gallery could not be opened. Check that the app may use it.',
        );
      }
      return;
    }
    if (photo == null || !mounted) return;

    final type = logoContentType(photo.name);
    if (type == null) {
      Snack.show(context, 'Choose a JPEG, PNG, WebP or GIF picture.');
      return;
    }
    final int size;
    try {
      size = File(photo.path).lengthSync();
    } catch (_) {
      Snack.show(context, 'That picture could not be read. Choose another.');
      return;
    }
    if (size > maxLogoBytes) {
      Snack.show(
        context,
        'That picture is too large. The logo can be at most 2 MB.',
      );
      return;
    }

    final ok = await confirmAction(
      context,
      title: 'Change the company logo?',
      message: 'The new picture replaces the current logo for everyone in the company.',
      confirmLabel: 'Change logo',
    );
    if (!ok || !mounted) return;

    setState(() => _uploading = true);
    try {
      await ref
          .read(companyActionsProvider)
          .changeLogo(
            path: photo.path,
            fileName: photo.name,
            contentType: type,
          );
      if (mounted) Snack.show(context, 'Logo changed.');
    } on AppException catch (e) {
      if (mounted) Snack.error(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(companyProfileProvider);
    try {
      await ref.read(companyProfileProvider.future);
    } on AppException {
      // The panel shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = ref.watch(permissionsProvider).hasAny(Feature.settings);
    return Scaffold(
      appBar: AppBar(title: const Text('Company')),
      body: SafeArea(child: full ? _full() : const _Basic()),
    );
  }

  Widget _full() {
    final profile = ref.watch(companyProfileProvider);
    return profile.when(
      skipLoadingOnReload: true,
      loading: () => const Padding(
        padding: EdgeInsets.all(Space.gutter),
        child: SkeletonList(rows: 4, rowHeight: 80),
      ),
      error: (e, _) => ErrorPanel(
        error: e,
        onRetry: () => ref.invalidate(companyProfileProvider),
      ),
      data: (p) => PageBody(
        onRefresh: _refresh,
        children: [
          _Header(
            name: p.displayName,
            slug: p.slug,
            logoUrl: p.logoUrl,
            uploading: _uploading,
            onChangeLogo: _changeLogo,
          ),
          const SizedBox(height: Space.md),
          StatusFilterRow(
            options: [for (final t in _Tab.values) (t.name, t.label)],
            selected: _tab.name,
            onSelected: (v) => setState(
              () => _tab = _Tab.values.firstWhere(
                (t) => t.name == v,
                orElse: () => _tab,
              ),
            ),
          ),
          switch (_tab) {
            _Tab.profile => _ProfileTab(profile: p),
            _Tab.business => _BusinessTab(profile: p),
            _Tab.sectors => _SectorsTab(profile: p),
            _Tab.roles => _RolesTab(profile: p),
            _Tab.workflows => _WorkflowsTab(profile: p),
            _Tab.settings => _SettingsTab(profile: p),
          },
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.slug,
    required this.logoUrl,
    this.uploading = false,
    this.onChangeLogo,
  });
  final String name;
  final String slug;
  final String? logoUrl;
  final bool uploading;
  final VoidCallback? onChangeLogo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              CompanyLogo(name: name, url: logoUrl, size: 64),
              if (uploading)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
            ],
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppType.bodyStrong.copyWith(color: c.text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (slug.isNotEmpty)
                  Text(
                    slug,
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                if (onChangeLogo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: TextButton.icon(
                      onPressed: uploading ? null : onChangeLogo,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: Text(uploading ? 'Uploading…' : 'Change logo'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a signed-in person without `settings.*` can see: what the sign-in carries.
class _Basic extends ConsumerWidget {
  const _Basic();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = ref.watch(sessionProvider).me?.tenant;
    if (t == null) {
      return const EmptyState(
        icon: Icons.apartment_rounded,
        title: 'Not signed in',
        message: 'Sign in to see your company.',
      );
    }
    return PageBody(
      children: [
        _Header(name: t.name, slug: t.slug, logoUrl: t.logoUrl),
        const SizedBox(height: Space.md),
        _FieldsCard([
          _F('Company name', t.name),
          _F('Currency', t.defaultCurrency),
          _F('Time zone', t.timezone),
          _F('Country', t.countryCode),
        ]),
        const SizedBox(height: Space.md),
        Text(
          'Your role does not include the full company profile. Ask an administrator if you need to see or change it.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
      ],
    );
  }
}

// ---- field rows -------------------------------------------------------------

class _F {
  const _F(this.label, this.value, {this.icon, this.onTap});
  final String label;
  final String? value;
  final IconData? icon;

  /// Opens the value (a call, an email, a web page).
  final VoidCallback? onTap;
}

class _FieldsCard extends StatelessWidget {
  const _FieldsCard(this.fields);
  final List<_F> fields;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) Divider(height: Space.xl, color: c.borderSoft),
            _FieldRow(fields[i]),
          ],
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow(this.f);
  final _F f;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final has = f.value != null && f.value!.isNotEmpty;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (f.icon != null) ...[
          Icon(f.icon, size: 18, color: c.textMuted),
          const SizedBox(width: Space.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.label, style: AppType.helper.copyWith(color: c.textMuted)),
              const SizedBox(height: 2),
              Text(
                has ? f.value! : 'Not set',
                style: AppType.body.copyWith(
                  color: has
                      ? (f.onTap != null ? c.primaryText : c.text)
                      : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (f.onTap == null || !has) return row;
    return Semantics(
      button: true,
      label: '${f.label}: ${f.value}',
      excludeSemantics: true,
      child: InkWell(onTap: f.onTap, child: row),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md),
    child: Text(
      text,
      style: AppType.helper.copyWith(color: context.colors.textMuted),
    ),
  );
}

class _EditButton extends StatelessWidget {
  const _EditButton(this.section);
  final String section;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => context.push('/more/company/edit/$section'),
    icon: const Icon(Icons.edit_outlined, size: 18),
    label: const Text('Edit'),
  );
}

// ---- tabs -------------------------------------------------------------------

class _ProfileTab extends ConsumerWidget {
  const _ProfileTab({required this.profile});
  final CompanyProfile profile;

  /// A web address as typed, opened with `https://` when it has no scheme.
  static String webAddress(String raw) {
    final t = raw.trim();
    return t.startsWith('http://') || t.startsWith('https://')
        ? t
        : 'https://$t';
  }

  Future<void> _open(
    BuildContext context,
    Future<bool> opened,
    String what,
  ) async {
    if (!await opened && context.mounted) {
      Snack.show(context, 'Could not open the $what on this phone.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final launcher = ref.read(contactLauncherProvider);
    final i = p.individual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          p.isIndividual ? 'BUSINESS PROFILE' : 'COMPANY PROFILE',
          trailing: const _EditButton('profile'),
        ),
        _FieldsCard([
          _F(p.isIndividual ? 'Business name' : 'Company name', p.displayName),
          _F('Description', p.shownDescription),
          _F(
            'Business phone',
            p.shownPhone,
            icon: Icons.phone_outlined,
            onTap: () =>
                _open(context, launcher.call(p.shownPhone!), 'dialler'),
          ),
          _F(
            'Business email',
            p.shownEmail,
            icon: Icons.mail_outline_rounded,
            onTap: () =>
                _open(context, launcher.email(p.shownEmail!), 'email app'),
          ),
          _F(
            'Website',
            p.website,
            icon: Icons.language_rounded,
            onTap: () => _open(
              context,
              launcher.openLink(webAddress(p.website!)),
              'website',
            ),
          ),
          _F('City', p.shownCity, icon: Icons.place_outlined),
          if (p.isIndividual) ...[
            _F('Primary sector', i?.primarySector),
            _F(
              'Business size',
              i?.businessSize == null ? null : '${i!.businessSize} employees',
            ),
          ],
          _F('Account type', p.isIndividual ? 'Individual' : 'Company'),
          _F('Short name (slug)', p.slug),
        ]),
      ],
    );
  }
}

class _BusinessTab extends StatelessWidget {
  const _BusinessTab({required this.profile});
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final years = p.shownYears;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'BUSINESS DETAILS',
          trailing: _EditButton('business'),
        ),
        _FieldsCard([
          if (!p.isIndividual) ...[
            _F('Legal name', p.legalName, icon: Icons.business_center_outlined),
            _F('Company size', p.companySizeLabel),
          ],
          _F(
            'Registration number',
            p.shownRegistration,
            icon: Icons.tag_rounded,
          ),
          _F('Tax number', p.shownTax, icon: Icons.tag_rounded),
          _F(
            'Years operating',
            years == null ? null : '$years ${years == 1 ? 'year' : 'years'}',
          ),
        ]),
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips(this.names, {required this.empty});
  final List<String> names;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (names.isEmpty) {
      return Text(empty, style: AppType.body.copyWith(color: c.textMuted));
    }
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final n in names)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.xs + 1,
            ),
            decoration: BoxDecoration(
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(Corners.sm),
            ),
            child: Text(n, style: AppType.label.copyWith(color: c.text)),
          ),
      ],
    );
  }
}

class _SectorsTab extends StatelessWidget {
  const _SectorsTab({required this.profile});
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('SECTORS'),
        AppCard(
          child: _Chips([
            for (final s in profile.sectors) s.name,
          ], empty: 'None configured'),
        ),
        const SectionHeader('PROJECT TYPES'),
        AppCard(
          child: _Chips([
            for (final t in profile.projectTypes) t.name,
          ], empty: 'None configured'),
        ),
        const _Note(
          'These are set up on the web app and cannot be changed here yet.',
        ),
      ],
    );
  }
}

class _RolesTab extends StatelessWidget {
  const _RolesTab({required this.profile});
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = profile.stakeholders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('TEAM ROLES'),
        if (list.isEmpty)
          AppCard(
            child: Text(
              'No stakeholders configured',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          ),
        for (final s in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: AppCard(
              child: AdaptiveRow(
                start: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    if (s.type != null)
                      Text(
                        s.type!,
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
                end: s.roleName == null
                    ? const SizedBox.shrink()
                    : StatusBadge(
                        label: s.roleName!,
                        tone: StatusTone.neutral,
                        dense: true,
                      ),
              ),
            ),
          ),
        const _Note(
          'These are set up on the web app and cannot be changed here yet.',
        ),
      ],
    );
  }
}

class _WorkflowsTab extends StatelessWidget {
  const _WorkflowsTab({required this.profile});
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = profile.workflows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('WORKFLOW TEMPLATES'),
        if (list.isEmpty)
          AppCard(
            child: Text(
              'No workflows configured',
              style: AppType.body.copyWith(color: c.textMuted),
            ),
          ),
        for (final w in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: AppCard(
              child: AdaptiveRow(
                start: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.name,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    if (w.stages != null)
                      Text(
                        '${w.stages} ${w.stages == 1 ? 'stage' : 'stages'}',
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                  ],
                ),
                end: StatusBadge(
                  label: w.isEnabled ? 'Enabled' : 'Disabled',
                  tone: w.isEnabled ? StatusTone.success : StatusTone.muted,
                  dense: true,
                ),
              ),
            ),
          ),
        const _Note(
          'These are set up on the web app and cannot be changed here yet.',
        ),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.profile});
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    final s = profile.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'BUSINESS SETTINGS',
          trailing: _EditButton('settings'),
        ),
        _FieldsCard([
          _F('Currency', s.currency),
          _F(
            'Tax',
            '${s.taxRate == s.taxRate.roundToDouble() ? s.taxRate.toInt() : s.taxRate}% ${s.taxName}',
          ),
          _F('Invoice numbers', s.invoiceFormat),
          _F('Quote numbers', s.quoteFormat),
          _F('Purchase order numbers', s.purchaseOrderFormat),
        ]),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          children: [
            StatusBadge(
              label: s.approvalRequired ? 'Approvals ON' : 'Approvals OFF',
              tone: s.approvalRequired ? StatusTone.success : StatusTone.muted,
            ),
            StatusBadge(
              label: s.notificationsEnabled
                  ? 'Notifications ON'
                  : 'Notifications OFF',
              tone: s.notificationsEnabled
                  ? StatusTone.success
                  : StatusTone.muted,
            ),
          ],
        ),
        const _Note(
          'At the moment the server applies only the purchase order prefix when it numbers new documents. The other numbers, the tax rate and the two switches are saved but do not change anything yet.',
        ),
      ],
    );
  }
}
