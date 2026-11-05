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
import '../../projects/data/project_models.dart';
import '../../projects/presentation/project_picker.dart';
import '../application/materials_providers.dart';
import '../data/material_models.dart';
import '../data/material_purchase_models.dart';
import '../data/material_reference_models.dart';
import 'log_usage_screen.dart' show parseQuantity, validateQuantity;
import 'material_pickers.dart';

/// The price paid for one unit: required, above zero, two decimals.
String? validatePaidPrice(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter the price you paid for one unit';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v <= 0) return 'Enter more than zero';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

/// How much was bought: required, above zero, three decimals.
String? validateBoughtQuantity(String? raw) {
  if (parseQuantity(raw ?? '') == null) return 'Enter how much you bought';
  return validateQuantity(raw);
}

class _BoughtLine {
  _BoughtLine(this.material)
    : quantity = TextEditingController(),
      price = TextEditingController(
        text: material.unitCost > 0 ? material.unitCost.toStringAsFixed(2) : '',
      );

  final MaterialItem material;
  final TextEditingController quantity;
  final TextEditingController price;

  void dispose() {
    quantity.dispose();
    price.dispose();
  }

  PurchaseLineInput? toInput() {
    final q = parseQuantity(quantity.text);
    final p = double.tryParse(price.text.trim().replaceAll(',', '.'));
    if (q == null || p == null) return null;
    return PurchaseLineInput(materialId: material.id, quantity: q, unitCost: p);
  }
}

/// Records material bought straight from a supplier, with no purchase order
/// behind it: the stock goes up now, each material's price becomes what was
/// paid, and with a project the cost is recorded in its Materials budget. Needs
/// `materials.manage_inventory`. Never recorded twice: see
/// [MaterialManagement.recordPurchase].
class RecordPurchaseScreen extends ConsumerStatefulWidget {
  const RecordPurchaseScreen({super.key});

  @override
  ConsumerState<RecordPurchaseScreen> createState() =>
      _RecordPurchaseScreenState();
}

class _RecordPurchaseScreenState extends ConsumerState<RecordPurchaseScreen> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _notes = TextEditingController();
  final _lines = <_BoughtLine>[];
  Supplier? _supplier;
  ProjectSummary? _project;
  DateTime _date = _today();
  String? _supplierError;
  String? _linesError;
  bool _pickingProject = false;
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _number.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold(0.0, (s, l) {
    final i = l.toInput();
    return i == null ? s : s + i.quantity * i.unitCost;
  });

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 366)),
      lastDate: today,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickProject() async {
    if (_pickingProject) return;
    setState(() => _pickingProject = true);
    try {
      final picked = await chooseProject(
        context,
        ref,
        title: 'Charge to a project',
        selected: _project,
        clearLabel: 'No project',
      );
      if (picked != null && mounted) setState(() => _project = picked.value);
    } finally {
      if (mounted) setState(() => _pickingProject = false);
    }
  }

  Future<void> _addItem() async {
    final m = await chooseMaterial(context, allowCreate: true);
    if (m == null || !mounted) return;
    if (_lines.any((l) => l.material.id == m.id)) {
      Snack.show(
        context,
        '${m.name} is already on this purchase. Change its quantity instead.',
      );
      return;
    }
    setState(() {
      _lines.add(_BoughtLine(m));
      _linesError = null;
    });
  }

  void _remove(int index) {
    final removed = _lines.removeAt(index);
    // The field is still on screen for this frame; dispose it after it.
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving || _confirming) return;
    setState(() {
      _error = null;
      _supplierError = _supplier == null ? 'Choose the supplier' : null;
      _linesError = _lines.isEmpty ? 'Add what you bought' : null;
    });
    if (!_form.currentState!.validate() ||
        _supplier == null ||
        _lines.isEmpty) {
      return;
    }
    // The exact moment is what finds this purchase again if the answer is lost.
    final now = DateTime.now();
    final input = NewPurchaseInput(
      supplierId: _supplier!.id,
      projectId: _project?.id,
      purchaseNumber: _number.text,
      notes: _notes.text,
      purchasedAt: DateTime(
        _date.year,
        _date.month,
        _date.day,
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
      ),
      items: [for (final l in _lines) l.toInput()!],
    );
    final currency = ref.read(currencyProvider);
    final count = input.items.length;

    // Set before the sheet opens: a second activation in the same frame would
    // otherwise open a second confirmation.
    _confirming = true;
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Record this purchase?',
        message:
            '$count ${count == 1 ? 'item' : 'items'} from ${_supplier!.name} for ${Fmt.money(input.total, currency)}. '
            'The quantities are added to stock now, and each material\'s price becomes what you paid.'
            '${_project == null ? '' : ' The cost is recorded against ${_project!.name} under Materials.'}'
            ' There is no purchase order behind it.',
        confirmLabel: 'Record purchase',
      );
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;

    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(materialManagementProvider)
          .recordPurchase(input);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Snack.show(context, saved.note ?? 'Purchase recorded. Stock updated.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Record a purchase')),
      body: SafeArea(
        child: !perms.hasAny(Feature.materialsInventory)
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot record purchases.',
              )
            : _body(perms.hasAny(Feature.projects)),
      ),
    );
  }

  Widget _body(bool canPickProject) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    return PageBody(
      children: [
        Text(
          'Material bought straight from a supplier, with no order. For material that was ordered, record the delivery on its order instead.',
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
                value: _supplier?.name,
                placeholder: 'Choose the supplier',
                enabled: !_saving,
                onTap: () async {
                  final picked = await chooseSupplier(
                    context,
                    ref,
                    selectedId: _supplier?.id,
                    allowAdd: true,
                    title: 'Bought from',
                  );
                  if (picked?.value != null && mounted) {
                    setState(() {
                      _supplier = picked!.value;
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
                label: 'Date bought',
                icon: Icons.event_rounded,
                value: Fmt.day(_date),
                enabled: !_saving,
                onTap: _pickDate,
              ),
              if (canPickProject) ...[
                const SizedBox(height: Space.lg),
                PickerField(
                  label: 'Charge to a project (optional)',
                  icon: Icons.apartment_rounded,
                  value: _project?.label,
                  placeholder: 'No project',
                  enabled: !_saving,
                  onTap: _pickingProject ? null : _pickProject,
                ),
              ],
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Invoice or receipt number (optional)',
                controller: _number,
                enabled: !_saving,
                textCapitalization: TextCapitalization.characters,
              ),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xl),
                  child: Text(
                    'Add each material you bought, with how much and what you paid for one unit.',
                    style: AppType.body.copyWith(color: c.textMuted),
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
                              _lines[i].material.name,
                              style: AppType.bodyStrong.copyWith(color: c.text),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ${_lines[i].material.name}',
                            onPressed: _saving ? null : () => _remove(i),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              color: c.danger,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${Fmt.quantity(_lines[i].material.stockOnHand)} ${_lines[i].material.unit} in stock now',
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                      const SizedBox(height: Space.md),
                      AppTextField(
                        label: _lines[i].material.unit.isEmpty
                            ? 'How much did you buy?'
                            : 'How much did you buy? (${_lines[i].material.unit})',
                        controller: _lines[i].quantity,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: validateBoughtQuantity,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: Space.md),
                      AppTextField(
                        label: 'Price paid for one unit ($currency)',
                        controller: _lines[i].price,
                        enabled: !_saving,
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: validatePaidPrice,
                        onChanged: (_) => setState(() {}),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          'The material\'s price becomes this.',
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
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
              const SizedBox(height: Space.sm),
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
                    'Total paid',
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
                label: 'Record purchase',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: Space.sm),
              Text(
                'A receipt photo cannot be attached from the app yet.',
                textAlign: TextAlign.center,
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
