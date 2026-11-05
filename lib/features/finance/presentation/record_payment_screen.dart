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
import '../../../shared/components/status_badge.dart';
import '../application/finance_providers.dart';
import '../application/payment_actions.dart';
import '../data/finance_models.dart';
import 'finance_widgets.dart';

/// Validation for the amount received: a positive amount, at most two
/// decimals, and no more than what is still owed.
String? validatePaymentAmount(String? raw, double balance) {
  final text = (raw ?? '').trim().replaceAll(',', '.');
  if (text.isEmpty) return 'Enter the amount received';
  final v = double.tryParse(text);
  if (v == null || !v.isFinite) return 'Enter an amount';
  if (v <= 0) return 'Enter more than zero';
  final dot = text.indexOf('.');
  if (dot >= 0 && text.length - dot - 1 > 2) return 'Use at most 2 decimals';
  if (roundMoney(v) > roundMoney(balance)) {
    return 'That is more than the balance due. Record the amount actually received.';
  }
  return null;
}

/// Record money received against an invoice, by cash or bank transfer.
/// Payments through PayNow or EcoCash start a payment with the customer's
/// phone on the server, so they stay on the web app. A recorded payment is never
/// sent twice: see [PaymentActions.record].
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _method;
  String? _methodError;
  bool _saving = false;
  bool _confirming = false;
  AppException? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(InvoiceDetail d) async {
    if (_saving || _confirming) return;
    setState(() => _error = null);
    final methodError = _method == null ? 'Choose how it was paid' : null;
    setState(() => _methodError = methodError);
    if (!_form.currentState!.validate() || methodError != null) return;
    final amount = roundMoney(
      double.parse(_amount.text.trim().replaceAll(',', '.')),
    );
    final currency = ref.read(currencyProvider);
    final after = roundMoney(d.summary.balance - amount);

    // Set before the sheet opens: a second activation in the same frame would
    // otherwise open a second confirmation.
    _confirming = true;
    final bool ok;
    try {
      ok = await confirmAction(
        context,
        title: 'Record this payment?',
        message:
            '${Fmt.money(amount, currency)} by ${ManualPayment.label(_method!).toLowerCase()} on ${d.summary.number} from ${d.summary.clientName}. '
            '${after <= 0 ? 'This pays the invoice in full.' : 'The balance due becomes ${Fmt.money(after, currency)}.'} '
            'A recorded payment cannot be changed or removed from this app.',
        confirmLabel: 'Record payment',
      );
    } finally {
      _confirming = false;
    }
    if (!ok || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      final note = await ref
          .read(paymentActionsProvider)
          .record(widget.invoiceId, method: _method!, amount: amount);
      if (!mounted) return;
      Snack.show(context, note ?? 'Payment recorded.');
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
    final allowed = perms.hasAny(Feature.invoicesRecordPayment);
    final detail = ref.watch(invoiceDetailProvider(widget.invoiceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value == null
              ? 'Record a payment'
              : 'Payment for ${detail.value!.summary.number}',
        ),
      ),
      body: SafeArea(
        child: !allowed
            ? const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Not allowed',
                message: 'Your role cannot record payments.',
              )
            : detail.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(Space.gutter),
                  child: SkeletonList(rows: 3, rowHeight: 100),
                ),
                error: (e, _) => ErrorPanel(
                  error: e,
                  onRetry: () =>
                      ref.invalidate(invoiceDetailProvider(widget.invoiceId)),
                ),
                data: (d) => !d.summary.isOpenForPayment && !_saving
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Not open for payments',
                        message: d.summary.balance <= 0
                            ? 'Nothing is owed on this invoice.'
                            : 'This invoice is ${statusInfo(d.summary.status).label.toLowerCase()}.',
                      )
                    : _body(d),
              ),
      ),
    );
  }

  Widget _body(InvoiceDetail d) {
    final c = context.colors;
    final currency = ref.watch(currencyProvider);
    final i = d.summary;
    return PageBody(
      children: [
        Text(i.clientName, style: AppType.pageTitle.copyWith(color: c.text)),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge.status(i.status),
            Text(i.number, style: AppType.label.copyWith(color: c.textMuted)),
          ],
        ),
        const SizedBox(height: Space.lg),
        AppCard(
          child: Column(
            children: [
              AmountRow('Total', i.total, currency: currency),
              AmountRow('Paid so far', i.paid, currency: currency),
              Divider(color: c.border),
              AmountRow(
                'Balance due',
                i.balance,
                currency: currency,
                strong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'How was it paid?',
                style: AppType.label.copyWith(color: c.text),
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final m in ManualPayment.all)
                    ChoiceChip(
                      label: Text(ManualPayment.label(m)),
                      selected: _method == m,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() {
                              _method = m;
                              _methodError = null;
                            }),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                ],
              ),
              if (_methodError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    _methodError!,
                    style: AppType.helper.copyWith(color: c.danger),
                  ),
                ),
              const SizedBox(height: Space.lg),
              AppTextField(
                label: 'Amount received',
                controller: _amount,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) => validatePaymentAmount(v, i.balance),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(
                          () => _amount.text = i.balance.toStringAsFixed(2),
                        ),
                  child: const Text('The full balance'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.md),
                ErrorPanel(error: _error!, compact: true),
              ],
              const SizedBox(height: Space.xl),
              AppButton(
                label: 'Record payment',
                icon: Icons.check_rounded,
                loading: _saving,
                onPressed: () => _save(d),
              ),
              const SizedBox(height: Space.md),
              Text(
                'Cash and bank transfers only. PayNow and EcoCash payments are started from the web app. A recorded payment cannot be changed or removed from this app.',
                style: AppType.helper.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
