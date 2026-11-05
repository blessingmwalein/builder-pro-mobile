import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/state/paged_catalog.dart';
import '../../finance/application/finance_providers.dart'
    show
        budgetLedgerProvider,
        companyDashboardProvider,
        costLedgerProvider,
        costsLedgerProvider,
        moneyOverviewProvider,
        projectBudgetProvider,
        projectSpendingProvider;
import '../../sync/application/sync_providers.dart';
import '../../sync/data/queued_write_models.dart';
import '../data/material_models.dart';
import '../data/material_purchase_models.dart';
import '../data/material_reference_models.dart';
import '../data/materials_repository.dart';

final materialsRepositoryProvider = Provider<MaterialsRepository>(
  (ref) => MaterialsRepository(ref.watch(apiClientProvider)),
);

class CatalogState {
  const CatalogState({
    this.items = const [],
    this.query = '',
    this.page = 0,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.fromSavedCopy = false,
  });

  final List<MaterialItem> items;
  final String query;
  final int page;
  final bool hasMore;

  /// The server could not be reached, so these are the materials saved on this
  /// phone from earlier visits. Stock and cost may be out of date.
  final bool fromSavedCopy;

  /// First page for the current query is loading.
  final bool loading;
  final bool loadingMore;

  /// The first page failed; the list cannot be shown.
  final AppException? error;

  /// A later page failed; the loaded items stay on screen.
  final AppException? loadMoreError;

  CatalogState copyWith({
    List<MaterialItem>? items,
    String? query,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppException? error,
    AppException? loadMoreError,
    bool? fromSavedCopy,
    bool clearError = false,
  }) => CatalogState(
    items: items ?? this.items,
    query: query ?? this.query,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
    fromSavedCopy: fromSavedCopy ?? this.fromSavedCopy,
  );
}

/// The company material catalog with search and paging.
class MaterialCatalog extends Notifier<CatalogState> {
  /// Bumped for every new search so a slow earlier reply cannot overwrite a newer one.
  int _generation = 0;

  @override
  CatalogState build() {
    ref.watch(currentUserIdProvider);
    Future<void>.microtask(() => _loadFirst(''));
    return const CatalogState();
  }

  Future<void> search(String query) {
    final q = query.trim();
    if (q == state.query && state.error == null) return Future.value();
    return _loadFirst(q);
  }

  Future<void> refresh() => _loadFirst(state.query);

  Future<void> _loadFirst(String query) async {
    final gen = ++_generation;
    state = state.copyWith(
      query: query,
      loading: true,
      clearError: true,
      items: const [],
      page: 0,
      hasMore: false,
      fromSavedCopy: false,
    );
    try {
      final page = await ref
          .read(materialsRepositoryProvider)
          .list(search: query);
      if (gen != _generation || !ref.mounted) return;
      state = state.copyWith(
        items: page.items,
        page: page.page,
        hasMore: page.hasMore,
        loading: false,
      );
      await _save(page.items);
    } on AppException catch (e) {
      if (gen != _generation || !ref.mounted) return;
      // No connection: offer what was saved from earlier visits, so material
      // can still be picked and its use saved on the phone.
      if (e.isNetwork) {
        final saved = await _saved(query);
        if (gen != _generation || !ref.mounted) return;
        if (saved.isNotEmpty) {
          state = state.copyWith(
            items: saved,
            hasMore: false,
            loading: false,
            fromSavedCopy: true,
          );
          return;
        }
      }
      state = state.copyWith(loading: false, error: e);
    }
  }

  // The materials seen on earlier visits, kept per user, so the catalog still
  // opens without signal. Wiped on sign-out with the rest of the cache.
  static const _scope = 'material';

  Future<void> _save(List<MaterialItem> items) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final db = ref.read(appDatabaseProvider);
    try {
      for (final i in items) {
        await db.putCache(uid, _scope, i.id, jsonEncode(i.toJson()));
      }
    } catch (_) {
      // A saved copy is a convenience; never fail the list over it.
    }
  }

  Future<List<MaterialItem>> _saved(String query) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return const [];
    try {
      final rows = await ref.read(appDatabaseProvider).readCache(uid, _scope);
      final items = <MaterialItem>[];
      for (final r in rows) {
        final item = MaterialItem.tryParse(
          Map<String, dynamic>.from(jsonDecode(r.json) as Map),
        );
        if (item != null && item.matches(query)) items.add(item);
      }
      items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final gen = _generation;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(materialsRepositoryProvider)
          .list(search: state.query, page: state.page + 1);
      if (gen != _generation || !ref.mounted) return;
      final known = state.items.map((i) => i.id).toSet();
      state = state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((i) => !known.contains(i.id)),
        ],
        page: page.page,
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on AppException catch (e) {
      if (gen != _generation || !ref.mounted) return;
      state = state.copyWith(loadingMore: false, loadMoreError: e);
    }
  }
}

final materialCatalogProvider = NotifierProvider<MaterialCatalog, CatalogState>(
  MaterialCatalog.new,
);

/// Usage logs recorded on this phone during this session, newest first.
class LoggedThisSession extends Notifier<List<MaterialLogEntry>> {
  @override
  List<MaterialLogEntry> build() {
    ref.watch(currentUserIdProvider);
    return const [];
  }

  void add(MaterialLogEntry log) {
    if (state.any((l) => l.id == log.id)) return;
    state = [log, ...state];
  }
}

final loggedThisSessionProvider =
    NotifierProvider<LoggedThisSession, List<MaterialLogEntry>>(
      LoggedThisSession.new,
    );

class LogUsageResult {
  const LogUsageResult(this.log, {this.note, this.savedOnPhone = false});

  /// What the server recorded; null when the usage was saved on the phone.
  final MaterialLogEntry? log;

  /// Explains a recovered outcome (the first reply never arrived).
  final String? note;

  /// There was no connection, so it was saved on the phone and will be sent
  /// when there is one.
  final bool savedOnPhone;
}

class MaterialUsageActions {
  MaterialUsageActions(this._ref);
  final Ref _ref;

  /// Records usage. If the reply never arrives the request is NOT repeated:
  /// the latest logs are read to see whether it was saved, and only a definite
  /// "nothing was recorded" lets the worker try again.
  ///
  /// With no connection (nothing was delivered) it is saved on the phone with
  /// the moment it was used and sent later by the write queue, exactly once.
  Future<LogUsageResult> logUsage({
    required MaterialItem material,
    required String projectId,
    required String projectName,
    required double quantity,
    String? notes,
  }) async {
    final repo = _ref.read(materialsRepositoryProvider);
    final startedAt = DateTime.now();
    final phoneIsOffline = _ref.read(connectivityProvider).value == false;
    if (phoneIsOffline && _ref.read(writeQueueProvider) != null) {
      return _saveOnPhone(
        material: material,
        projectId: projectId,
        projectName: projectName,
        quantity: quantity,
        notes: notes,
      );
    }
    try {
      final log = await repo.logUsage(
        material: material,
        projectId: projectId,
        projectName: projectName,
        quantity: quantity,
        notes: notes,
      );
      _ref.read(loggedThisSessionProvider.notifier).add(log);
      return LogUsageResult(log);
    } on AppException catch (e) {
      // Nothing was delivered, so saving it for later cannot count it twice.
      if (e.isNetwork && _ref.read(writeQueueProvider) != null) {
        return _saveOnPhone(
          material: material,
          projectId: projectId,
          projectName: projectName,
          quantity: quantity,
          notes: notes,
        );
      }
      if (!e.outcomeUnknown) rethrow;
      List<MaterialLogEntry>? recent;
      try {
        recent = await repo.recentLogs(
          projectId: projectId,
          materialId: material.id,
        );
      } on AppException {
        recent = null;
      }
      // Could not even check: the outcome stays unknown.
      if (recent == null) rethrow;
      final since = startedAt.subtract(const Duration(minutes: 2));
      for (final l in recent) {
        if ((l.quantity - quantity).abs() < 0.0005 && l.usedAt.isAfter(since)) {
          _ref.read(loggedThisSessionProvider.notifier).add(l);
          return LogUsageResult(
            l,
            note: 'It was recorded. The confirmation was slow, so we checked.',
          );
        }
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and nothing was recorded. Please try again.",
      );
    }
  }

  Future<LogUsageResult> _saveOnPhone({
    required MaterialItem material,
    required String projectId,
    required String projectName,
    required double quantity,
    String? notes,
  }) async {
    final queue = _ref.read(writeQueueProvider)!;
    final id = const Uuid().v4();
    await queue.enqueue(
      id: id,
      kind: WriteKind.materialUsage,
      // Each use is sent on its own, so one that needs attention holds nothing
      // else back.
      stream: 'usage:$id',
      payload: MaterialUsageWrite(
        projectId: projectId,
        projectName: projectName,
        materialId: material.id,
        materialName: material.name,
        unit: material.unit,
        quantity: quantity,
        unitCost: material.unitCost,
        notes: notes == null || notes.trim().isEmpty ? null : notes.trim(),
        occurredAt: eventTime(),
      ).toJson(),
    );
    unawaited(queue.flush());
    return const LogUsageResult(
      null,
      savedOnPhone: true,
      note: 'Saved on this phone. It will be sent when there is a connection.',
    );
  }
}

final materialUsageActionsProvider = Provider<MaterialUsageActions>(
  (ref) => MaterialUsageActions(ref),
);

/// One material as the server has it now (its stock changes with every use,
/// purchase and delivery, so the saved catalog copy is not trusted for a count).
final materialDetailProvider = FutureProvider.autoDispose
    .family<MaterialItem, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(materialsRepositoryProvider).material(id);
    });

/// Purchases recorded against stock, newest first.
class MaterialPurchasesLedger extends PagedCatalog<MaterialPurchase> {
  @override
  Future<PageResult<MaterialPurchase>> fetch({String? filter, int page = 1}) =>
      ref.read(materialsRepositoryProvider).purchases(page: page);

  @override
  String idOf(MaterialPurchase item) => item.id;
}

final materialPurchasesProvider =
    NotifierProvider.autoDispose<
      MaterialPurchasesLedger,
      PagedState<MaterialPurchase>
    >(MaterialPurchasesLedger.new);

/// The company's material categories (the web app's list).
final materialCategoriesProvider =
    FutureProvider.autoDispose<List<MaterialCategoryRef>>((ref) {
      ref.watch(currentUserIdProvider);
      return ref.watch(materialsRepositoryProvider).categories();
    });

/// Where materials are bought or delivered from.
final suppliersProvider = FutureProvider.autoDispose<List<Supplier>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(materialsRepositoryProvider).suppliers();
});

/// A saved material or supplier, with a note when the outcome needs explaining.
class Saved<T> {
  const Saved(this.value, {this.note});
  final T value;
  final String? note;
}

/// Adding and changing materials, suppliers and categories.
///
/// Adding is never repeated (a second call makes a second record). Before it is
/// sent the existing records of that name are noted; after a timeout they are
/// read again, and a new one of the same name means it arrived. If the first
/// reading failed there is nothing to compare with, so an unknown outcome stays
/// unknown. Changing a material only sets fields, so it is sent once more after
/// an uncertain failure.
class MaterialManagement {
  MaterialManagement(this._ref);
  final Ref _ref;

  MaterialsRepository get _repo => _ref.read(materialsRepositoryProvider);

  static bool _same(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  void _refreshCatalog() {
    _ref.read(materialCatalogProvider.notifier).refresh();
  }

  Future<Saved<MaterialItem>> createMaterial(MaterialInput input) async {
    Set<String>? before;
    try {
      before = (await _repo.list(search: input.name)).items
          .where((m) => _same(m.name, input.name))
          .map((m) => m.id)
          .toSet();
    } on AppException {
      before = null;
    }
    try {
      final created = await _repo.createMaterial(input);
      _refreshCatalog();
      return Saved(created);
    } on AppException catch (e) {
      if (!e.outcomeUnknown || before == null) rethrow;
      List<MaterialItem>? now;
      try {
        now = (await _repo.list(search: input.name)).items;
      } on AppException {
        now = null;
      }
      if (now == null) rethrow;
      for (final m in now) {
        if (_same(m.name, input.name) && !before.contains(m.id)) {
          _refreshCatalog();
          return Saved(
            m,
            note: 'The material was saved. The confirmation was slow, so we checked.',
          );
        }
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and no material was added. Please try again.",
      );
    }
  }

  Future<void> updateMaterial(String id, MaterialInput input) async {
    Future<void> send() => _repo.updateMaterial(id, input);
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _refreshCatalog();
  }

  /// Records material bought straight from a supplier, with no order. Adding it
  /// twice would add the stock and the cost twice and the server cannot tell a
  /// repeat from a second purchase, so it is never resent. The purchase carries
  /// its exact moment: after a timeout the supplier's purchases are read for one
  /// at that moment with that total. Found means it arrived; not there (with
  /// the list read past that moment) means it did not; anything else stays
  /// unknown and the person is told to look before trying again.
  Future<Saved<MaterialPurchase>> recordPurchase(NewPurchaseInput input) async {
    try {
      final created = await _repo.createPurchase(input);
      _afterPurchase(input);
      return Saved(created);
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      final look = await _findPurchase(input);
      if (look.found != null) {
        _afterPurchase(input);
        return Saved(
          look.found!,
          note: 'The purchase was recorded. The confirmation was slow, so we checked.',
        );
      }
      if (look.certainlyNotThere) {
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was recorded. Please try again.",
        );
      }
      throw const AppException(
        AppErrorKind.uncertain,
        "We couldn't tell whether this purchase was recorded. Open Purchases and look for it before trying again, or it may be counted twice.",
      );
    }
  }

  /// Reads the supplier's purchases for the one [input] made. `found` is it;
  /// `certainlyNotThere` means the list was read past its moment without it.
  /// Neither means the server could not be asked or the list was too long.
  Future<({MaterialPurchase? found, bool certainlyNotThere})> _findPurchase(
    NewPurchaseInput input,
  ) async {
    try {
      for (var page = 1; page <= 3; page++) {
        final result = await _repo.purchases(
          page: page,
          limit: 50,
          supplierId: input.supplierId,
        );
        for (final p in result.items) {
          if (p.isSameAs(input)) return (found: p, certainlyNotThere: false);
        }
        // Newest first: once the list is past our moment, ours would have been
        // on it already.
        final oldest = result.items.isEmpty ? null : result.items.last;
        if (!result.hasMore ||
            (oldest != null &&
                oldest.purchasedAt.isBefore(input.purchasedAt))) {
          return (found: null, certainlyNotThere: true);
        }
      }
    } on AppException {
      // Could not even ask: the outcome stays unknown.
    }
    return (found: null, certainlyNotThere: false);
  }

  void _afterPurchase(NewPurchaseInput input) {
    _refreshCatalog();
    _ref.invalidate(materialPurchasesProvider);
    if (input.projectId != null) {
      _ref.invalidate(projectBudgetProvider);
      _ref.invalidate(projectSpendingProvider);
      _ref.invalidate(costLedgerProvider);
      _ref.invalidate(moneyOverviewProvider);
      _ref.invalidate(costsLedgerProvider);
      _ref.invalidate(budgetLedgerProvider);
      _ref.invalidate(companyDashboardProvider);
    }
  }

  /// Corrects a stock count: the stock on hand becomes [counted], with [reason]
  /// kept by the server as a stock correction. [recorded] is what the person was
  /// looking at when they counted; if the stock has moved since (something was
  /// used or delivered) the correction is refused rather than overwriting that.
  ///
  /// It sets a quantity, so a repeat that arrived first would be harmless, but
  /// only if nothing moved in between. After a timeout the stock is read back
  /// instead of resending: the counted figure means it arrived; the recorded
  /// figure means it did not. Returns a note when the outcome needs explaining;
  /// throws when nothing was changed.
  Future<String?> correctStock(
    MaterialItem recorded,
    double counted,
    String reason,
  ) async {
    bool sameStock(double a, double b) => (a - b).abs() < 0.0005;
    String stale(MaterialItem now) =>
        'The stock of ${now.name} is now ${Fmt.quantity(now.stockOnHand)} ${now.unit}. Something was used or delivered since you opened this. The page shows the current figure: check your count and try again.';

    void refresh() {
      _ref.invalidate(materialDetailProvider(recorded.id));
      _refreshCatalog();
    }

    final before = await _repo.material(recorded.id);
    if (!sameStock(before.stockOnHand, recorded.stockOnHand)) {
      refresh();
      throw AppException(AppErrorKind.validation, stale(before));
    }

    try {
      await _repo.setStock(recorded.id, counted, reason);
      refresh();
      return null;
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      MaterialItem? now;
      try {
        now = await _repo.material(recorded.id);
      } on AppException {
        now = null;
      }
      // Could not even ask: the outcome stays unknown.
      if (now == null) rethrow;
      if (sameStock(now.stockOnHand, counted) &&
          !sameStock(counted, recorded.stockOnHand)) {
        refresh();
        return 'The count was saved. The confirmation was slow, so we checked.';
      }
      if (sameStock(now.stockOnHand, recorded.stockOnHand)) {
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and the stock was not changed. Please try again.",
        );
      }
      refresh();
      throw AppException(AppErrorKind.validation, stale(now));
    }
  }

  Future<Saved<Supplier>> createSupplier(SupplierInput input) async {
    List<Supplier>? before;
    try {
      before = await _repo.suppliers();
    } on AppException {
      before = null;
    }
    try {
      final created = await _repo.createSupplier(input);
      _ref.invalidate(suppliersProvider);
      return Saved(created);
    } on AppException catch (e) {
      if (!e.outcomeUnknown || before == null) rethrow;
      List<Supplier>? now;
      try {
        now = await _repo.suppliers();
      } on AppException {
        now = null;
      }
      if (now == null) rethrow;
      final known = before.map((s) => s.id).toSet();
      for (final s in now) {
        if (_same(s.name, input.name) && !known.contains(s.id)) {
          _ref.invalidate(suppliersProvider);
          return Saved(
            s,
            note: 'The supplier was saved. The confirmation was slow, so we checked.',
          );
        }
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and no supplier was added. Please try again.",
      );
    }
  }

  Future<Saved<MaterialCategoryRef>> createCategory(String name) async {
    List<MaterialCategoryRef>? before;
    try {
      before = await _repo.categories();
    } on AppException {
      before = null;
    }
    try {
      final created = await _repo.createCategory(name);
      _ref.invalidate(materialCategoriesProvider);
      return Saved(created);
    } on AppException catch (e) {
      if (!e.outcomeUnknown || before == null) rethrow;
      List<MaterialCategoryRef>? now;
      try {
        now = await _repo.categories();
      } on AppException {
        now = null;
      }
      if (now == null) rethrow;
      final known = before.map((c) => c.id).toSet();
      for (final c in now) {
        if (_same(c.name, name) && !known.contains(c.id)) {
          _ref.invalidate(materialCategoriesProvider);
          return Saved(
            c,
            note: 'The category was saved. The confirmation was slow, so we checked.',
          );
        }
      }
      throw const AppException(
        AppErrorKind.timeout,
        "That didn't go through and no category was added. Please try again.",
      );
    }
  }
}

final materialManagementProvider = Provider<MaterialManagement>(
  (ref) => MaterialManagement(ref),
);
