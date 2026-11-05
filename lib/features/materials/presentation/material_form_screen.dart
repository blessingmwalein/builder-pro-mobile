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
import '../application/materials_providers.dart';
import '../data/material_models.dart';
import '../data/material_reference_models.dart';
import 'material_pickers.dart';
import '../../finance/application/finance_providers.dart' show currencyProvider;

String? validateMaterialName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Give the material a name';
  if (t.length > 120) return 'Keep the name under 120 characters';
  return null;
}

/// The price of one unit: required, not negative, at most two decimals.
String? validateMaterialCost(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter the price of one unit';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v < 0) return 'Cannot be negative';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

/// An optional quantity: not negative, at most three decimals.
String? validateOptionalQuantity(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number';
  if (v < 0) return 'Cannot be negative';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 3) return 'Use at most 3 decimals';
  return null;
}

double? _num(String text) {
  final t = text.trim().replaceAll(',', '.');
  return t.isEmpty ? null : double.tryParse(t);
}

/// Add a material to the company's catalog, or change one. Needs
/// `materials.manage_inventory`. The category list is the web app's, and the
/// unit comes from the construction units. Changing a price needs a reason (the
/// server keeps an audit trail of price changes).
///
/// When it was opened to make a material for a request line, saving returns the
/// new material to the screen that asked.
class MaterialFormScreen extends ConsumerStatefulWidget {
  const MaterialFormScreen({super.key, this.editing});
  final MaterialItem? editing;

  @override
  ConsumerState<MaterialFormScreen> createState() => _MaterialFormScreenState();
}

class _MaterialFormScreenState extends ConsumerState<MaterialFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.editing?.name);
  late final _sku = TextEditingController(text: widget.editing?.sku);
  late final _cost = TextEditingController(
    text: widget.editing == null
        ? ''
        : widget.editing!.unitCost.toStringAsFixed(2),
  );
  late final _reorder = TextEditingController(
    text: widget.editing?.reorderAt?.toString() ?? '',
  );
  late final _description = TextEditingController(
    text: widget.editing?.description,
  );
  final _opening = TextEditingController();
  final _reason = TextEditingController();

  late String? _unit = widget.editing?.unit.isEmpty ?? true
      ? null
      : widget.editing!.unit;
  late String? _categoryId = widget.editing?.categoryId;
  late String? _categoryName = widget.editing?.category;
  late String? _supplierId = widget.editing?.supplierId;
  late String? _supplierName = widget.editing?.supplierName;
  String? _unitError;
  bool _saving = false;
  AppException? _error;

  bool get _isEdit => widget.editing != null;

  /// The price was changed on an existing material: a reason is then required.
  bool get _costChanged {
    final e = widget.editing;
    final v = _num(_cost.text);
    return e != null && v != null && (v - e.unitCost).abs() >= 0.005;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _sku,
      _cost,
      _reorder,
      _description,
      _opening,
      _reason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _unitError = _unit == null ? 'Choose the unit' : null;
    });
    if (!_form.currentState!.validate() || _unit == null) return;
    final input = MaterialInput(
      name: _name.text,
      unit: _unit!,
      unitCost: _num(_cost.text)!,
      sku: _sku.text,
      categoryId: _categoryId,
      supplierId: _supplierId,
      reorderAt: _num(_reorder.text),
      description: _description.text,
      openingStock: _isEdit ? null : _num(_opening.text),
      reason: _costChanged ? _reason.text : null,
    );
    setState(() => _saving = true);
    try {
      final mgmt = ref.read(materialManagementProvider);
      if (_isEdit) {
        await mgmt.updateMaterial(widget.editing!.id, input);
        if (!mounted) return;
        Snack.show(context, 'Material updated.');
        context.pop();
      } else {
        final saved = await mgmt.createMaterial(input);
        if (!mounted) return;
        Snack.show(context, saved.note ?? 'Material added.');
        context.pop(saved.value);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit material' : 'New material')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot add or change materials.',
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
                          enabled: !_saving,
                          hint: 'e.g. Portland cement 50kg',
                          maxLength: 120,
                          validator: validateMaterialName,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Category',
                          icon: Icons.category_outlined,
                          value: _categoryName,
                          placeholder: 'No category',
                          enabled: !_saving,
                          onTap: () async {
                            final picked = await chooseCategory(
                              context,
                              ref,
                              selectedId: _categoryId,
                              allowAdd: true,
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _categoryId = picked.value?.id;
                                _categoryName = picked.value?.name;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Unit',
                          icon: Icons.straighten_rounded,
                          value: _unit,
                          placeholder: 'Choose the unit',
                          enabled: !_saving,
                          onTap: () async {
                            final picked = await chooseUnit(
                              context,
                              current: _unit,
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _unit = picked;
                                _unitError = null;
                              });
                            }
                          },
                        ),
                        if (_unitError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: Space.xs),
                            child: Text(
                              _unitError!,
                              style: AppType.helper.copyWith(color: c.danger),
                            ),
                          ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Price of one unit ($currency)',
                          controller: _cost,
                          enabled: !_saving,
                          hint: '0.00',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          validator: validateMaterialCost,
                          onChanged: (_) => setState(() {}),
                        ),
                        if (_costChanged) ...[
                          const SizedBox(height: Space.md),
                          AppTextField(
                            label: 'Why is the price changing?',
                            controller: _reason,
                            enabled: !_saving,
                            helper: 'Kept with the price change so it can be checked later.',
                            textCapitalization: TextCapitalization.sentences,
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Say why the price changed'
                                : null,
                          ),
                        ],
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Supplier (where it is bought)',
                          icon: Icons.local_shipping_outlined,
                          value: _supplierName,
                          placeholder: 'No supplier',
                          enabled: !_saving,
                          onTap: () async {
                            final picked = await chooseSupplier(
                              context,
                              ref,
                              selectedId: _supplierId,
                              allowAdd: true,
                              allowNone: true,
                            );
                            if (picked != null && mounted) {
                              setState(() {
                                _supplierId = picked.value?.id;
                                _supplierName = picked.value?.name;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Code (optional)',
                          controller: _sku,
                          enabled: !_saving,
                          hint: 'Supplier or stock code',
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Reorder when stock falls to (optional)',
                          controller: _reorder,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          validator: validateOptionalQuantity,
                        ),
                        if (!_isEdit) ...[
                          const SizedBox(height: Space.lg),
                          AppTextField(
                            label: 'Stock on hand now (optional)',
                            controller: _opening,
                            enabled: !_saving,
                            helper: 'What you have counted. Deliveries and use change it from here.',
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.,]'),
                              ),
                            ],
                            validator: validateOptionalQuantity,
                          ),
                        ],
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Description (optional)',
                          controller: _description,
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
                          label: _isEdit ? 'Save changes' : 'Add material',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                        if (_isEdit) ...[
                          const SizedBox(height: Space.md),
                          Text(
                            'Stock is changed by deliveries and by use. To correct a count, use the web app.',
                            style: AppType.helper.copyWith(color: c.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
