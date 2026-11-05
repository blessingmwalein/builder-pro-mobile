import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/format.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import 'finance_providers.dart';

const _notOpenMessage =
    'This invoice is no longer open for payments. The page now shows its current state.';
const _changedMessage =
    'This invoice has changed since you opened it. The page now shows its current state.';

/// Recording a payment against an invoice.
///
/// A payment moves money records, the server has no way to tell a repeat from a
/// second payment (no idempotency key; a repeat would count the money twice),
/// and it checks neither the invoice's status nor the amount against the
/// balance. So the invoice is re-read first and the amount checked against the
/// balance as it is now, the payment is never resent, and after a timeout the
/// invoice is read back to look for a payment of its own.
class PaymentActions {
  PaymentActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded.
  Future<String?> record(
    String invoiceId, {
    required String method,
    required double amount,
  }) async {
    if (!ManualPayment.all.contains(method)) {
      throw const AppException(
        AppErrorKind.validation,
        'That payment method has to be recorded on the web app.',
      );
    }
    final money = roundMoney(amount);
    if (!money.isFinite || money <= 0 || money > 1000000000) {
      throw const AppException(
        AppErrorKind.validation,
        'Enter an amount greater than zero.',
      );
    }
    final startedAt = DateTime.now();
    final currency = _ref.read(currencyProvider);

    // Re-read: the balance and status come from the server as they are now.
    final before = await _repo.invoice(invoiceId);
    if (!before.summary.isOpenForPayment) {
      _refresh(invoiceId);
      throw const AppException(AppErrorKind.validation, _notOpenMessage);
    }
    if (money > roundMoney(before.summary.balance)) {
      _refresh(invoiceId);
      throw AppException(
        AppErrorKind.validation,
        'That is more than the balance due now (${Fmt.money(before.summary.balance, currency)}). A payment may have been recorded since you opened this. The page now shows the balance.',
      );
    }

    try {
      await _repo.recordPayment(invoiceId, method: method, amount: money);
      _refresh(invoiceId);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        InvoiceDetail? fresh;
        try {
          fresh = await _repo.invoice(invoiceId);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final known = before.payments.map((p) => p.id).toSet();
        final added = fresh.payments
            .where((p) => !known.contains(p.id))
            .toList();
        final since = startedAt.subtract(const Duration(minutes: 2));
        final mine = added.any(
          (p) =>
              p.method == method &&
              roundMoney(p.amount) == money &&
              p.status == PaymentRecord.success &&
              (p.paidAt ?? startedAt).isAfter(since),
        );
        if (mine) {
          _refresh(invoiceId);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (added.isEmpty) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and no payment was recorded. Please try again.",
          );
        }
        _refresh(invoiceId);
        throw const AppException(
          AppErrorKind.validation,
          'A different payment was recorded on this invoice while we were checking. Look at its payments before trying again.',
        );
      }
      if (e.kind == AppErrorKind.validation) {
        // Say the invoice moved on only when it did; any other 400 keeps the
        // server's own words.
        InvoiceDetail? fresh;
        try {
          fresh = await _repo.invoice(invoiceId);
        } on AppException {
          fresh = null;
        }
        if (fresh != null && !fresh.summary.isOpenForPayment) {
          _refresh(invoiceId);
          throw const AppException(AppErrorKind.validation, _changedMessage);
        }
      }
      rethrow;
    }
  }

  /// A payment changes the invoice, the receivables and the money collected.
  void _refresh(String invoiceId) {
    _ref.invalidate(invoiceDetailProvider(invoiceId));
    _ref.invalidate(invoicesCatalogProvider);
    _ref.invalidate(financeSummaryProvider);
    _ref.invalidate(moneyOverviewProvider);
    _ref.invalidate(collectionsLedgerProvider);
    _ref.invalidate(agingReportProvider);
  }
}

final paymentActionsProvider = Provider<PaymentActions>(
  (ref) => PaymentActions(ref),
);
