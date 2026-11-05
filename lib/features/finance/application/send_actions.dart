import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import 'finance_providers.dart';

const _movedMessage =
    'This has already been sent or changed since you opened it. The page now shows its current state.';

/// Sending a draft invoice or quote to the client.
///
/// Sending sets SENT and (when asked) emails the client. A repeat answers 400
/// before any email goes out, so nothing is resent; after a timeout the record
/// is read back and a status other than DRAFT means it went.
class SendActions {
  SendActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded.
  Future<String?> sendInvoice(String id, {required bool email}) async {
    try {
      await _repo.sendInvoice(id, email: email);
      _refreshInvoice(id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        InvoiceDetail? fresh;
        try {
          fresh = await _repo.invoice(id);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        if (fresh.summary.status != InvoiceStatus.draft) {
          _refreshInvoice(id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was sent. Please try again.",
        );
      }
      if (e.kind == AppErrorKind.validation) {
        _refreshInvoice(id);
        throw const AppException(AppErrorKind.validation, _movedMessage);
      }
      rethrow;
    }
  }

  Future<String?> sendQuote(String id, {required bool email}) async {
    try {
      await _repo.sendQuote(id, email: email);
      _refreshQuote(id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        QuoteDetail? fresh;
        try {
          fresh = await _repo.quote(id);
        } on AppException {
          fresh = null;
        }
        if (fresh == null) rethrow;
        if (fresh.summary.status != 'DRAFT') {
          _refreshQuote(id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was sent. Please try again.",
        );
      }
      if (e.kind == AppErrorKind.validation) {
        _refreshQuote(id);
        throw const AppException(AppErrorKind.validation, _movedMessage);
      }
      rethrow;
    }
  }

  void _refreshInvoice(String id) {
    _ref.invalidate(invoiceDetailProvider(id));
    _ref.invalidate(invoicesCatalogProvider);
    _ref.invalidate(agingReportProvider);
  }

  void _refreshQuote(String id) {
    _ref.invalidate(quoteDetailProvider(id));
    _ref.invalidate(quotesCatalogProvider);
  }
}

final sendActionsProvider = Provider<SendActions>((ref) => SendActions(ref));
