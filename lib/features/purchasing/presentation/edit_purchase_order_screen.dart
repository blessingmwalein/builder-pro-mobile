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
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/confirm_sheet.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../finance/application/finance_providers.dart' show currencyProvider;
import '../../materials/data/material_models.dart';
import '../../materials/presentation/log_usage_screen.dart' show parseQuantity;
import '../../materials/presentation/material_pickers.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';
import 'purchase_order_form_screen.dart'
    show validateOrderPrice, validateOrderQuantity;

class _EditLine {
  _EditLine({
    required this.description,
    required this.unit,
    required String quantity,
    required String price,
    this.materialId,
  }) : quantity = TextEditingController(text: quantity),
       price = TextEditingController(text: price);

  factory _EditLine.fromItem(PoItem i) => _EditLine(
    description: i.description,
    materialId: i.materialId,
    unit: i.unit,
    quantity: Fmt.quantity(i.quantity),
    price: i.unitCost.toStringAsFixed(2),
  );

  factory _EditLine.fromMaterial(MaterialItem m) => _EditLine(
    description: m.name,
    materialId: m.id,
    unit: m.unit,
    quantity: '',
    price: m.unitCost > 0 ? m.unitCost.toStringAsFixed(2) : '',
  );

  final String description;
  final String? materialId;
  final String unit;
  final TextEditingController quantity;
  final TextEditingController price;

  void dispose() {
    quantity.dispose();
    price.dispose();
  }

  NewPoItem? toItem() {
    final q = parseQuantity(quantity.text);
    final p = double.tryParse(price.text.trim().replaceAll(',', '.'));
    if (q == null || p == null) return null;
    return NewPoItem(
      description: description,
      materialId: materialId,
      quantity: q,
      unitCost: p,
    );
  }
}

/// Changes a draft purchase order: the supplier, the expected delivery, the
/// notes, and the items (their quantity and price, remove one, add a material).
/// Only a draft can be changed, because once it is sent the supplier has it.
/// Saving sets the order to exactly what is on screen, so it is safe to repeat;
/// see [PurchasingActions.updateOrder].
class EditPurchaseOrderScreen extends ConsumerStatefulWidget {
  const EditPurchaseOrderScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<EditPurchaseOrderScreen> createState() =>
      _EditPurchaseOrderScreenState();
}

class _EditPurchaseOrderScreenState
    extends ConsumerState<EditPurchaseOrderScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _lines = <_EditLine>[];
  String? _supplierId;
  String? _supplierName;
  String? _supplierError;
  DateTime? _expected;
  String? _linesError;
  bool _prefilled = false;
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold(0.0, (s, l) {
    final i = l.toItem();
    return i == null ? s : s + i.quantity * i.unitCost;
  });

  void _prefill(PurchaseOrderDetail d) {
    _prefilled = true;
    _supplierId = d.summary.supplierId;
    _supplierName = d.summary.supplierName;
    _expected = d.summary.expectedDelivery;
    _notes.text = d.notes ?? '';
    _lines.addAll([for (final i in d.items) _EditLine.fromItem(i)]);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _expected?.toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today.add(const Duration(days: 7)),
      // The date already on the order may be in the past.
      firstDate: current != null && current.isBefore(today) ? current : today,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _expected = picked);
  }

  Future<void> _addItem() async {
    final canCreate = ref
        .read(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    final m = await chooseMaterial(context, allowCreate: canCreate);
    if (m == null || !mounted) return;
    if (_lines.any((l) => l.materialId == m.id)) {
      Snack.show(
        context,
        '${m.name} is already on this order. Change its quantity instead.',
      );
      return;
    }
    setState(() {
      _lines.add(_EditLine.fromMaterial(m));
      _linesError = null;
    });
  }

  void _remove(int index) {
    final removed = _lines.removeAt(index);
    // The field is still on screen for this frame; dispose it after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    setState(() {});
  }

  Future<void> _save(PurchaseOrderDetail order) async {
    if (_saving || _confirming) return;
    setState(() {
      _error = null;
      _supplierError = _supplierId == null ? 'Choose the supplier' : null;
      _linesError = _lines.isEmpty ? 'An order needs at least one item' : null;
    });
    if (!_form.currentState!.validate() ||
        _supplierId == null ||
        _lines.isEmpty) {
      return;
    }
    final input = EditOrderInput(
      supplierId: _supplierId!,
      items: [for (final l in _lines) l.toItem()!],
      expectedDelivery: _expected,
      notes: _notes.text,
    );
    final currency = ref.read(currencyProvider);

    // Set before the sheet opens: a second activation in the same frame would
    // otherwise open a second confirmation.
    _confirming = true;
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Save the changes?',
        message:
            '${order.summary.number} to $_supplierName is set to ${input.items.length} ${input.items.length == 1 ? 'item' : 'items'} totalling ${Fmt.money(input.total, currency)}. '
            'It stays a draft, and nothing is sent to the supplier.',
        confirmLabel: 'Save changes',
      );
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(purchasingActionsProvider)
          .updateOrder(widget.orderId, input);
      if (!mounted) return;
      Snack.show(context, 'Order updated.');
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    final allowed = perms.hasAny(Feature.purchasingManage);
    final detail = ref.watch(purchaseOrderDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit order')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot change purchase orders.',
              )
            : detail.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 110),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(
                    purchaseOrderDetailProvider(widget.orderId),
                  ),
                ),
                data: (d) {
                  if (!d.canEdit && !_saving) {
                    return const EmptyState(
                      icon: Icons.edit_off_outlined,
                      title: 'Cannot be changed',
                      message: 'Only a draft order can be changed. Once an order is sent, cancel it and make a new one.',
                    );
                  }
                  if (!_prefilled) _prefill(d);
                  return _body(d);
                },
              ),
      ),
    );
  }

  Widget _body(PurchaseOrderDetail d) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final canAddSupplier = ref
        .watch(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    return PageBody(
      children: [
        Text(
          d.summary.number,
          style: AppType.bodyStrong.copyWith(color: c.text),
        ),
        const SizedBox(height: Space.xs),
        Text(
          d.requestNumber == null
              ? 'Change what you need to, then save.'
              : 'From ${d.requestNumber}. Change what you need to, then save.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickerField(
                label: 'Supplier',
                icon: Icons.local_shipping_outlined,
                value: _supplierName,
                placeholder: 'Choose the supplier',
                enabled: !_saving,
                onTap: () async {
                  final picked = await chooseSupplier(
                    context,
                    ref,
                    selectedId: _supplierId,
                    allowAdd: canAddSupplier,
                    title: 'Choose the supplier',
                  );
                  if (picked?.value != null && mounted) {
                    setState(() {
                      _supplierId = picked!.value!.id;
                      _supplierName = picked.value!.name;
                      _supplierError = null;
                    });
                  }
                },
              ),
              if (_supplierError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    _supplierError!,
                    style: AppType.helper.copyWith(color: c.danger),
                  ),
                ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Expected delivery (optional)',
                icon: Icons.event_rounded,
                value: _expected == null ? null : Fmt.day(_expected!),
                placeholder: 'No date yet',
                enabled: !_saving,
                onTap: _pickDate,
              ),
              if (_expected != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _expected = null),
                    child: const Text('Remove the date'),
                  ),
                ),
              for (var i = 0; i < _lines.length; i++) ...[
                SectionHeader('ITEM ${i + 1}'),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              _lines[i].description,
                              style: AppType.bodyStrong.copyWith(color: c.text),
                            ),
                          ),
                          if (_lines.length > 1)
                            IconButton(
                              tooltip: 'Remove ${_lines[i].description}',
                              onPressed: _saving ? null : () => _remove(i),
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: c.danger,
                              ),
                            ),
                        ],
                      ),
                      if (_lines[i].materialId == null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            'Not linked to a catalog material, so a delivery will not change any stock level.',
                            style: AppType.helper.copyWith(color: c.warning),
                          ),
                        ),
                      const SizedBox(height: Space.md),
                      AppTextField(
                        label: _lines[i].unit.isEmpty
                            ? 'Quantity'
                            : 'Quantity (${_lines[i].unit})',
                        controller: _lines[i].quantity,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: validateOrderQuantity,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: Space.md),
                      AppTextField(
                        label: 'Price of one unit ($currency)',
                        controller: _lines[i].price,
                        enabled: !_saving,
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: validateOrderPrice,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.sm),
              ],
              if (_linesError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Text(
                    _linesError!,
                    style: AppType.helper.copyWith(color: c.danger),
                  ),
                ),
              AppButton(
                label: 'Add an item',
                icon: Icons.add_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: _saving ? null : _addItem,
              ),
              const SizedBox(height: Space.lg),
              AppCard(
                child: AdaptiveRow(
                  start: Text(
                    'Order total',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: Text(
                    Fmt.money(_total, currency),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Notes for the supplier (optional)',
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
                label: 'Save changes',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(d),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
