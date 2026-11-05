import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/utils/format.dart';
import '../../../shared/components/app_button.dart';
import '../../../shared/components/app_text_field.dart';
import '../../../shared/components/layout.dart';
import '../../../shared/components/pickers.dart';
import '../data/document_input.dart';

/// One line of a quote or invoice while it is being typed.
class LineDraft {
  LineDraft({
    String description = '',
    String quantity = '1',
    String unitPrice = '',
    this.category = 'Labour',
  }) : description = TextEditingController(text: description),
       quantity = TextEditingController(text: quantity),
       unitPrice = TextEditingController(text: unitPrice);

  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  String category;

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }

  /// The line as typed, or null while it is not a usable number yet.
  DocLine? toLine() {
    final q = parseAmountText(quantity.text);
    final p = parseAmountText(unitPrice.text);
    if (q == null || p == null) return null;
    return DocLine(
      description: description.text,
      quantity: q,
      unitPrice: p,
      category: category,
    );
  }
}

String? validateLineDescription(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Say what this line is for';
  if (t.length > 300) return 'Keep it under 300 characters';
  return null;
}

String? validateLineQuantity(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter a quantity';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number';
  if (v <= 0) return 'Enter more than zero';
  if (v > 1000000) return 'That is too large. Check the number';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 3) return 'Use at most 3 decimals';
  return null;
}

/// A price: not zero, at most two decimals, not absurdly large. A negative
/// price is a credit, allowed only when [allowNegative] (invoices).
String? validateLineUnitPrice(String? raw, {bool allowNegative = false}) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter a price';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v == 0) return 'Enter more than zero';
  if (v < 0 && !allowNegative) return 'Enter a price above zero';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  if (v.abs() > maxDocAmount) return 'That is too large';
  return null;
}

/// An optional percentage between 0 and 100 with at most two decimals.
String? validatePercent(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter a number';
  if (v < 0 || v > 100) return 'Use a number from 0 to 100';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  return null;
}

/// An optional amount: not negative, at most two decimals, not absurdly large.
String? validateOptionalAmount(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v < 0) return 'Cannot be negative';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  if (v > maxDocAmount) return 'That is too large';
  return null;
}

/// The lines of a quote or invoice: add, remove, and type each one. The parent
/// owns the [lines] and is told (with [onChanged]) whenever a value changes so it
/// can redraw its totals.
class LineItemsEditor extends StatelessWidget {
  const LineItemsEditor({
    super.key,
    required this.lines,
    required this.currency,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    this.withCategory = false,
    this.allowNegativePrice = false,
    this.enabled = true,
  });

  final List<LineDraft> lines;
  final String currency;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onChanged;

  /// Quotes only: each line is filed under Labour, Materials…
  final bool withCategory;
  final bool allowNegativePrice;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          SectionHeader(
            'LINE ${i + 1}',
            trailing: lines.length > 1
                ? TextButton(
                    onPressed: enabled ? () => onRemove(i) : null,
                    child: const Text('Remove'),
                  )
                : null,
          ),
          AppCard(
            key: ObjectKey(lines[i]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (withCategory) ...[
                  PickerField(
                    label: 'Category',
                    icon: Icons.category_outlined,
                    value: lines[i].category,
                    enabled: enabled,
                    onTap: () async {
                      final picked = await pickOne<String>(
                        context,
                        title: 'Category',
                        selected: lines[i].category,
                        options: [
                          for (final cat in quoteCategories)
                            PickerOption(value: cat, title: cat),
                        ],
                      );
                      if (picked?.value != null) {
                        lines[i].category = picked!.value!;
                        onChanged();
                      }
                    },
                  ),
                  const SizedBox(height: Space.md),
                ],
                AppTextField(
                  label: 'Description',
                  controller: lines[i].description,
                  enabled: enabled,
                  hint: 'What is this line for?',
                  validator: validateLineDescription,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: Space.md),
                AppTextField(
                  label: 'Quantity',
                  controller: lines[i].quantity,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  validator: validateLineQuantity,
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: Space.md),
                AppTextField(
                  label: 'Price each ($currency)',
                  controller: lines[i].unitPrice,
                  enabled: enabled,
                  hint: '0.00',
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                    signed: allowNegativePrice,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(allowNegativePrice ? r'[0-9.,-]' : r'[0-9.,]'),
                    ),
                  ],
                  validator: (v) => validateLineUnitPrice(
                    v,
                    allowNegative: allowNegativePrice,
                  ),
                  onChanged: (_) => onChanged(),
                ),
                const SizedBox(height: Space.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Line total ${_lineTotal(lines[i], currency)}',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.md),
        AppButton(
          label: 'Add a line',
          icon: Icons.add_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: enabled ? onAdd : null,
        ),
      ],
    );
  }

  static String _lineTotal(LineDraft d, String currency) {
    final line = d.toLine();
    return line == null ? '—' : Fmt.money(line.total, currency);
  }
}
