import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/company_providers.dart';
import '../application/profile_actions.dart' show validatePhone;
import '../data/company_models.dart';

// ---- validation ---------------------------------------------------------------

/// A name: required, a sensible length.
String? validateCompanyName(String? raw, {String what = 'company name'}) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Enter the $what';
  if (t.length > 120) return 'Keep it under 120 characters';
  return null;
}

/// Free text that may be left empty.
String? validateCompanyText(String? raw, {required int max}) =>
    (raw ?? '').trim().length > max ? 'Keep it under $max characters' : null;

/// An email address that may be left empty.
String? validateBusinessEmail(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (t.length > 120 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)) {
    return 'Enter a full email address';
  }
  return null;
}

/// A web address that may be left empty: no spaces, and a dot in it.
String? validateWebsite(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (t.length > 200 || t.contains(RegExp(r'\s')) || !t.contains('.')) {
    return 'Enter a web address such as www.example.com';
  }
  return null;
}

/// How many years: a whole number from 0 to 150. The server cannot empty it
/// again, so it may be left blank only if it was blank before.
String? validateYearsOperating(String? raw, {required bool wasSet}) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return wasSet ? 'Enter a number of years' : null;
  final v = int.tryParse(t);
  if (v == null) return 'Enter a whole number';
  if (v < 0 || v > 150) return 'Enter a number from 0 to 150';
  return null;
}

/// A document prefix: 1 to 10 letters or digits.
String? validatePrefix(String? raw) {
  final t = (raw ?? '').trim();
  if (!RegExp(r'^[A-Za-z0-9]{1,10}$').hasMatch(t)) {
    return 'Use 1 to 10 letters or digits';
  }
  return null;
}

/// The next document number: a whole number from 1.
String? validateNextNumber(String? raw) {
  final v = int.tryParse((raw ?? '').trim());
  if (v == null) return 'Enter a whole number';
  if (v < 1 || v > 999999) return 'Enter a number from 1 to 999999';
  return null;
}

/// A tax rate in percent: 0 to 100, at most two decimals.
String? validateTaxRate(String? raw) {
  final t = (raw ?? '').trim().replaceAll(',', '.');
  final v = double.tryParse(t);
  if (v == null || !v.isFinite) return 'Enter a percentage';
  if (v < 0 || v > 100) return 'Enter a number from 0 to 100';
  final dot = t.indexOf('.');
  if (dot >= 0 && t.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

/// The name of the tax (VAT…): required, short.
String? validateTaxName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Enter the tax name';
  if (t.length > 20) return 'Keep it under 20 characters';
  return null;
}

/// The text now in [c] when it differs from [before] (nothing is "different" from
/// a blank that was never set), otherwise null, so only real changes are sent.
String? _changed(TextEditingController c, String? before) {
  final now = c.text.trim();
  return now == (before ?? '') ? null : now;
}

// ---- the screen ---------------------------------------------------------------

/// Edits one part of the company's profile: `profile` (name, description,
/// contact), `business` (legal name, size, registration, tax, years) or
/// `settings` (tax, document numbering, switches). Needs `settings.*`. Only what
/// was changed is sent.
class CompanyEditScreen extends ConsumerWidget {
  const CompanyEditScreen({super.key, required this.section});
  final String section;

  static String titleFor(String section) => switch (section) {
    'business' => 'Business details',
    'settings' => 'Business settings',
    _ => 'Company profile',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(permissionsProvider).hasAny(Feature.settings);
    final profile = ref.watch(companyProfileProvider);
    return Scaffold(
      appBar: AppBar(title: Text(titleFor(section))),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot change the company profile.',
              )
            : profile.when(
                // Keep the form (and what was typed) if the profile is read
                // again while it is open.
                skipLoadingOnReload: true,
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 4, rowHeight: 64),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(companyProfileProvider),
                ),
                data: (p) => switch (section) {
                  'business' => _BusinessForm(profile: p),
                  'settings' => _SettingsForm(profile: p),
                  _ => _ProfileForm(profile: p),
                },
              ),
      ),
    );
  }
}

/// The save button's behaviour shared by the three forms: one save at a time, a
/// confirmation where asked, "nothing changed" when nothing was, and the error
/// kept on the form.
mixin _SavesCompany<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  bool saving = false;
  bool _confirming = false;
  AppException? error;

  Future<void> submit(
    CompanyChange change, {
    String? confirmTitle,
    String? confirmMessage,
    String? confirmLabel,
  }) async {
    if (saving || _confirming) return;
    if (change.isEmpty) {
      Snack.show(context, 'Nothing was changed.');
      return;
    }
    if (confirmMessage != null) {
      // Set before the sheet opens: a second activation in the same frame would
      // otherwise open a second confirmation.
      _confirming = true;
      final bool ok;
      try {
        ok = await confirmAction(
          context,
          title: confirmTitle ?? 'Save these changes?',
          message: confirmMessage,
          confirmLabel: confirmLabel ?? 'Save',
        );
      } finally {
        _confirming = false;
      }
      if (!ok || !mounted || saving) return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref.read(companyActionsProvider).save(change);
      if (!mounted) return;
      Snack.show(context, 'Saved.');
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

// ---- profile ------------------------------------------------------------------

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});
  final CompanyProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm>
    with _SavesCompany<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.displayName);
  late final _description = TextEditingController(
    text: widget.profile.shownDescription ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.profile.shownPhone ?? '',
  );
  late final _email = TextEditingController(
    text: widget.profile.shownEmail ?? '',
  );
  late final _website = TextEditingController(
    text: widget.profile.website ?? '',
  );
  late final _city = TextEditingController(
    text: widget.profile.shownCity ?? '',
  );
  late final _sector = TextEditingController(
    text: widget.profile.individual?.primarySector ?? '',
  );
  late String? _size = widget.profile.individual?.businessSize;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _email.dispose();
    _website.dispose();
    _city.dispose();
    _sector.dispose();
    super.dispose();
  }

  Future<void> _pickSize() async {
    final picked = await pickOne<String>(
      context,
      title: 'How many people work in the business?',
      selected: _size,
      options: [
        for (final s in IndividualBusiness.sizes)
          PickerOption(value: s, title: '$s employees'),
      ],
    );
    if (picked?.value != null && mounted) setState(() => _size = picked!.value);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final p = widget.profile;
    final i = p.individual;
    final name = _changed(_name, p.displayName);
    final description = _changed(_description, p.shownDescription);
    final phone = _changed(_phone, p.shownPhone);
    final email = _changed(_email, p.shownEmail);
    final website = _changed(_website, p.website);
    final city = _changed(_city, p.shownCity);
    final sector = _changed(_sector, i?.primarySector);
    final size = _size == i?.businessSize ? null : _size;
    await submit(
      CompanyChange(
        // A sole trader's name lives in their business profile.
        name: p.isIndividual ? null : name,
        description: description,
        website: website,
        businessPhone: phone,
        businessEmail: email,
        city: city,
        individual: p.isIndividual
            ? {
                'businessName': ?name,
                'primarySector': ?sector,
                'businessSize': ?size,
                'description': ?description,
                'businessEmail': ?email,
                'city': ?city,
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.profile;
    return PageBody(
      children: [
        Text(
          'How the company appears and how people reach it. The logo is changed from the company page.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: p.isIndividual ? 'Business name' : 'Company name',
                controller: _name,
                enabled: !saving,
                validator: (v) => validateCompanyName(
                  v,
                  what: p.isIndividual ? 'business name' : 'company name',
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Description (optional)',
                controller: _description,
                enabled: !saving,
                minLines: 3,
                maxLines: 6,
                validator: (v) => validateCompanyText(v, max: 1000),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Business phone (optional)',
                controller: _phone,
                enabled: !saving,
                hint: '+263 77 123 4567',
                keyboardType: TextInputType.phone,
                validator: validatePhone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Business email (optional)',
                controller: _email,
                enabled: !saving,
                keyboardType: TextInputType.emailAddress,
                validator: validateBusinessEmail,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Website (optional)',
                controller: _website,
                enabled: !saving,
                hint: 'www.example.com',
                keyboardType: TextInputType.url,
                validator: validateWebsite,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'City (optional)',
                controller: _city,
                enabled: !saving,
                validator: (v) => validateCompanyText(v, max: 80),
                textCapitalization: TextCapitalization.words,
              ),
              if (p.isIndividual) ...[
                const SizedBox(height: Space.lg),
                AppTextField(
                  label: 'Primary sector (optional)',
                  controller: _sector,
                  enabled: !saving,
                  validator: (v) => validateCompanyText(v, max: 80),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: Space.lg),
                PickerField(
                  label: 'Business size',
                  icon: Icons.groups_2_outlined,
                  value: _size == null ? null : '$_size employees',
                  placeholder: 'Choose the size',
                  enabled: !saving,
                  onTap: _pickSize,
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                loading: saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- business details ----------------------------------------------------------

class _BusinessForm extends ConsumerStatefulWidget {
  const _BusinessForm({required this.profile});
  final CompanyProfile profile;

  @override
  ConsumerState<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends ConsumerState<_BusinessForm>
    with _SavesCompany<_BusinessForm> {
  final _form = GlobalKey<FormState>();
  late final _legal = TextEditingController(
    text: widget.profile.legalName ?? '',
  );
  late final _registration = TextEditingController(
    text: widget.profile.shownRegistration ?? '',
  );
  late final _tax = TextEditingController(text: widget.profile.shownTax ?? '');
  late final _years = TextEditingController(
    text: widget.profile.shownYears?.toString() ?? '',
  );
  late String? _size = widget.profile.companySize;

  @override
  void dispose() {
    _legal.dispose();
    _registration.dispose();
    _tax.dispose();
    _years.dispose();
    super.dispose();
  }

  Future<void> _pickSize() async {
    final picked = await pickOne<String>(
      context,
      title: 'Company size',
      selected: _size,
      options: [
        for (final s in CompanyProfile.companySizes)
          PickerOption(value: s, title: CompanyProfile.labelForSize(s)!),
      ],
    );
    if (picked?.value != null && mounted) setState(() => _size = picked!.value);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final p = widget.profile;
    final legal = _changed(_legal, p.legalName);
    final registration = _changed(_registration, p.shownRegistration);
    final tax = _changed(_tax, p.shownTax);
    final typedYears = int.tryParse(_years.text.trim());
    final years = typedYears == p.shownYears ? null : typedYears;
    final size = _size == p.companySize ? null : _size;
    await submit(
      CompanyChange(
        legalName: p.isIndividual ? null : legal,
        companySize: p.isIndividual ? null : size,
        registrationNumber: registration,
        taxNumber: tax,
        yearsOperating: years,
        // A sole trader keeps these in their business profile too, as the web
        // app does.
        individual: p.isIndividual
            ? {
                'registrationNumber': ?registration,
                'taxNumber': ?tax,
                'yearsOperating': ?years,
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = widget.profile;
    return PageBody(
      children: [
        Text(
          'Registration and tax details, as they appear on documents.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!p.isIndividual) ...[
                AppTextField(
                  label: 'Legal name (optional)',
                  controller: _legal,
                  enabled: !saving,
                  validator: (v) => validateCompanyText(v, max: 160),
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: Space.lg),
                PickerField(
                  label: 'Company size',
                  icon: Icons.groups_2_outlined,
                  value: CompanyProfile.labelForSize(_size),
                  placeholder: 'Choose the size',
                  enabled: !saving,
                  onTap: _pickSize,
                ),
                const SizedBox(height: Space.lg),
              ],
              AppTextField(
                label: 'Registration number (optional)',
                controller: _registration,
                enabled: !saving,
                validator: (v) => validateCompanyText(v, max: 60),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Tax number (optional)',
                controller: _tax,
                enabled: !saving,
                validator: (v) => validateCompanyText(v, max: 60),
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Years operating (optional)',
                controller: _years,
                enabled: !saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => validateYearsOperating(
                  v,
                  wasSet: widget.profile.shownYears != null,
                ),
                helper: 'It can be changed to another number but not removed.',
              ),
              if (error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Save changes',
                icon: Icons.check_rounded,
                loading: saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---- business settings ------------------------------------------------------------

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.profile});
  final CompanyProfile profile;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm>
    with _SavesCompany<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late final CompanySettings _s = widget.profile.settings;
  late final _taxName = TextEditingController(text: _s.taxName);
  late final _taxRate = TextEditingController(text: _rate(_s.taxRate));
  late final _invoicePrefix = TextEditingController(text: _s.invoicePrefix);
  late final _invoiceNext = TextEditingController(
    text: '${_s.invoiceNextNumber}',
  );
  late final _quotePrefix = TextEditingController(text: _s.quotePrefix);
  late final _quoteNext = TextEditingController(text: '${_s.quoteNextNumber}');
  late final _poPrefix = TextEditingController(text: _s.purchaseOrderPrefix);
  late final _poNext = TextEditingController(text: '${_s.purchaseOrderNext}');
  late String _currency = _s.currency;
  late bool _approval = _s.approvalRequired;
  late bool _notifications = _s.notificationsEnabled;

  static String _rate(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  @override
  void dispose() {
    for (final c in [
      _taxName,
      _taxRate,
      _invoicePrefix,
      _invoiceNext,
      _quotePrefix,
      _quoteNext,
      _poPrefix,
      _poNext,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCurrency() async {
    // A currency the company already has is kept in the list even if the web
    // app's own list does not include it.
    final all = {...CompanySettings.currencies, _s.currency}.toList();
    final picked = await pickOne<String>(
      context,
      title: 'Currency',
      selected: _currency,
      options: [for (final cur in all) PickerOption(value: cur, title: cur)],
    );
    if (picked?.value != null && mounted) {
      setState(() => _currency = picked!.value!);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final s = _s;
    final changes = <String, Object?>{};
    final lines = <String>[];

    void text(
      String key,
      String label,
      TextEditingController c,
      String before,
    ) {
      final now = c.text.trim();
      if (now == before) return;
      changes[key] = now;
      lines.add('$label: $before → $now');
    }

    void whole(String key, String label, TextEditingController c, int before) {
      final now = int.parse(c.text.trim());
      if (now == before) return;
      changes[key] = now;
      lines.add('$label: $before → $now');
    }

    if (_currency != s.currency) {
      changes['currency'] = _currency;
      lines.add('Currency: ${s.currency} → $_currency');
    }
    text('taxName', 'Tax name', _taxName, s.taxName);
    final rate = double.parse(_taxRate.text.trim().replaceAll(',', '.'));
    if (rate != s.taxRate) {
      changes['taxRate'] = rate;
      lines.add('Tax rate: ${_rate(s.taxRate)}% → ${_rate(rate)}%');
    }
    text('invoicePrefix', 'Invoice prefix', _invoicePrefix, s.invoicePrefix);
    whole(
      'invoiceNextNumber',
      'Next invoice number',
      _invoiceNext,
      s.invoiceNextNumber,
    );
    text('quotePrefix', 'Quote prefix', _quotePrefix, s.quotePrefix);
    whole(
      'quoteNextNumber',
      'Next quote number',
      _quoteNext,
      s.quoteNextNumber,
    );
    text(
      'purchaseOrderPrefix',
      'Purchase order prefix',
      _poPrefix,
      s.purchaseOrderPrefix,
    );
    whole(
      'purchaseOrderNext',
      'Next purchase order number',
      _poNext,
      s.purchaseOrderNext,
    );
    if (_approval != s.approvalRequired) {
      changes['approvalRequired'] = _approval;
      lines.add(
        'Require approvals: ${s.approvalRequired ? 'on' : 'off'} → ${_approval ? 'on' : 'off'}',
      );
    }
    if (_notifications != s.notificationsEnabled) {
      changes['notificationsEnabled'] = _notifications;
      lines.add(
        'Notifications: ${s.notificationsEnabled ? 'on' : 'off'} → ${_notifications ? 'on' : 'off'}',
      );
    }

    await submit(
      CompanyChange(settings: changes),
      confirmTitle: 'Change the business settings?',
      confirmMessage: 'These apply to the whole company:\n${lines.join('\n')}',
      confirmLabel: 'Save settings',
    );
  }

  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (context, box) {
      // Side by side; stacked when text is enlarged so neither is squeezed.
      final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
      return stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                a,
                const SizedBox(height: Space.lg),
                b,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: a),
                const SizedBox(width: Space.md),
                Expanded(child: b),
              ],
            );
    },
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final companyCurrency = ref
        .watch(sessionProvider)
        .me
        ?.tenant
        .defaultCurrency;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return PageBody(
      children: [
        Text(
          'Tax and document numbering for the whole company. At the moment the server applies only the purchase order prefix when it numbers new documents; the rest is saved for later.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickerField(
                label: 'Currency',
                icon: Icons.payments_outlined,
                value: _currency,
                enabled: !saving,
                onTap: _pickCurrency,
              ),
              if (companyCurrency != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    'Amounts in the app follow the company currency set when it was created ($companyCurrency). This setting does not change that.',
                    style: AppType.helper.copyWith(color: c.textMuted),
                  ),
                ),
              const SizedBox(height: Space.lg),
              _pair(
                AppTextField(
                  label: 'Tax name',
                  controller: _taxName,
                  enabled: !saving,
                  validator: validateTaxName,
                  textInputAction: TextInputAction.next,
                ),
                AppTextField(
                  label: 'Tax rate (%)',
                  controller: _taxRate,
                  enabled: !saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: validateTaxRate,
                ),
              ),
              const SizedBox(height: Space.lg),
              _pair(
                AppTextField(
                  label: 'Invoice prefix',
                  controller: _invoicePrefix,
                  enabled: !saving,
                  validator: validatePrefix,
                  textCapitalization: TextCapitalization.characters,
                ),
                AppTextField(
                  label: 'Next invoice number',
                  controller: _invoiceNext,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: validateNextNumber,
                ),
              ),
              const SizedBox(height: Space.lg),
              _pair(
                AppTextField(
                  label: 'Quote prefix',
                  controller: _quotePrefix,
                  enabled: !saving,
                  validator: validatePrefix,
                  textCapitalization: TextCapitalization.characters,
                ),
                AppTextField(
                  label: 'Next quote number',
                  controller: _quoteNext,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: validateNextNumber,
                ),
              ),
              const SizedBox(height: Space.lg),
              _pair(
                AppTextField(
                  label: 'Purchase order prefix',
                  controller: _poPrefix,
                  enabled: !saving,
                  validator: validatePrefix,
                  textCapitalization: TextCapitalization.characters,
                ),
                AppTextField(
                  label: 'Next order number',
                  controller: _poNext,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  validator: validateNextNumber,
                ),
              ),
              const SizedBox(height: Space.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Require approvals'),
                value: _approval,
                onChanged: saving ? null : (v) => setState(() => _approval = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifications enabled'),
                value: _notifications,
                onChanged: saving
                    ? null
                    : (v) => setState(() => _notifications = v),
              ),
              if (error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Save settings',
                icon: Icons.check_rounded,
                loading: saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
