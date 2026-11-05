import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/state/paged_catalog.dart';
import '../data/document_input.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import 'finance_providers.dart';

/// A quote or invoice that was just made, and a note when the outcome needs
/// explaining.
class CreatedDocument<T> {
  const CreatedDocument(this.document, {this.note});
  final T document;
  final String? note;
}

/// Making quotes and invoices.
///
/// Creating is never repeated (a second call makes a second document). After a
/// timeout the client's newest documents are read back: one with the same title
/// (or the same total, for an invoice) made in the last three minutes means it
/// arrived. The server records no creator, so this cannot be checked further.
class QuoteInvoiceActions {
  QuoteInvoiceActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  static const _window = Duration(minutes: 3);

  Future<CreatedDocument<QuoteSummary>> createQuote(QuoteInput input) async {
    final startedAt = DateTime.now();
    try {
      final quote = await _repo.createQuote(input);
      _refreshQuotes();
      return CreatedDocument(quote);
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      PageResult<QuoteSummary>? page;
      try {
        page = await _repo.quotes(clientId: input.clientId);
      } on AppException {
        page = null;
      }
      // Could not even ask: the outcome stays unknown.
      if (page == null) rethrow;
      final since = startedAt.subtract(_window);
      final expected = input.totals.total;
      for (final q in page.items) {
        final made = q.createdAt;
        if (q.title == input.title.trim() &&
            (q.total - expected).abs() < 0.01 &&
            made != null &&
            made.isAfter(since)) {
          _refreshQuotes();
          return CreatedDocument(
            q,
            note: 'The quote was saved. The confirmation was slow, so we checked.',
          );
        }
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and no quote was created. Please try again.",
      );
    }
  }

  /// Makes a draft invoice. When it was made from an approved quote
  /// ([convertQuoteId]) the quote is then marked as converted, as the web app
  /// does. That comes AFTER the invoice exists, so giving up half way never
  /// leaves a converted quote with no invoice; if it cannot be done the invoice
  /// is kept and the note says so.
  Future<CreatedDocument<InvoiceSummary>> createInvoice(
    InvoiceInput input, {
    String? convertQuoteId,
  }) async {
    final startedAt = DateTime.now();
    InvoiceSummary invoice;
    String? note;
    try {
      invoice = await _repo.createInvoice(input);
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      PageResult<InvoiceSummary>? page;
      try {
        page = await _repo.invoices(clientId: input.clientId);
      } on AppException {
        page = null;
      }
      if (page == null) rethrow;
      final since = startedAt.subtract(_window);
      InvoiceSummary? match;
      for (final i in page.items) {
        final made = i.createdAt;
        if ((i.total - input.total).abs() < 0.01 &&
            made != null &&
            made.isAfter(since)) {
          match = i;
          break;
        }
      }
      if (match == null) {
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and no invoice was created. Please try again.",
        );
      }
      invoice = match;
      note = 'The invoice was saved. The confirmation was slow, so we checked.';
    }

    if (convertQuoteId != null) {
      try {
        await _repo.markQuoteConverted(convertQuoteId);
      } on AppException catch (e) {
        final why = e.kind == AppErrorKind.forbidden
            ? 'your role cannot change quotes'
            : e.message;
        note =
            '${note == null ? '' : '$note '}The invoice was created, but the quote could not be marked as converted ($why).';
      }
    }
    _refreshInvoices();
    _refreshQuotes();
    if (convertQuoteId != null) {
      _ref.invalidate(quoteDetailProvider(convertQuoteId));
    }
    return CreatedDocument(invoice, note: note);
  }

  void _refreshQuotes() {
    _ref.read(quotesCatalogProvider.notifier).refresh();
  }

  void _refreshInvoices() {
    _ref.read(invoicesCatalogProvider.notifier).refresh();
    _ref.invalidate(agingReportProvider);
  }
}

final quoteInvoiceActionsProvider = Provider<QuoteInvoiceActions>(
  (ref) => QuoteInvoiceActions(ref),
);
