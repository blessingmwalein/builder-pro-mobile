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
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../../shared/components/status_badge.dart';
import '../application/purchasing_providers.dart';
import '../data/purchasing_models.dart';

/// Validation for "received now" on one item: blank means none arrived; it can
/// not exceed what is still outstanding (the server decides "received in full"
/// from the totals, so over-delivery on one item would hide a shortfall on
/// another).
String? validateReceived(String? raw, double outstanding, {String unit = ''}) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number';
  if (v < 0) return 'Cannot be negative';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 3) return 'Use at most 3 decimals';
  if (roundQty(v) > outstanding) {
    final u = unit.isEmpty ? '' : ' $unit';
    return 'Only ${Fmt.quantity(outstanding)}$u is still outstanding. Record any extra on the web app.';
  }
  return null;
}

String? validateDeliveryNotes(String? raw) {
  if ((raw ?? '').trim().length > 500) {
    return 'Keep the note under 500 characters';
  }
  return null;
}

/// Record what arrived against a purchase order. Adds to stock for items that
/// are linked to a material, so it confirms first and is never sent twice: see
/// [PurchasingActions.receiveDelivery].
class ReceiveDeliveryScreen extends ConsumerStatefulWidget {
  const ReceiveDeliveryScreen({super.key, required this.orderId});
  final String orderId;

  @override
  ConsumerState<ReceiveDeliveryScreen> createState() =>
      _ReceiveDeliveryScreenState();
}

class _ReceiveDeliveryScreenState extends ConsumerState<ReceiveDeliveryScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _received = <String, TextEditingController>{};
  late DateTime _date = _today();
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  TextEditingController _controllerFor(String key) =>
      _received.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    _notes.dispose();
    for (final c in _received.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(const Duration(days: 90)),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _fillAll(List<OutstandingLine> open) {
    setState(() {
      for (final l in open) {
        _controllerFor(l.key).text = Fmt.quantity(l.outstanding);
      }
    });
  }

  Map<String, double> _entered(List<OutstandingLine> open) => {
    for (final l in open)
      if ((double.tryParse(
                _controllerFor(l.key).text.trim().replaceAll(',', '.'),
              ) ??
              0) >
          0)
        l.key: roundQty(
          double.parse(_controllerFor(l.key).text.trim().replaceAll(',', '.')),
        ),
  };

  Future<void> _save(PurchaseOrderDetail d) async {
    if (_saving || _confirming) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final open = d.outstanding.where((l) => !l.isComplete).toList();
    final entered = _entered(open);
    if (entered.isEmpty) {
      setState(
        () => _error = const AppException(
          AppErrorKind.validation,
          'Enter how much of at least one item arrived.',
        ),
      );
      return;
    }
    // Set before the sheet opens: a second tap in the same frame would
    // otherwise open a second confirmation.
    _confirming = true;
    final bool ok;
    try {
      ok = await _confirm(open, entered);
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      final note = await ref
          .read(purchasingActionsProvider)
          .receiveDelivery(
            widget.orderId,
            date: _date,
            received: entered,
            notes: _notes.text,
          );
      if (!mounted) return;
      Snack.show(context, note ?? 'Delivery recorded.');
      context.pop();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirm(
    List<OutstandingLine> open,
    Map<String, double> entered,
  ) {
    final arrived = open.where((l) => entered.containsKey(l.key)).toList();
    final missing = open.where((l) => !entered.containsKey(l.key)).toList();
    final toStock = arrived.where((l) => l.materialId != null).length;
    String qty(OutstandingLine l) =>
        '${l.description} ${Fmt.quantity(entered[l.key]!)}${l.unit.isEmpty ? '' : ' ${l.unit}'}';
    return confirmAction(
      context,
      title: 'Record this delivery?',
      message: [
        'Received: ${arrived.map(qty).join(', ')}.',
        if (missing.isNotEmpty)
          'Nothing received yet of: ${missing.map((l) => l.description).join(', ')}.',
        if (toStock > 0)
          'Stock goes up for $toStock ${toStock == 1 ? 'item' : 'items'} linked to a material.',
        'A delivery cannot be changed or removed from this app.',
      ].join(' '),
      confirmLabel: 'Record delivery',
    );
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    final allowed = perms.hasAny(Feature.purchasingManage);
    final detail = ref.watch(purchaseOrderDetailProvider(widget.orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value == null
              ? 'Record a delivery'
              : 'Delivery for ${detail.value!.summary.number}',
        ),
      ),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot record deliveries.',
              )
            : detail.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 120),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(
                    purchaseOrderDetailProvider(widget.orderId),
                  ),
                ),
                data: (d) => (!d.isReceivable || !d.hasOutstanding) && !_saving
                    ? EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: 'Not waiting for a delivery',
                        message: d.isReceivable
                            ? 'Everything ordered is already recorded as received.'
                            : 'This order is ${statusInfo(d.summary.status).label.toLowerCase()}.',
                      )
                    : _formBody(d),
              ),
      ),
    );
  }

  Widget _formBody(PurchaseOrderDetail d) {
    final c = context.colors;
    final lines = d.outstanding;
    final open = lines.where((l) => !l.isComplete).toList();
    final done = lines.where((l) => l.isComplete).toList();
    return PageBody(
      children: [
        Text(
          d.summary.supplierName,
          style: AppType.pageTitle.copyWith(color: c.text),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(d.summary.status),
            Text(
              d.summary.number,
              style: AppType.label.copyWith(color: c.textMuted),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickerField(
                label: 'Delivery date',
                icon: Icons.event_rounded,
                value: Fmt.day(_date),
                onTap: _saving ? null : _pickDate,
              ),
              const SizedBox(height: Space.lg),
              AppButton(
                label: 'Everything outstanding arrived',
                variant: AppButtonVariant.secondary,
                onPressed: _saving ? null : () => _fillAll(open),
              ),
              for (final l in open) ...[
                SectionHeader(l.description.toUpperCase()),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ordered ${Fmt.quantity(l.ordered)} · received so far ${Fmt.quantity(l.received)} · outstanding ${Fmt.quantity(l.outstanding)}${l.unit.isEmpty ? '' : ' ${l.unit}'}',
                        style: AppType.helper.copyWith(color: c.textMuted),
                      ),
                      const SizedBox(height: Space.md),
                      AppTextField(
                        label: 'Received now',
                        controller: _controllerFor(l.key),
                        hint: '0',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: (v) =>
                            validateReceived(v, l.outstanding, unit: l.unit),
                      ),
                    ],
                  ),
                ),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                Text(
                  'Already received in full: ${done.map((l) => l.description).join(', ')}.',
                  style: AppType.helper.copyWith(color: c.textMuted),
                ),
              ],
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Notes (optional)',
                controller: _notes,
                hint: 'e.g. 2 bags damaged, rest in good order',
                minLines: 2,
                maxLines: 4,
                validator: validateDeliveryNotes,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Record delivery',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(d),
              ),
              const SizedBox(height: Space.md),
              Text(
                'Stock goes up for items linked to a material. A recorded delivery cannot be changed or removed from this app.',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
