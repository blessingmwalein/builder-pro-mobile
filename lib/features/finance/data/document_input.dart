import 'package:flutter/foundation.dart';

import '../../../core/utils/format.dart';
import 'finance_models.dart';

/// The line categories a quote offers (the same presets as the web app).
const quoteCategories = [
  'Labour',
  'Materials',
  'Equipment',
  'Subcontractors',
  'Overheads',
  'Margin',
  'Transport',
  'Permits',
  'Miscellaneous',
];

/// The most a price, a discount or a retention figure may be: far above any real
/// document and below what the server's columns hold.
const maxDocAmount = 999999999.99;

/// One line of a quote or invoice, as typed.
@immutable
class DocLine {
  const DocLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.category,
  });

  final String description;
  final double quantity;
  final double unitPrice;

  /// Quotes only.
  final String? category;

  double get total => roundMoney(quantity * unitPrice);

  Map<String, dynamic> toJson({required bool withCategory}) => {
    if (withCategory) 'category': category ?? quoteCategories.first,
    'description': description.trim(),
    'quantity': quantity,
    'unitPrice': unitPrice,
  };
}

/// A quote's figures the way the server works them out: the discount comes off
/// first, then the tax is taken from what is left. An invoice carries neither.
@immutable
class DocTotals {
  const DocTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
  });

  final double subtotal;
  final double discount;
  final double tax;
  final double total;
}

DocTotals quoteTotals(
  List<DocLine> lines, {
  double taxRate = 0,
  double discount = 0,
}) {
  final subtotal = roundMoney(lines.fold<double>(0, (s, l) => s + l.total));
  final discounted = (subtotal - discount) < 0 ? 0.0 : subtotal - discount;
  final tax = roundMoney(discounted * (taxRate / 100));
  return DocTotals(
    subtotal: subtotal,
    discount: roundMoney(subtotal - discounted),
    tax: tax,
    total: roundMoney(discounted + tax),
  );
}

/// Lines added up (an invoice has no tax or discount of its own).
double invoiceTotal(List<DocLine> lines) =>
    roundMoney(lines.fold<double>(0, (s, l) => s + l.total));

/// What the person typed for a new quote.
@immutable
class QuoteInput {
  const QuoteInput({
    required this.clientId,
    required this.title,
    required this.issueDate,
    required this.lines,
    this.projectId,
    this.expiryDate,
    this.taxRate,
    this.discountAmount,
    this.notes,
    this.paymentTerms,
  });

  final String clientId;
  final String? projectId;
  final String title;
  final DateTime issueDate;
  final DateTime? expiryDate;
  final double? taxRate;
  final double? discountAmount;
  final String? notes;
  final String? paymentTerms;
  final List<DocLine> lines;

  /// What the server will work out for this quote.
  DocTotals get totals =>
      quoteTotals(lines, taxRate: taxRate ?? 0, discount: discountAmount ?? 0);

  Map<String, dynamic> toBody() => {
    'clientId': clientId,
    'projectId': ?projectId,
    'title': title.trim(),
    'issueDate': Fmt.isoDay(issueDate),
    if (expiryDate != null) 'expiryDate': Fmt.isoDay(expiryDate!),
    'taxRate': ?taxRate,
    'discountAmount': ?discountAmount,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    if (paymentTerms != null && paymentTerms!.trim().isNotEmpty)
      'paymentTerms': paymentTerms!.trim(),
    'lineItems': [for (final l in lines) l.toJson(withCategory: true)],
  };
}

/// What the person typed for a new invoice.
@immutable
class InvoiceInput {
  const InvoiceInput({
    required this.clientId,
    required this.issueDate,
    required this.dueDate,
    required this.lines,
    this.projectId,
    this.quoteId,
    this.retentionPct,
    this.notes,
    this.paymentTerms,
  });

  final String clientId;
  final String? projectId;

  /// The approved quote this invoice is made from, if any.
  final String? quoteId;
  final DateTime issueDate;
  final DateTime dueDate;
  final double? retentionPct;
  final String? notes;
  final String? paymentTerms;
  final List<DocLine> lines;

  double get total => invoiceTotal(lines);

  Map<String, dynamic> toBody() => {
    'clientId': clientId,
    'projectId': ?projectId,
    'quoteId': ?quoteId,
    'issueDate': Fmt.isoDay(issueDate),
    'dueDate': Fmt.isoDay(dueDate),
    'retentionPct': ?retentionPct,
    if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
    if (paymentTerms != null && paymentTerms!.trim().isNotEmpty)
      'paymentTerms': paymentTerms!.trim(),
    'lineItems': [for (final l in lines) l.toJson(withCategory: false)],
  };
}

/// An optional amount typed as text, or null when empty or not a number.
double? parseAmountText(String? raw) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return null;
  return v;
}
