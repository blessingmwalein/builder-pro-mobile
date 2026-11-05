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
import '../../../shared/components/layout.dart';
import '../../../shared/components/list_widgets.dart';
import '../../../shared/components/pickers.dart';
import '../../../shared/components/snack.dart';
import '../../../shared/components/states.dart';
import '../../clients/presentation/client_picker.dart';
import '../../projects/presentation/project_picker.dart';
import '../application/quote_invoice_actions.dart';
import '../application/finance_providers.dart';
import '../data/document_input.dart';
import 'line_items_editor.dart';

String? validateQuoteTitle(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Give the quote a title';
  if (t.length > 200) return 'Keep the title under 200 characters';
  return null;
}

/// A new quote, saved as a draft. Nothing is sent to the client from here: the
/// quote's page has "Send to client". Never created twice: see
/// [QuoteInvoiceActions.createQuote].
class QuoteFormScreen extends ConsumerStatefulWidget {
  const QuoteFormScreen({super.key});

  @override
  ConsumerState<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends ConsumerState<QuoteFormScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  final _terms = TextEditingController();
  final _tax = TextEditingController();
  final _discount = TextEditingController();
  final _lines = <LineDraft>[LineDraft()];

  String? _clientId;
  String? _clientName;
  String? _projectId;
  String? _projectName;
  String? _clientError;
  DateTime _issue = DateTime.now();
  DateTime? _expiry;
  bool _saving = false;
  AppException? _error;

  @override
  void dispose() {
    for (final c in [_title, _notes, _terms, _tax, _discount]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<DocLine> get _validLines => [for (final l in _lines) ?l.toLine()];

  DocTotals get _totals => quoteTotals(
    _validLines,
    taxRate: parseAmountText(_tax.text) ?? 0,
    discount: parseAmountText(_discount.text) ?? 0,
  );

  Future<void> _pickDate({required bool expiry}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: expiry
          ? (_expiry ?? _issue.add(const Duration(days: 30)))
          : _issue,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (expiry) {
        _expiry = picked;
      } else {
        _issue = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _clientError = _clientId == null ? 'Choose the client' : null;
    });
    if (!_form.currentState!.validate() || _clientId == null) return;
    if (_expiry != null && _expiry!.isBefore(_issue)) {
      setState(
        () => _error = const AppException(
          AppErrorKind.validation,
          'The quote cannot expire before it is issued.',
        ),
      );
      return;
    }
    final input = QuoteInput(
      clientId: _clientId!,
      projectId: _projectId,
      title: _title.text,
      issueDate: _issue,
      expiryDate: _expiry,
      taxRate: parseAmountText(_tax.text),
      discountAmount: parseAmountText(_discount.text),
      notes: _notes.text,
      paymentTerms: _terms.text,
      lines: _validLines,
    );
    if (input.totals.total <= 0) {
      setState(
        () => _error = const AppException(
          AppErrorKind.validation,
          'The total must be more than zero. Check the prices and the discount.',
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await ref
          .read(quoteInvoiceActionsProvider)
          .createQuote(input);
      if (!mounted) return;
      Snack.show(
        context,
        result.note ?? 'Quote saved as a draft. Review it, then send it.',
      );
      context.pushReplacement('/quotes/${result.document.id}');
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final allowed = ref.watch(permissionsProvider).hasAny(Feature.quotesCreate);
    final currency = ref.watch(currencyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New quote')),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot create quotes.',
              )
            : PageBody(
                children: [
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
                        AppTextField(
                          label: 'Title',
                          controller: _title,
                          enabled: !_saving,
                          hint: 'e.g. Kitchen extension',
                          maxLength: 200,
                          validator: validateQuoteTitle,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Issue date',
                          icon: Icons.event_rounded,
                          value: Fmt.day(_issue),
                          enabled: !_saving,
                          onTap: () => _pickDate(expiry: false),
                        ),
                        const SizedBox(height: Space.lg),
                        PickerField(
                          label: 'Valid until (optional)',
                          icon: Icons.event_busy_outlined,
                          value: _expiry == null ? null : Fmt.day(_expiry!),
                          placeholder: 'No expiry date',
                          enabled: !_saving,
                          onTap: () => _pickDate(expiry: true),
                        ),
                        if (_expiry != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _expiry = null),
                              child: const Text('Remove the expiry date'),
                            ),
                          ),
                        LineItemsEditor(
                          lines: _lines,
                          currency: currency,
                          withCategory: true,
                          enabled: !_saving,
                          onAdd: () => setState(() => _lines.add(LineDraft())),
                          onRemove: (i) =>
                              setState(() => _lines.removeAt(i).dispose()),
                          onChanged: () => setState(() {}),
                        ),
                        const SectionHeader('TAX AND DISCOUNT'),
                        AppTextField(
                          label: 'Discount ($currency, optional)',
                          controller: _discount,
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
                          validator: validateOptionalAmount,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.md),
                        AppTextField(
                          label: 'Tax rate (%, optional)',
                          controller: _tax,
                          enabled: !_saving,
                          hint: '0',
                          helper:
                              'Worked out on what is left after the discount.',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          validator: validatePercent,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: Space.lg),
                        _TotalsCard(totals: _totals, currency: currency),
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
                          hint: 'e.g. 50% deposit, balance on completion',
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
                          label: 'Save quote',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
                        ),
                        const SizedBox(height: Space.md),
                        Text(
                          'The quote is saved as a draft. Nothing is sent to the client until you choose "Send to client" on its page.',
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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.currency});
  final DocTotals totals;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(String label, double v, {bool strong = false}) => AdaptiveRow(
      start: Text(
        label,
        style: (strong ? AppType.bodyStrong : AppType.body).copyWith(
          color: strong ? c.text : c.textMuted,
        ),
      ),
      end: Text(
        Fmt.money(v, currency),
        style: (strong ? AppType.amount : AppType.bodyStrong).copyWith(
          color: c.text,
        ),
      ),
    );
    return AppCard(
      child: Column(
        children: [
          row('Subtotal', totals.subtotal),
          if (totals.discount > 0) row('Discount', -totals.discount),
          if (totals.tax > 0) row('Tax', totals.tax),
          Divider(color: c.border),
          row('Total', totals.total, strong: true),
        ],
      ),
    );
  }
}
