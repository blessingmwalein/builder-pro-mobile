import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/state/paged_catalog.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';
import '../data/money_models.dart';
import '../../../core/errors/app_exception.dart';

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(apiClientProvider)),
);

/// Currency of the signed-in company (`GET /auth/me` → tenant.defaultCurrency).
final currencyProvider = Provider<String>(
  (ref) => ref.watch(
    sessionProvider.select((s) => s.me?.tenant.defaultCurrency ?? 'USD'),
  ),
);

/// Costs, collected money and profit. Reloads when the app returns to the front.
final financeSummaryProvider = FutureProvider.autoDispose<FinanceSummary>((
  ref,
) {
  ref.watch(currentUserIdProvider);
  ref.watch(appResumeProvider);
  return ref.watch(financeRepositoryProvider).summary();
});

/// How many projects are active and which budgets are at their alert level.
final companyDashboardProvider = FutureProvider.autoDispose<CompanyDashboard>((
  ref,
) {
  ref.watch(currentUserIdProvider);
  ref.watch(appResumeProvider);
  return ref.watch(financeRepositoryProvider).dashboard();
});

/// A project's budget by category.
final projectBudgetProvider = FutureProvider.autoDispose
    .family<ProjectBudget, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(financeRepositoryProvider).projectBudget(projectId);
    });

/// The budget categories (the same for every project).
final budgetCategoriesProvider =
    FutureProvider.autoDispose<List<BudgetCategory>>((ref) {
      ref.watch(currentUserIdProvider);
      return ref.watch(financeRepositoryProvider).budgetCategories();
    });

/// Setting a project's budget and adding categories.
///
/// A budget is "set" per category, so saving it only sets values and is sent
/// once more after an uncertain failure. Adding a category is never repeated:
/// after a timeout the list is read back for one of that name.
class BudgetActions {
  BudgetActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  Future<void> save(String projectId, List<BudgetEdit> lines) async {
    Future<void> send() => _repo.setProjectBudget(projectId, lines);
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _ref.invalidate(projectBudgetProvider(projectId));
    _ref.invalidate(budgetLedgerProvider);
    _ref.invalidate(moneyOverviewProvider);
    _ref.invalidate(companyDashboardProvider);
  }

  Future<BudgetCategory> addCategory(String name, String code) async {
    List<BudgetCategory>? before;
    try {
      before = await _repo.budgetCategories();
    } on AppException {
      before = null;
    }
    try {
      final created = await _repo.createBudgetCategory(name, code);
      _ref.invalidate(budgetCategoriesProvider);
      return created;
    } on AppException catch (e) {
      if (!e.outcomeUnknown || before == null) rethrow;
      List<BudgetCategory>? now;
      try {
        now = await _repo.budgetCategories();
      } on AppException {
        now = null;
      }
      if (now == null) rethrow;
      final known = before.map((c) => c.id).toSet();
      for (final c in now) {
        if (!known.contains(c.id) &&
            c.name.trim().toLowerCase() == name.trim().toLowerCase()) {
          _ref.invalidate(budgetCategoriesProvider);
          return c;
        }
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and no category was added. Please try again.",
      );
    }
  }
}

final budgetActionsProvider = Provider<BudgetActions>(
  (ref) => BudgetActions(ref),
);

/// A project's latest expenses.
final projectSpendingProvider = FutureProvider.autoDispose
    .family<RecentSpending, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(financeRepositoryProvider).recentSpending(projectId);
    });

/// One project's cost ledger: every transaction, newest first, paged.
class CostLedger extends PagedCatalog<SpendEntry> {
  CostLedger(this.projectId);
  final String projectId;

  @override
  Future<PageResult<SpendEntry>> fetch({String? filter, int page = 1}) => ref
      .read(financeRepositoryProvider)
      .costTransactions(projectId, page: page);

  @override
  String idOf(SpendEntry item) => item.id;
}

final costLedgerProvider = NotifierProvider.autoDispose
    .family<CostLedger, PagedState<SpendEntry>, String>(CostLedger.new);

/// Collected, costs and profit for a period (and optionally one project), with
/// each project's budget as it stands.
final moneyOverviewProvider = FutureProvider.autoDispose
    .family<MoneyOverview, MoneyQuery>((ref, query) {
      ref.watch(currentUserIdProvider);
      return ref.watch(financeRepositoryProvider).moneyOverview(query);
    });

/// The payments that make up the money collected in a period.
class CollectionsLedger extends PagedCatalog<CollectionEntry> {
  CollectionsLedger(this.query);
  final MoneyQuery query;

  @override
  Future<PageResult<CollectionEntry>> fetch({String? filter, int page = 1}) =>
      ref.read(financeRepositoryProvider).collections(query, page: page);

  @override
  String idOf(CollectionEntry item) => item.id;
}

final collectionsLedgerProvider = NotifierProvider.autoDispose
    .family<CollectionsLedger, PagedState<CollectionEntry>, MoneyQuery>(
      CollectionsLedger.new,
    );

/// The rows behind one kind of cost in a period.
class CostsLedger extends PagedCatalog<CostEntry> {
  CostsLedger(this.key);
  final CostsKey key;

  @override
  Future<PageResult<CostEntry>> fetch({String? filter, int page = 1}) => ref
      .read(financeRepositoryProvider)
      .costs(key.query, key.source, page: page);

  @override
  String idOf(CostEntry item) => item.id;
}

final costsLedgerProvider = NotifierProvider.autoDispose
    .family<CostsLedger, PagedState<CostEntry>, CostsKey>(CostsLedger.new);

/// Everything behind one budget line of a project.
final budgetLedgerProvider = FutureProvider.autoDispose
    .family<BudgetLedger, ({String projectId, String categoryId})>((ref, key) {
      ref.watch(currentUserIdProvider);
      return ref
          .watch(financeRepositoryProvider)
          .budgetLedger(key.projectId, key.categoryId);
    });

/// Recording a cost against a project's budget.
///
/// Recording twice would count the cost twice and the server cannot tell a repeat
/// from a second cost, so it is never resent. The cost carries its exact moment:
/// after a timeout the project's costs are read for one with that description,
/// amount and moment. Found means it arrived; not there (with the list read past
/// that moment) means it did not; anything else stays unknown and the person is
/// told to look before trying again.
class CostActions {
  CostActions(this._ref);
  final Ref _ref;

  FinanceRepository get _repo => _ref.read(financeRepositoryProvider);

  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded or it could not be told.
  Future<String?> record(NewCostInput input) async {
    try {
      await _repo.createCost(input);
      _after();
      return null;
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      final look = await _find(input);
      if (look.found) {
        _after();
        return 'The cost was recorded. The confirmation was slow, so we checked.';
      }
      if (look.certainlyNotThere) {
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was recorded. Please try again.",
        );
      }
      throw const AppException(
        AppErrorKind.uncertain,
        "We couldn't tell whether this cost was recorded. Open the project's costs and look for it before trying again, or it may be counted twice.",
      );
    }
  }

  Future<({bool found, bool certainlyNotThere})> _find(
    NewCostInput input,
  ) async {
    try {
      for (var page = 1; page <= 3; page++) {
        final result = await _repo.costTransactions(
          input.projectId,
          page: page,
          limit: 50,
        );
        if (result.items.any(input.isSameAs)) {
          return (found: true, certainlyNotThere: false);
        }
        // Newest first: once the list is past our moment, ours would be on it.
        final oldest = result.items.isEmpty ? null : result.items.last;
        if (!result.hasMore ||
            (oldest != null && oldest.occurredAt.isBefore(input.occurredAt))) {
          return (found: false, certainlyNotThere: true);
        }
      }
    } on AppException {
      // Could not even ask: the outcome stays unknown.
    }
    return (found: false, certainlyNotThere: false);
  }

  void _after() {
    _ref.invalidate(projectBudgetProvider);
    _ref.invalidate(projectSpendingProvider);
    _ref.invalidate(costLedgerProvider);
    _ref.invalidate(budgetLedgerProvider);
    _ref.invalidate(moneyOverviewProvider);
    _ref.invalidate(costsLedgerProvider);
    _ref.invalidate(financeSummaryProvider);
    _ref.invalidate(companyDashboardProvider);
  }
}

final costActionsProvider = Provider<CostActions>((ref) => CostActions(ref));

/// Money owed by clients, by how late it is.
final agingReportProvider = FutureProvider.autoDispose<AgingReport>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(appResumeProvider);
  return ref.watch(financeRepositoryProvider).aging();
});

class InvoicesCatalog extends PagedCatalog<InvoiceSummary> {
  @override
  Future<PageResult<InvoiceSummary>> fetch({String? filter, int page = 1}) =>
      ref.read(financeRepositoryProvider).invoices(status: filter, page: page);

  @override
  String idOf(InvoiceSummary item) => item.id;
}

final invoicesCatalogProvider =
    NotifierProvider<InvoicesCatalog, PagedState<InvoiceSummary>>(
      InvoicesCatalog.new,
    );

class QuotesCatalog extends PagedCatalog<QuoteSummary> {
  @override
  Future<PageResult<QuoteSummary>> fetch({String? filter, int page = 1}) =>
      ref.read(financeRepositoryProvider).quotes(status: filter, page: page);

  @override
  String idOf(QuoteSummary item) => item.id;
}

final quotesCatalogProvider =
    NotifierProvider<QuotesCatalog, PagedState<QuoteSummary>>(
      QuotesCatalog.new,
    );

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<InvoiceDetail, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(financeRepositoryProvider).invoice(id);
    });

final quoteDetailProvider = FutureProvider.autoDispose
    .family<QuoteDetail, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(financeRepositoryProvider).quote(id);
    });
