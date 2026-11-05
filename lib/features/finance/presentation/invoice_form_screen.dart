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
import '../../clients/presentation/client_picker.dart';
import '../../projects/presentation/project_picker.dart';
import '../application/quote_invoice_actions.dart';
import '../application/finance_providers.dart';
import '../application/quote_actions.dart';
import '../data/document_input.dart';
import '../data/finance_models.dart';
import 'line_items_editor.dart';

/// A new invoice, saved as a draft; or, with [quoteId], an invoice made from an
/// approved quote (client, project, lines, notes and terms are copied and can be
/// changed). Nothing is sent to the client from here.
///
/// An invoice carries only its lines: the server keeps no tax or discount for it
/// (backend-gaps G53), so a quote's tax and discount do not come across. The
/// form says so, with the two totals side by side, and offers to add them as
/// lines. When the invoice is made from a quote the quote is marked as converted
/// AFTER the invoice exists (and only with the right to change quotes).
class InvoiceFormScreen extends ConsumerStatefulWidget {
  const InvoiceFormScreen({super.key, this.quoteId});
  final String? quoteId;

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final _form = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _terms = TextEditingController();
  final _retention = TextEditingController();
  final _lines = <LineDraft>[LineDraft()];

  String? _clientId;
  String? _clientName;
  String? _projectId;
  String? _projectName;
  String? _clientError;
  DateTime _issue = DateTime.now();
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  bool _prefilled = false;
  bool _taxLinesAdded = false;
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  @override
  void dispose() {
    for (final c in [_notes, _terms, _retention]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<DocLine> get _validLines => [for (final l in _lines) ?l.toLine()];

  /// Copies the quote into the form, once.
  void _prefill(QuoteDetail d) {
    _prefilled = true;
    _clientId = d.summary.clientId.isEmpty ? null : d.summary.clientId;
    _clientName = d.summary.clientName;
    _projectId = d.projectId;
    _projectName = d.projectId == null ? null : 'Same project as the quote';
    _notes.text = d.notes ?? '';
    _terms.text = d.paymentTerms ?? '';
    for (final l in _lines) {
      l.dispose();
    }
    _lines
      ..clear()
      ..addAll([
        for (final line in d.lines)
          LineDraft(
            description: line.description,
            quantity: Fmt.quantity(line.quantity),
            unitPrice: line.unitPrice.toStringAsFixed(2),
          ),
      ]);
    if (_lines.isEmpty) _lines.add(LineDraft());
  }

  /// "Discount" and "Tax" as lines, so the invoice totals what the quote did.
  void _addTaxAndDiscountLines(QuoteDetail d) {
    setState(() {
      if (d.discount > 0) {
        _lines.add(
          LineDraft(
            description: 'Discount',
            quantity: '1',
            unitPrice: (-d.discount).toStringAsFixed(2),
          ),
        );
      }
      if (d.tax > 0) {
        _lines.add(
          LineDraft(
            description: d.taxRate > 0
                ? 'Tax (${Fmt.quantity(d.taxRate)}%)'
                : 'Tax',
            quantity: '1',
            unitPrice: d.tax.toStringAsFixed(2),
          ),
        );
      }
      _taxLinesAdded = true;
    });
  }

  Future<void> _pickDate({required bool due}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: due ? _due : _issue,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (due) {
        _due = picked;
      } else {
        _issue = picked;
      }
    });
  }

  Future<void> _save(QuoteDetail? quote) async {
    if (_saving || _confirming) return;
    setState(() {
      _error = null;
      _clientError = _clientId == null ? 'Choose the client' : null;
    });
    if (!_form.currentState!.validate() || _clientId == null) return;
    if (_due.isBefore(DateTime(_issue.year, _issue.month, _issue.day))) {
      setState(
        () => _error = const AppException(
          AppErrorKind.validation,
          'The due date cannot be before the issue date.',
        ),
      );
      return;
    }
    final input = InvoiceInput(
      clientId: _clientId!,
      projectId: _projectId,
      quoteId: widget.quoteId,
      issueDate: _issue,
      dueDate: _due,
      retentionPct: parseAmountText(_retention.text),
      notes: _notes.text,
      paymentTerms: _terms.text,
      lines: _validLines,
    );
    if (input.total <= 0) {
      setState(
        () => _error = const AppException(
          AppErrorKind.validation,
          'The total must be more than zero. Check the prices.',
        ),
      );
      return;
    }

    final markConverted =
        quote != null &&
        quote.summary.status == QuoteStatus.approved &&
        ref.read(permissionsProvider).hasAny(Feature.quotesConvert);

    if (quote != null) {
      final currency = ref.read(currencyProvider);
      final differs = (quote.summary.total - input.total).abs() >= 0.01;
      // Set before the sheet opens: a second activation in the same frame would
      // otherwise open a second confirmation.
      _confirming = true;
      final bool ok;
      try {
        ok = await confirmAction(
          context,
          title: 'Create the invoice?',
          message:
              'A draft invoice for ${Fmt.money(input.total, currency)} is made for $_clientName from ${quote.summary.number}. '
              'Nothing is sent to the client. '
              '${markConverted ? 'The quote is then marked as converted.' : 'The quote stays as it is.'}'
              '${differs ? " The quote's total was ${Fmt.money(quote.summary.total, currency)}: an invoice carries no tax or discount, only its lines." : ''}',
          confirmLabel: 'Create invoice',
        );
      } finally {
        _confirming = false;
      }
      if (!ok || !mounted || _saving) return;
    }

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(quoteInvoiceActionsProvider)
          .createInvoice(
            input,
            convertQuoteId: markConverted ? widget.quoteId : null,
          );
      if (!mounted) return;
      Snack.show(
        context,
        result.note ?? 'Invoice saved as a draft. Review it, then send it.',
      );
      context.pushReplacement('/invoices/${result.document.id}');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref
        .watch(permissionsProvider)
        .hasAny(Feature.invoicesCreate);
    final quoteId = widget.quoteId;
    final quote = quoteId == null
        ? null
        : ref.watch(quoteDetailProvider(quoteId));
    return Scaffold(
      appBar: AppBar(
        title: Text(quoteId == null ? 'New invoice' : 'Invoice from quote'),
      ),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot create invoices.',
              )
            : quote == null
            ? _formFor(null)
            : quote.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 110),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () => ref.invalidate(quoteDetailProvider(quoteId!)),
                ),
                data: (d) {
                  final status = d.summary.status;
                  if (status != QuoteStatus.approved &&
                      status != QuoteStatus.converted) {
                    return const EmptyState(
                      icon: Icons.description_outlined,
                      title: 'Not ready to invoice',
                      message: 'Only an approved quote can be turned into an invoice.',
                    );
                  }
                  if (!_prefilled && !_saving) _prefill(d);
                  return _formFor(d);
                },
              ),
      ),
    );
  }

  Widget _formFor(QuoteDetail? quote) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final total = invoiceTotal(_validLines);
    final hasExtras = quote != null && (quote.tax > 0 || quote.discount > 0);
    return PageBody(
      children: [
        if (quote != null) ...[
          Text(
            'From ${quote.summary.number} · ${quote.summary.title}',
            style: AppType.bodyStrong.copyWith(color: c.text),
          ),
          const SizedBox(height: Space.xs),
          Text(
            'The lines, client, notes and terms are copied from the quote. You can change anything before saving.',
            style: AppType.helper.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.lg),
        ],
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PickerField(
                label: 'Client',
                icon: Icons.person_outline_rounded,
                value: _clientName,
                placeholder: 'Choose the client',
                enabled: !_saving,
                onTap: () async {
                  final picked = await chooseClient(
                    context,
                    title: 'Choose the client',
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _clientId = picked.id;
                      _clientName = picked.name;
                      _clientError = null;
                    });
                  }
                },
              ),
              if (_clientError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    _clientError!,
                    style: AppType.helper.copyWith(color: c.danger),
                  ),
                ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Project (optional)',
                icon: Icons.apartment_rounded,
                value: _projectName,
                placeholder: 'Not linked to a project',
                enabled: !_saving,
                onTap: () async {
                  final picked = await chooseProject(
                    context,
                    ref,
                    title: 'Choose a project',
                    clearLabel: 'Not linked to a project',
                  );
                  if (picked != null && mounted) {
                    setState(() {
                      _projectId = picked.value?.id;
                      _projectName = picked.value?.name;
                    });
                  }
                },
              ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Issue date',
                icon: Icons.event_rounded,
                value: Fmt.day(_issue),
                enabled: !_saving,
                onTap: () => _pickDate(due: false),
              ),
              const SizedBox(height: Space.lg),
              PickerField(
                label: 'Due date',
                icon: Icons.event_available_outlined,
                value: Fmt.day(_due),
                enabled: !_saving,
                onTap: () => _pickDate(due: true),
              ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Retention (%, optional)',
                controller: _retention,
                enabled: !_saving,
                hint: '0',
                helper: 'The share held back until the work is signed off.',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: validatePercent,
              ),
              LineItemsEditor(
                lines: _lines,
                currency: currency,
                allowNegativePrice: true,
                enabled: !_saving,
                onAdd: () => setState(() => _lines.add(LineDraft())),
                onRemove: (i) => setState(() => _lines.removeAt(i).dispose()),
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: Space.lg),
              if (hasExtras && !_taxLinesAdded)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.lg),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          "The quote's total was ${Fmt.money(quote.summary.total, currency)}, including ${[if (quote.discount > 0) 'a discount of ${Fmt.money(quote.discount, currency)}', if (quote.tax > 0) 'tax of ${Fmt.money(quote.tax, currency)}'].join(' and ')}.",
                          style: AppType.bodySmall.copyWith(color: c.text),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'An invoice carries only its lines, so as it stands this invoice totals ${Fmt.money(total, currency)}. Add them as lines to match the quote.',
                          style: AppType.helper.copyWith(color: c.textMuted),
                        ),
                        const SizedBox(height: Space.md),
                        AppButton(
                          label: 'Add tax and discount as lines',
                          variant: AppButtonVariant.secondary,
                          onPressed: _saving
                              ? null
                              : () => _addTaxAndDiscountLines(quote),
                        ),
                      ],
                    ),
                  ),
                ),
              AppCard(
                child: AdaptiveRow(
                  start: Text(
                    'Total',
                    style: AppType.bodyStrong.copyWith(color: c.text),
                  ),
                  end: Text(
                    Fmt.money(total, currency),
                    style: AppType.amount.copyWith(color: c.text),
                  ),
                ),
              ),
              const SectionHeader('NOTES'),
              AppTextField(
                label: 'Notes (optional)',
                controller: _notes,
                enabled: !_saving,
                minLines: 2,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: Space.md),
              AppTextField(
                label: 'Payment terms (optional)',
                controller: _terms,
                enabled: !_saving,
                hint: 'e.g. Net 30',
                minLines: 1,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.lg),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xxl),
              AppButton(
                label: 'Save invoice',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(quote),
              ),
              const SizedBox(height: Space.md),
              Text(
                'The invoice is saved as a draft. Nothing is sent to the client until you choose "Send to client" on its page.',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
