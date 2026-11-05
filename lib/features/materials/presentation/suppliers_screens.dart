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
import '../../../shared/services/contact_launcher.dart';
import '../application/materials_providers.dart';
import '../data/material_reference_models.dart';

String? validateSupplierName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Give the supplier a name';
  if (t.length > 120) return 'Keep the name under 120 characters';
  return null;
}

String? validateSupplierEmail(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
  return ok ? null : 'Enter an email address like name@example.com';
}

/// The company's suppliers (where materials are bought or delivered from).
/// People who can manage inventory can add one.
class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final suppliers = ref.watch(suppliersProvider);
    final canAdd = ref
        .watch(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    return Scaffold(
      appBar: AppBar(title: const Text('Suppliers')),
      body: SafeArea(
        child: PageBody(
          onRefresh: () async {
            ref.invalidate(suppliersProvider);
            try {
              await ref.read(suppliersProvider.future);
            } catch (_) {
              // The list shows its own error.
            }
          },
          children: [
            if (canAdd) ...[
              AppButton(
                label: 'Add a supplier',
                icon: Icons.add_business_outlined,
                onPressed: () async {
                  await context.push<Supplier>('/materials/suppliers/new');
                },
              ),
              const SizedBox(height: Space.md),
            ],
            suppliers.when(
              loading: () => const SkeletonList(rows: 4, rowHeight: 80),
              error: (e, _) => ErrorPanel(
                error: e,
                compact: true,
                onRetry: () => ref.invalidate(suppliersProvider),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: Space.x3),
                      child: EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'No suppliers yet',
                        message: 'Add where you buy materials from.',
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.sm),
                            child: AppCard(
                              onTap: () => _showSupplier(context, ref, s),
                              semanticLabel: s.name,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: AppType.bodyStrong.copyWith(
                                      color: c.text,
                                    ),
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    [
                                      if (s.phone != null) s.phone!,
                                      if (s.email != null) s.email!,
                                      if (s.materialCount > 0)
                                        '${s.materialCount} ${s.materialCount == 1 ? 'material' : 'materials'}',
                                    ].join(' · '),
                                    style: AppType.helper.copyWith(
                                      color: c.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupplier(BuildContext context, WidgetRef ref, Supplier s) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SupplierSheet(supplier: s),
    );
  }
}

class _SupplierSheet extends ConsumerWidget {
  const _SupplierSheet({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final s = supplier;
    final launcher = ref.read(contactLauncherProvider);
    Widget fact(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppType.helper.copyWith(color: c.textMuted)),
                Text(value, style: AppType.body.copyWith(color: c.text)),
              ],
            ),
          );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.xxl,
        Space.sm,
        Space.xxl,
        Space.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.name, style: AppType.sectionTitle.copyWith(color: c.text)),
          const SizedBox(height: Space.lg),
          fact('Phone', s.phone),
          fact('Email', s.email),
          fact('Address', s.address),
          fact('Website', s.website),
          fact('Notes', s.notes),
          if (s.phone != null) ...[
            AppButton(
              label: 'Call',
              icon: Icons.call_outlined,
              onPressed: () async {
                final ok = await launcher.call(s.phone!);
                if (!ok && context.mounted) {
                  Snack.show(
                    context,
                    'Could not start the call. The number is ${s.phone}.',
                  );
                }
              },
            ),
            const SizedBox(height: Space.sm),
          ],
          if (s.email != null)
            AppButton(
              label: 'Email',
              icon: Icons.mail_outline_rounded,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                final ok = await launcher.email(s.email!);
                if (!ok && context.mounted) {
                  Snack.show(
                    context,
                    'Could not open email. The address is ${s.email}.',
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

/// Add a supplier. Needs `materials.manage_inventory`. When opened to choose a
/// supplier for something else, the new supplier is returned to it.
class SupplierFormScreen extends ConsumerStatefulWidget {
  const SupplierFormScreen({super.key});

  @override
  ConsumerState<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends ConsumerState<SupplierFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _website = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  AppException? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _website, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(materialManagementProvider)
          .createSupplier(
            SupplierInput(
              name: _name.text,
              phone: _phone.text,
              email: _email.text,
              address: _address.text,
              website: _website.text,
              notes: _notes.text,
            ),
          );
      if (!mounted) return;
      Snack.show(context, saved.note ?? 'Supplier added.');
      context.pop(saved.value);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    return Scaffold(
      appBar: AppBar(title: const Text('New supplier')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot add suppliers.',
              )
            : PageBody(
                children: [
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppTextField(
                          label: 'Supplier name',
                          controller: _name,
                          enabled: !_saving,
                          maxLength: 120,
                          validator: validateSupplierName,
                          textCapitalization: TextCapitalization.words,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Phone (optional)',
                          controller: _phone,
                          enabled: !_saving,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Email (optional)',
                          controller: _email,
                          enabled: !_saving,
                          keyboardType: TextInputType.emailAddress,
                          validator: validateSupplierEmail,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Address (optional)',
                          controller: _address,
                          enabled: !_saving,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Website (optional)',
                          controller: _website,
                          enabled: !_saving,
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Notes (optional)',
                          controller: _notes,
                          enabled: !_saving,
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: 'Add supplier',
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
