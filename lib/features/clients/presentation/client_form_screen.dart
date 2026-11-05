import 'package:flutter/material.dart';
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
import '../../../shared/components/layout.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/clients_providers.dart';
import '../data/client_models.dart';
import '../data/clients_repository.dart';

String? validateClientName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Enter the client name';
  if (t.length > 120) return 'Keep the name under 120 characters';
  return null;
}

/// Optional; when given it must look like an email address (the server checks
/// too).
String? validateClientEmail(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? validateClientPhone(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^[0-9+()\-\s]+$').hasMatch(t)) {
    return 'Use digits, spaces, + and - only';
  }
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7 || t.length > 20) return 'Enter a full phone number';
  return null;
}

String? validateClientText(String? raw, {int max = 300}) {
  if ((raw ?? '').trim().length > max) return 'Keep it under $max characters';
  return null;
}

/// Add a client, or (with [clientId]) change their details. Never sent twice:
/// see [ClientActions.create].
class ClientFormScreen extends ConsumerStatefulWidget {
  const ClientFormScreen({super.key, this.clientId});
  final String? clientId;

  @override
  ConsumerState<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends ConsumerState<ClientFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String _type = ClientType.other;
  bool _loaded = false;
  bool _saving = false;
  AppException? _error;

  bool get _isEdit => widget.clientId != null;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Fills the form from the client being edited, once.
  void _prefill(ClientDetail d) {
    if (_loaded) return;
    _loaded = true;
    final s = d.summary;
    _name.text = s.name;
    _contact.text = s.contactPerson ?? '';
    _email.text = s.email ?? '';
    _phone.text = s.phone ?? '';
    _address.text = d.address ?? '';
    _notes.text = d.notes ?? '';
    _type = s.type;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final input = ClientInput(
      name: _name.text,
      type: _type,
      contactPerson: _contact.text,
      email: _email.text,
      phone: _phone.text,
      address: _address.text,
      notes: _notes.text,
    );
    try {
      final actions = ref.read(clientActionsProvider);
      if (_isEdit) {
        await actions.update(widget.clientId!, input);
        if (!mounted) return;
        Snack.show(context, 'Client updated.');
      } else {
        final note = await actions.create(input);
        if (!mounted) return;
        Snack.show(context, note ?? 'Client added.');
      }
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allowed = ref.watch(permissionsProvider).hasAny(Feature.crmManage);
    final detail = _isEdit
        ? ref.watch(clientDetailProvider(widget.clientId!))
        : null;
    if (detail?.value != null) _prefill(detail!.value!);

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit client' : 'Add client')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot add or change clients.',
              )
            : (_isEdit && detail != null && detail.isLoading && !_loaded)
            ? const Padding(
                padding: EdgeInsets.all(Space.gutter),
                child: SkeletonList(rows: 3, rowHeight: 90),
              )
            : (_isEdit && detail != null && detail.hasError && !_loaded)
            ? ErrorPanel(
                error: detail.error!,
                onRetry: () =>
                    ref.invalidate(clientDetailProvider(widget.clientId!)),
              )
            : PageBody(
                children: [
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          label: 'Name',
                          controller: _name,
                          hint: 'Company or person',
                          validator: validateClientName,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        Text(
                          'Type',
                          style: AppType.label.copyWith(color: c.text),
                        ),
                        const SizedBox(height: Space.sm),
                        Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final t in ClientType.all)
                              ChoiceChip(
                                label: Text(clientTypeLabel(t)),
                                selected: _type == t,
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(() => _type = t),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.padded,
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Contact person (optional)',
                          controller: _contact,
                          validator: (v) => validateClientText(v, max: 80),
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Phone (optional)',
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          validator: validateClientPhone,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Email (optional)',
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          validator: validateClientEmail,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Address (optional)',
                          controller: _address,
                          minLines: 2,
                          maxLines: 4,
                          validator: validateClientText,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Notes (optional)',
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          validator: (v) => validateClientText(v, max: 500),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: _isEdit ? 'Save changes' : 'Add client',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
