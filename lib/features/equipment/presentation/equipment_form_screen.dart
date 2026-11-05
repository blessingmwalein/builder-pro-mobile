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
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/equipment_providers.dart';
import '../data/equipment_models.dart';

String? validateEquipmentName(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Enter a name';
  if (t.length > 120) return 'Keep the name under 120 characters';
  return null;
}

String? validateEquipmentText(String? raw, {int max = 300}) {
  if ((raw ?? '').trim().length > max) return 'Keep it under $max characters';
  return null;
}

/// Add a piece of equipment, or (with [equipmentId]) change its name, serial
/// number, notes and category. Costs and status are not set here. Never sent
/// twice: see [EquipmentActions.create].
class EquipmentFormScreen extends ConsumerStatefulWidget {
  const EquipmentFormScreen({super.key, this.equipmentId});
  final String? equipmentId;

  @override
  ConsumerState<EquipmentFormScreen> createState() =>
      _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends ConsumerState<EquipmentFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _serial = TextEditingController();
  final _description = TextEditingController();
  EquipmentCategory? _category;
  String? _categoryId;
  bool _loaded = false;
  bool _saving = false;
  AppException? _error;

  bool get _isEdit => widget.equipmentId != null;

  @override
  void dispose() {
    _name.dispose();
    _serial.dispose();
    _description.dispose();
    super.dispose();
  }

  /// Fills the form from the item being edited, once.
  void _prefill(EquipmentDetail d) {
    if (_loaded) return;
    _loaded = true;
    _name.text = d.summary.name;
    _serial.text = d.summary.serialNumber ?? '';
    _description.text = d.description ?? '';
    _categoryId = d.summary.categoryId;
  }

  Future<void> _pickCategory(List<EquipmentCategory> all) async {
    final picked = await pickOne<EquipmentCategory>(
      context,
      title: 'Choose a category',
      selected: all.where((c) => c.id == _categoryId).firstOrNull,
      clearLabel: 'No category',
      emptyMessage: 'No categories yet. Add them on the web app.',
      options: [for (final c in all) PickerOption(value: c, title: c.name)],
    );
    if (picked != null && mounted) {
      setState(() {
        _category = picked.value;
        _categoryId = picked.value?.id;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final actions = ref.read(equipmentActionsProvider);
      if (_isEdit) {
        await actions.updateDetails(
          widget.equipmentId!,
          name: _name.text,
          description: _description.text,
          serialNumber: _serial.text,
          categoryId: _categoryId,
        );
        if (!mounted) return;
        Snack.show(context, 'Equipment updated.');
      } else {
        final note = await actions.create(
          name: _name.text,
          description: _description.text,
          serialNumber: _serial.text,
          categoryId: _categoryId,
        );
        if (!mounted) return;
        Snack.show(context, note ?? 'Equipment added.');
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
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.equipmentManage);
    final categories = ref.watch(equipmentCategoriesProvider);
    final detail = _isEdit
        ? ref.watch(equipmentDetailProvider(widget.equipmentId!))
        : null;
    if (detail?.value != null) _prefill(detail!.value!);
    final categoryName =
        _category?.name ??
        categories.value?.where((x) => x.id == _categoryId).firstOrNull?.name;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit equipment' : 'Add equipment')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot add or change equipment.',
              )
            : (_isEdit && detail != null && detail.isLoading && !_loaded)
            ? const Padding(
                padding: EdgeInsets.all(Space.gutter),
                child: SkeletonList(rows: 3, rowHeight: 90),
              )
            : (_isEdit && detail != null && detail.hasError && !_loaded)
            ? ErrorPanel(
                error: detail.error!,
                onRetry: () => ref.invalidate(
                  equipmentDetailProvider(widget.equipmentId!),
                ),
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
                          hint: 'e.g. Excavator CAT 320',
                          validator: validateEquipmentName,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Serial number (optional)',
                          controller: _serial,
                          validator: (v) => validateEquipmentText(v, max: 60),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Category (optional)',
                          icon: Icons.category_outlined,
                          value: categoryName,
                          placeholder: 'No category',
                          onTap: categories.value == null || _saving
                              ? null
                              : () => _pickCategory(categories.value!),
                        ),
                        const SizedBox(height: Space.lg),
                        AppTextField(
                          label: 'Notes (optional)',
                          controller: _description,
                          hint: 'Anything people should know',
                          minLines: 2,
                          maxLines: 5,
                          validator: validateEquipmentText,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: Space.lg),
                          ErrorPanel(error: _error!, compact: true),
                        ],
                        const SizedBox(height: Space.xxl),
                        AppButton(
                          label: _isEdit ? 'Save changes' : 'Add equipment',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'Costs and purchase details are set on the web app.',
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
