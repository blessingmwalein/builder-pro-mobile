import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'document_input.dart';
import 'finance_models.dart';
import 'money_models.dart';

/// Read-only finance: overview, invoices and quotes. Nothing here changes data.
class FinanceRepository {
  FinanceRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /financials/summary` (needs `financials.view`).
  Future<FinanceSummary> summary() async =>
      FinanceSummary.parse(await _api.get('financials/summary'));

  /// `GET /financials/dashboard` (needs `financials.view`). Only the active
  /// project count and the budget alerts are read.
  Future<CompanyDashboard> dashboard() async =>
      CompanyDashboard.parse(await _api.get('financials/dashboard'));

  /// `GET /financials/budget-categories` (needs `financials.view`): the
  /// categories every project's budget is split by (standard ones are added the
  /// first time it is read).
  Future<List<BudgetCategory>> budgetCategories() async {
    final body = await _api.get('financials/budget-categories');
    return J
        .list(body)
        .map(BudgetCategory.tryParse)
        .whereType<BudgetCategory>()
        .toList();
  }

  /// `POST /financials/budget-categories` (needs `financials.*`).
  Future<BudgetCategory> createBudgetCategory(String name, String code) async {
    final created = BudgetCategory.tryParse(
      await _api.post(
        'financials/budget-categories',
        body: {'name': name.trim(), 'code': code},
      ),
    );
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The category may have been added.',
      );
    }
    return created;
  }

  /// `PUT /financials/projects/:id/budget` (needs `financials.*`). Sets the
  /// planned amount of each category given (an upsert per category), so sending
  /// it again is harmless. The amounts spent are not set here: the server adds
  /// them up as material is used and bought.
  Future<void> setProjectBudget(
    String projectId,
    List<BudgetEdit> lines,
  ) async {
    await _api.put(
      'financials/projects/$projectId/budget',
      body: {
        'lines': [
          for (final l in lines)
            {
              'categoryId': l.categoryId,
              'plannedAmount': l.plannedAmount,
              'thresholdPct': ?l.thresholdPct,
            },
        ],
      },
    );
  }

  /// `GET /financials/projects/:id/budget` (needs `financials.view`).
  Future<ProjectBudget> projectBudget(String projectId) async =>
      ProjectBudget.parse(
        await _api.get('financials/projects/$projectId/budget'),
      );

  /// The latest expenses: `GET /financials/projects/:id/transactions`
  /// (needs `financials.view`). `page` and `limit` are always sent.
  Future<RecentSpending> recentSpending(
    String projectId, {
    int limit = 10,
  }) async => RecentSpending.parse(
    await _api.get(
      'financials/projects/$projectId/transactions',
      query: {'page': 1, 'limit': limit},
    ),
  );

  /// One page of a project's cost ledger, newest first:
  /// `GET /financials/projects/:id/transactions` (needs `financials.view`).
  /// Only transactions: the category ledger is never used because it lists each
  /// worker's pay (backend-gaps G44). `page` and `limit` are always sent.
  Future<PageResult<SpendEntry>> costTransactions(
    String projectId, {
    int page = 1,
    int limit = pageSize,
  }) async {
    final paged = J.paged(
      await _api.get(
        'financials/projects/$projectId/transactions',
        query: {'page': page, 'limit': limit},
      ),
    );
    return PageResult(
      paged.items.map(SpendEntry.tryParse).whereType<SpendEntry>().toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// `GET /financials/overview` (needs `financials.view`): collected, costs and
  /// profit for a period, with a row per project and its budget as it stands.
  Future<MoneyOverview> moneyOverview(MoneyQuery q) async =>
      MoneyOverview.parse(
        await _api.get('financials/overview', query: q.toQuery()),
      );

  /// One page of the payments that make up the money collected, newest first:
  /// `GET /financials/collections` (needs `financials.view`).
  Future<PageResult<CollectionEntry>> collections(
    MoneyQuery q, {
    int page = 1,
  }) async {
    final paged = J.paged(
      await _api.get(
        'financials/collections',
        query: {...q.toQuery(), 'page': page, 'limit': pageSize},
      ),
    );
    return PageResult(
      paged.items
          .map(CollectionEntry.tryParse)
          .whereType<CollectionEntry>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// One page of the rows behind one kind of cost, newest first:
  /// `GET /financials/costs` (needs `financials.view`). Labour comes added up per
  /// day and project, never per person.
  Future<PageResult<CostEntry>> costs(
    MoneyQuery q,
    CostSource source, {
    int page = 1,
  }) async {
    final paged = J.paged(
      await _api.get(
        'financials/costs',
        query: {
          ...q.toQuery(),
          'source': source.api,
          'page': page,
          'limit': pageSize,
        },
      ),
    );
    return PageResult(
      paged.items
          .map((e) => CostEntry.tryParse(e, source))
          .whereType<CostEntry>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// Everything behind one budget line:
  /// `GET /financials/projects/:id/budget/:categoryId/ledger` (needs
  /// `financials.view`). The server includes each worker's rate in the Labour
  /// line's time entries; only the hours and cost are kept (see
  /// [LedgerLabourDay]).
  Future<BudgetLedger> budgetLedger(
    String projectId,
    String categoryId,
  ) async => BudgetLedger.parse(
    await _api.get('financials/projects/$projectId/budget/$categoryId/ledger'),
  );

  /// `POST /financials/transactions` (needs `financials.*`): records a cost
  /// against a project and a budget category and adds it to that category's spent
  /// amount. NOT repeatable: every call records another cost.
  Future<void> createCost(NewCostInput input) async {
    await _api.post('financials/transactions', body: input.toBody());
  }

  /// `GET /invoices/aging-report` (needs `invoices.view`).
  Future<AgingReport> aging() async =>
      AgingReport.parse(await _api.get('invoices/aging-report'));

  /// Newest first. `page` and `limit` are always sent.
  Future<PageResult<InvoiceSummary>> invoices({
    String? status,
    int page = 1,
    String? clientId,
  }) async {
    final body = await _api.get(
      'invoices',
      query: {
        'page': page,
        'limit': pageSize,
        'status': status,
        'clientId': clientId,
      },
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(InvoiceSummary.tryParse)
          .whereType<InvoiceSummary>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  Future<InvoiceDetail> invoice(String id) async {
    final detail = InvoiceDetail.tryParse(await _api.get('invoices/$id'));
    if (detail == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected invoice response.',
      );
    }
    return detail;
  }

  /// Records a manual payment. NOT repeatable: a repeat counts the money twice.
  /// No notes are sent: the API rejects unknown fields.
  Future<void> recordPayment(
    String invoiceId, {
    required String method,
    required double amount,
  }) async {
    await _api.post(
      'invoices/$invoiceId/payments',
      body: {'method': method, 'amount': amount},
    );
  }

  /// DRAFT → SENT, and (when [email] is set and the client has an address)
  /// emails it to the client. A repeat answers 400, before any email.
  Future<void> sendInvoice(String id, {required bool email}) async {
    await _api.put('invoices/$id/send', body: {'sendEmail': email});
  }

  /// DRAFT → SENT, and (when [email] is set and the client has an address)
  /// emails it to the client. A repeat answers 400, before any email.
  Future<void> sendQuote(String id, {required bool email}) async {
    await _api.put('quotes/$id/send', body: {'sendEmail': email});
  }

  /// SENT → APPROVED. Also records the quote's material lines as used on its
  /// project, on the server. A repeat answers 400.
  Future<void> approveQuote(String id) async {
    await _api.put('quotes/$id/approve');
  }

  /// SENT → REJECTED, with an optional reason. A repeat answers 400.
  Future<void> rejectQuote(String id, {String? notes}) async {
    await _api.put(
      'quotes/$id/reject',
      body: {
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  Future<PageResult<QuoteSummary>> quotes({
    String? status,
    int page = 1,
    String? clientId,
  }) async {
    final body = await _api.get(
      'quotes',
      query: {
        'page': page,
        'limit': pageSize,
        'status': status,
        'clientId': clientId,
      },
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items.map(QuoteSummary.tryParse).whereType<QuoteSummary>().toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// `POST /quotes` (needs `quotes.create`). Makes a DRAFT: nothing is sent to
  /// the client. NOT repeatable: every call makes another quote.
  Future<QuoteSummary> createQuote(QuoteInput input) async {
    final created = QuoteSummary.tryParse(
      await _api.post('quotes', body: input.toBody()),
    );
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The quote may have been created.',
      );
    }
    return created;
  }

  /// `POST /invoices` (needs `invoices.create`). Makes a DRAFT: nothing is sent
  /// to the client. NOT repeatable. The server adds the lines up and carries no
  /// tax or discount (backend-gaps G53).
  Future<InvoiceSummary> createInvoice(InvoiceInput input) async {
    final created = InvoiceSummary.tryParse(
      await _api.post('invoices', body: input.toBody()),
    );
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The invoice may have been created.',
      );
    }
    return created;
  }

  /// `PUT /quotes/:id/convert` (needs `quotes.*`). Despite its name on the
  /// server (`convertToProject`) it only sets an APPROVED quote's status to
  /// CONVERTED: it creates no invoice and no project (G54). A repeat answers 400.
  Future<void> markQuoteConverted(String id) async {
    await _api.put('quotes/$id/convert');
  }

  Future<QuoteDetail> quote(String id) async {
    final detail = QuoteDetail.tryParse(await _api.get('quotes/$id'));
    if (detail == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected quote response.',
      );
    }
    return detail;
  }
}
