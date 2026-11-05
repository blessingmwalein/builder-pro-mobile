import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import 'finance_providers.dart';

/// Quote statuses the backend uses.
abstract final class QuoteStatus {
  static const sent = 'SENT';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';

  /// Set once an invoice has been made from an approved quote.
  static const converted = 'CONVERTED';
}

const _movedMessage =
    'This quote has changed since you opened it. The page now shows its current state.';

/// Marking a sent quote approved or rejected.
///
/// Both only set the quote's status and answer 400 when repeated, so nothing is
/// resent: after a timeout the quote is read back and its status says what
/// happened. (Approving also records the quote's material lines as used on its
/// project, once, on the server.)
class QuoteActions {
  QuoteActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded.
  Future<String?> approve(String id) => _decide(
    id,
    wanted: QuoteStatus.approved,
    send: () => _repo.approveQuote(id),
  );

  Future<String?> reject(String id, {String? notes}) => _decide(
    id,
    wanted: QuoteStatus.rejected,
    send: () => _repo.rejectQuote(id, notes: notes),
  );

  Future<String?> _decide(
    String id, {
    required String wanted,
    required Future<void> Function() send,
  }) async {
    try {
      await send();
      _refresh(id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        QuoteDetail? fresh;
        try {
          fresh = await _repo.quote(id);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final status = fresh.summary.status;
        if (status == wanted) {
          _refresh(id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (status == QuoteStatus.sent) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _refresh(id);
        throw const AppException(AppErrorKind.validation, _movedMessage);
      }
      if (e.kind == AppErrorKind.validation) {
        // Only a sent quote can be decided: it moved on.
        _refresh(id);
        throw const AppException(AppErrorKind.validation, _movedMessage);
      }
      rethrow;
    }
  }

  void _refresh(String id) {
    _ref.invalidate(quoteDetailProvider(id));
    _ref.invalidate(quotesCatalogProvider);
    _ref.invalidate(financeSummaryProvider);
  }
}

final quoteActionsProvider = Provider<QuoteActions>((ref) => QuoteActions(ref));
