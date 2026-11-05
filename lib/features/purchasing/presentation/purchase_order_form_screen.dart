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
import '../../materials/presentation/log_usage_screen.dart'
    show parseQuantity, validateQuantity;
import '../../materials/presentation/material_pickers.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';

/// The price of one unit on an order: required, above zero, two decimals.
String? validateOrderPrice(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter the price of one unit';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v <= 0) return 'Enter more than zero';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

/// The quantity of one item on an order: required, above zero, three decimals.
String? validateOrderQuantity(String? raw) {
  final v = parseQuantity(raw ?? '');
  if (v == null) return 'Enter the quantity';
  return validateQuantity(raw);
}

class _LineDraft {
  _LineDraft(PrItem item)
    : description = item.description,
      materialId = item.materialId,
      unit = item.unit,
      quantity = TextEditingController(text: Fmt.quantity(item.quantity)),
      price = TextEditingController(
        text: item.estimatedUnitCost == null
            ? ''
            : item.estimatedUnitCost!.toStringAsFixed(2),
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

/// Turns an approved purchase request into a purchase order: choose the supplier
/// and the prices (each line starts from the request's estimate). The order is a
/// draft; nothing is sent to the supplier, and when goods arrive the delivery
/// adds to the stock of each catalog material on it. Never created twice: see
/// [PurchasingActions.createOrder].
class NewPurchaseOrderScreen extends ConsumerStatefulWidget {
  const NewPurchaseOrderScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<NewPurchaseOrderScreen> createState() =>
      _NewPurchaseOrderScreenState();
}

class _NewPurchaseOrderScreenState
    extends ConsumerState<NewPurchaseOrderScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _lines = <_LineDraft>[];
  String? _supplierId;
  String? _supplierName;
  String? _supplierError;
  DateTime? _expected;
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expected ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _expected = picked);
  }

  Future<void> _save(PurchaseRequestDetail request) async {
    if (_saving || _confirming) return;
    setState(() {
      _error = null;
      _supplierError = _supplierId == null ? 'Choose the supplier' : null;
    });
    if (!_form.currentState!.validate() || _supplierId == null) return;
    final items = [for (final l in _lines) l.toItem()!];
    final input = NewOrderInput(
      requestId: widget.requestId,
      supplierId: _supplierId!,
      items: items,
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
        title: 'Create the purchase order?',
        message:
            'A draft order for ${Fmt.money(input.total, currency)} to $_supplierName is made from ${request.summary.number}, and the request becomes Ordered. '
            'Nothing is sent to the supplier yet. When the goods arrive, record the delivery to add them to stock.',
        confirmLabel: 'Create order',
      );
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(purchasingActionsProvider)
          .createOrder(input);
      if (!mounted) return;
      Snack.show(context, result.note ?? 'Purchase order created as a draft.');
      context.pushReplacement('/purchasing/orders/${result.orderId}');
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
    final detail = ref.watch(purchaseRequestDetailProvider(widget.requestId));
    return Scaffold(
      appBar: AppBar(title: const Text('New purchase order')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot create purchase orders.',
              )
            : detail.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 110),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(
                    purchaseRequestDetailProvider(widget.requestId),
                  ),
                ),
                data: (d) {
                  if (d.summary.status != PrStatus.approved && !_saving) {
                    return const EmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'Not ready to order',
                      message: 'Only an approved request can be turned into an order.',
                    );
                  }
                  if (!_prefilled && !_saving) {
                    _prefilled = true;
                    _lines.addAll([for (final i in d.items) _LineDraft(i)]);
                  }
                  return _body(d);
                },
              ),
      ),
    );
  }

  Widget _body(PurchaseRequestDetail d) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final canAddSupplier = ref
        .watch(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    return PageBody(
      children: [
        Text(
          'From ${d.summary.number}',
          style: AppType.bodyStrong.copyWith(color: c.text),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Each line starts from the request. Set the real price and quantity.',
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
                      Text(
                        _lines[i].description,
                        style: AppType.bodyStrong.copyWith(color: c.text),
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
              ],
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
                label: 'Create purchase order',
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
