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
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../materials/data/material_models.dart';
import '../../materials/presentation/log_usage_screen.dart'
    show parseQuantity, validateQuantity;
import '../../materials/presentation/material_pickers.dart';
import '../../projects/data/project_models.dart';
import '../../projects/presentation/project_picker.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';

String? validateDescription(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Say what is needed';
  if (t.length > 200) return 'Keep it under 200 characters';
  return null;
}

String? validateUnit(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Choose the unit';
  if (t.length > 20) return 'Keep the unit short';
  return null;
}

/// Optional estimated cost per unit: at most 2 decimals, not negative.
String? validateUnitCost(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v < 0) return 'Cannot be negative';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

class _ItemDraft {
  final description = TextEditingController();
  final quantity = TextEditingController();
  final cost = TextEditingController();

  /// The unit chosen from the construction units (null until chosen).
  String? unit;
  String? unitError;

  /// The catalog material this line is for, when it was chosen from the catalog.
  String? materialId;
  String? materialName;

  void dispose() {
    description.dispose();
    quantity.dispose();
    cost.dispose();
  }

  /// Fills the line from a catalog material (its name, unit and price).
  void useMaterial(MaterialItem m) {
    materialId = m.id;
    materialName = m.name;
    description.text = m.name;
    unit = m.unit.isEmpty ? unit : m.unit;
    unitError = null;
    cost.text = m.unitCost > 0 ? m.unitCost.toStringAsFixed(2) : cost.text;
  }

  NewPrItem toItem() {
    final costText = cost.text.trim().replaceAll(',', '.');
    return NewPrItem(
      description: description.text.trim(),
      quantity: parseQuantity(quantity.text)!,
      unit: (unit ?? '').trim(),
      estimatedUnitCost: costText.isEmpty ? null : double.parse(costText),
      materialId: materialId,
    );
  }
}

/// Ask for materials. Each line is a material from the catalog (or a new one made
/// on the spot) or just described in words. Saved as a draft, or submitted for
/// approval straight away. Creating is never repeated blindly; see
/// [PurchasingActions.create].
class NewPurchaseRequestScreen extends ConsumerStatefulWidget {
  const NewPurchaseRequestScreen({super.key});

  @override
  ConsumerState<NewPurchaseRequestScreen> createState() =>
      _NewPurchaseRequestScreenState();
}

class _NewPurchaseRequestScreenState
    extends ConsumerState<NewPurchaseRequestScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _items = <_ItemDraft>[_ItemDraft()];
  ProjectSummary? _project;
  bool _saving = false;
  bool _pickingProject = false;
  AppException? _error;

  @override
  void dispose() {
    _notes.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _pickProject() async {
    if (_pickingProject) return;
    setState(() => _pickingProject = true);
    try {
      final picked = await chooseProject(
        context,
        ref,
        title: 'Choose a project',
        selected: _project,
        clearLabel: 'No specific project',
      );
      if (picked != null && mounted) setState(() => _project = picked.value);
    } finally {
      if (mounted) setState(() => _pickingProject = false);
    }
  }

  Future<void> _pickMaterial(_ItemDraft item) async {
    final picked = await chooseMaterial(
      context,
      allowCreate: ref
          .read(permissionsProvider)
          .hasAny(Feature.materialsInventory),
    );
    if (picked != null && mounted) setState(() => item.useMaterial(picked));
  }

  Future<void> _pickUnit(_ItemDraft item) async {
    final picked = await chooseUnit(context, current: item.unit);
    if (picked != null && mounted) {
      setState(() {
        item.unit = picked;
        item.unitError = null;
      });
    }
  }

  Future<void> _save({required bool submit}) async {
    if (_saving) return;
    setState(() => _error = null);
    var unitsOk = true;
    for (final i in _items) {
      i.unitError = validateUnit(i.unit);
      if (i.unitError != null) unitsOk = false;
    }
    final fieldsOk = _form.currentState!.validate();
    if (!unitsOk) setState(() {});
    if (!fieldsOk || !unitsOk) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(purchasingActionsProvider)
          .create(
            items: [for (final i in _items) i.toItem()],
            projectId: _project?.id,
            notes: _notes.text,
            submit: submit,
          );
      if (!mounted) return;
      final message = result.submitError != null
          ? 'Saved as a draft, but it could not be submitted: ${result.submitError!.message} Open it to try again.'
          : result.note ??
                (result.submitted
                    ? 'Submitted for approval.'
                    : 'Saved as a draft.');
      Snack.show(context, message);
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
    final perms = ref.watch(permissionsProvider);
    final allowed = perms.hasAny(Feature.purchasingManage);
    final canPickProject = perms.hasAny(Feature.projects);

    return Scaffold(
      appBar: AppBar(title: const Text('New purchase request')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot raise purchase requests.',
              )
            : PageBody(
                children: [
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (canPickProject) ...[
                          PickerField(
                            label: 'Project (optional)',
                            icon: Icons.apartment_rounded,
                            value: _project?.label,
                            placeholder: 'No specific project',
                            onTap: _pickingProject ? null : _pickProject,
                          ),
                          const SizedBox(height: Space.lg),
                        ],
                        AppTextField(
                          label: 'Notes (optional)',
                          controller: _notes,
                          hint: 'Why is this needed, and by when?',
                          minLines: 2,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        for (var i = 0; i < _items.length; i++) ...[
                          SectionHeader(
                            'ITEM ${i + 1}',
                            trailing: _items.length > 1
                                ? TextButton(
                                    onPressed: _saving
                                        ? null
                                        : () => setState(() {
                                            _items.removeAt(i).dispose();
                                          }),
                                    child: const Text('Remove'),
                                  )
                                : null,
                          ),
                          AppCard(
                            key: ObjectKey(_items[i]),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PickerField(
                                  label: 'Material',
                                  icon: Icons.inventory_2_outlined,
                                  value: _items[i].materialName,
                                  placeholder: 'Choose from your materials, or describe it below',
                                  enabled: !_saving,
                                  onTap: () => _pickMaterial(_items[i]),
                                ),
                                if (_items[i].materialId != null)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => setState(() {
                                              _items[i].materialId = null;
                                              _items[i].materialName = null;
                                            }),
                                      child: const Text('Not from the catalog'),
                                    ),
                                  ),
                                const SizedBox(height: Space.md),
                                AppTextField(
                                  label: 'What is needed',
                                  controller: _items[i].description,
                                  hint: 'e.g. Portland cement 50kg',
                                  validator: validateDescription,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: Space.md),
                                AdaptiveFields(
                                  first: AppTextField(
                                    label: 'Quantity',
                                    controller: _items[i].quantity,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'[0-9.,]'),
                                      ),
                                    ],
                                    validator: validateQuantity,
                                  ),
                                  second: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      PickerField(
                                        label: 'Unit',
                                        value: _items[i].unit,
                                        placeholder: 'Choose',
                                        enabled: !_saving,
                                        onTap: () => _pickUnit(_items[i]),
                                      ),
                                      if (_items[i].unitError != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: Space.xs,
                                          ),
                                          child: Text(
                                            _items[i].unitError!,
                                            style: AppType.helper.copyWith(
                                              color: c.danger,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: Space.md),
                                AppTextField(
                                  label: 'Estimated cost per unit (optional)',
                                  controller: _items[i].cost,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]'),
                                    ),
                                  ],
                                  validator: validateUnitCost,
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: Space.md),
                        AppButton(
                          label: 'Add another item',
                          icon: Icons.add_rounded,
                          variant: AppButtonVariant.secondary,
                          onPressed: _saving
                              ? null
                              : () => setState(() => _items.add(_ItemDraft())),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: 'Submit for approval',
                          icon: Icons.send_rounded,
                          loading: _saving,
                          onPressed: () => _save(submit: true),
                        ),
                        const SizedBox(height: Space.sm),
                        AppButton(
                          label: 'Save as draft',
                          variant: AppButtonVariant.secondary,
                          onPressed: _saving
                              ? null
                              : () => _save(submit: false),
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'A draft is kept for you to edit on the web app and submit later.',
                          style: AppType.helper.copyWith(color: c.textMuted),
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

/// Two fields side by side; stacked when text is enlarged so neither is squeezed.
class AdaptiveFields extends StatelessWidget {
  const AdaptiveFields({super.key, required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          const SizedBox(height: Space.md),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: first),
        const SizedBox(width: Space.md),
        Expanded(flex: 2, child: second),
      ],
    );
  }
}
