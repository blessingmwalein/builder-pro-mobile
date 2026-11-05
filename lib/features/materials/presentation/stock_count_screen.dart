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
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../application/materials_providers.dart';
import '../data/material_models.dart';
import 'log_usage_screen.dart' show parseQuantity;

/// A counted quantity: required, not negative (zero is a real count), at most
/// three decimals.
String? validateCountedStock(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter how much you counted';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number';
  if (v < 0) return 'Cannot be negative';
  if (v > 100000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 3) return 'Use at most 3 decimals';
  return null;
}

/// Why the count differs: written down, because the server keeps it with the
/// correction.
String? validateCountReason(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Say why the stock is being corrected';
  if (t.length < 3) return 'Give a little more detail';
  if (t.length > 300) return 'Keep it under 300 characters';
  return null;
}

/// "12 fewer" / "12 more" / "no change" for a count against what is recorded.
String describeStockDifference(double counted, double recorded, String unit) {
  final diff = ((counted - recorded) * 1000).round() / 1000;
  if (diff == 0) return 'no change';
  final amount = '${Fmt.quantity(diff.abs())}${unit.isEmpty ? '' : ' $unit'}';
  return diff < 0 ? '$amount fewer' : '$amount more';
}

/// Corrects what the app says is in stock after a physical count. Stock
/// otherwise moves only through deliveries, purchases and use, so this is the
/// one place a number is set by hand, and it needs a reason that the server
/// keeps. Needs `materials.manage_inventory`. See
/// [MaterialManagement.correctStock] for how a clash with a later movement and a
/// lost answer are handled.
class StockCountScreen extends ConsumerWidget {
  const StockCountScreen({super.key, required this.material});
  final MaterialItem material;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.materialsInventory);
    final fresh = ref.watch(materialDetailProvider(material.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Correct the stock count')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot correct stock.',
              )
            : fresh.when(
                // Keep the form (and what was typed) while the figure is read
                // again after a clash with a later movement.
                skipLoadingOnReload: true,
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 2, rowHeight: 110),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(materialDetailProvider(material.id)),
                ),
                data: (m) => _CountForm(material: m),
              ),
      ),
    );
  }
}

class _CountForm extends ConsumerStatefulWidget {
  const _CountForm({required this.material});

  /// The material as the server has it now. The correction is refused if its
  /// stock has moved from this figure by the time it is sent.
  final MaterialItem material;

  @override
  ConsumerState<_CountForm> createState() => _CountFormState();
}

class _CountFormState extends ConsumerState<_CountForm> {
  final _form = GlobalKey<FormState>();
  final _counted = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _confirming) return;
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    final m = widget.material;
    final counted = parseQuantity(_counted.text)!;
    final diff = describeStockDifference(counted, m.stockOnHand, m.unit);
    if (diff == 'no change') {
      setState(
        () => _error = const AppException(
          AppErrorKind.validation,
          'That is the same as the stock on record, so there is nothing to correct.',
        ),
      );
      return;
    }

    // Set before the sheet opens: a second activation in the same frame would
    // otherwise open a second confirmation.
    _confirming = true;
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Correct the stock?',
        message:
            'The stock of ${m.name} changes from ${Fmt.quantity(m.stockOnHand)} to ${Fmt.quantity(counted)} ${m.unit} ($diff). '
            'It is saved as a correction with your reason, and is not charged to any project.',
        confirmLabel: 'Correct stock',
      );
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;

    setState(() => _saving = true);
    try {
      final note = await ref
          .read(materialManagementProvider)
          .correctStock(m, counted, _reason.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      Snack.show(
        context,
        note ?? 'Stock corrected to ${Fmt.quantity(counted)} ${m.unit}.',
      );
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
    final m = widget.material;
    final counted = double.tryParse(_counted.text.trim().replaceAll(',', '.'));
    return PageBody(
      children: [
        AppCard(
          child: Row(
            children: [
              const IconTile(Icons.inventory_2_outlined),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: AppType.bodyStrong.copyWith(color: c.text),
                    ),
                    Text(
                      'On record: ${Fmt.quantity(m.stockOnHand)} ${m.unit}',
                      style: AppType.bodySmall.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        Text(
          'Count what is really there and enter it. Stock normally moves only when a delivery is recorded, a purchase is recorded or material is used. Use this when the count disagrees.',
          style: AppType.helper.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'How much is there?',
                controller: _counted,
                enabled: !_saving,
                suffixText: m.unit,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: validateCountedStock,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.next,
              ),
              if (counted != null && counted >= 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    'Against ${Fmt.quantity(m.stockOnHand)} on record: ${describeStockDifference(counted, m.stockOnHand, m.unit)}.',
                    style: AppType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Why is it being corrected?',
                controller: _reason,
                enabled: !_saving,
                hint: 'e.g. Counted on site, 3 bags damaged',
                minLines: 2,
                maxLines: 4,
                validator: validateCountReason,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Correct stock',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
