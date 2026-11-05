import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/state/paged_catalog.dart';
import '../../materials/application/materials_providers.dart';
import '../data/purchasing_models.dart';
import '../data/purchasing_repository.dart';

final purchasingRepositoryProvider = Provider<PurchasingRepository>(
  (ref) => PurchasingRepository(ref.watch(apiClientProvider)),
);

class PurchaseRequestsCatalog extends PagedCatalog<PurchaseRequestSummary> {
  @override
  Future<PageResult<PurchaseRequestSummary>> fetch({
    String? filter,
    int page = 1,
  }) => ref
      .read(purchasingRepositoryProvider)
      .requests(status: filter, page: page);

  @override
  String idOf(PurchaseRequestSummary item) => item.id;
}

final purchaseRequestsProvider =
    NotifierProvider<
      PurchaseRequestsCatalog,
      PagedState<PurchaseRequestSummary>
    >(PurchaseRequestsCatalog.new);

class PurchaseOrdersCatalog extends PagedCatalog<PurchaseOrderSummary> {
  @override
  Future<PageResult<PurchaseOrderSummary>> fetch({
    String? filter,
    int page = 1,
  }) =>
      ref.read(purchasingRepositoryProvider).orders(status: filter, page: page);

  @override
  String idOf(PurchaseOrderSummary item) => item.id;
}

final purchaseOrdersProvider =
    NotifierProvider<PurchaseOrdersCatalog, PagedState<PurchaseOrderSummary>>(
      PurchaseOrdersCatalog.new,
    );

final purchaseRequestDetailProvider = FutureProvider.autoDispose
    .family<PurchaseRequestDetail, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(purchasingRepositoryProvider).request(id);
    });

final purchaseOrderDetailProvider = FutureProvider.autoDispose
    .family<PurchaseOrderDetail, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(purchasingRepositoryProvider).order(id);
    });

/// Result of "new purchase request".
class NewRequestResult {
  const NewRequestResult(
    this.request, {
    this.submitted = false,
    this.note,
    this.submitError,
  });

  final PurchaseRequestSummary request;

  /// It is now waiting for approval (not just saved as a draft).
  final bool submitted;

  /// Explains a recovered outcome (the first reply never arrived).
  final String? note;

  /// The draft was saved but submitting it failed; the draft is not lost.
  final AppException? submitError;
}

/// Creating, submitting, approving and rejecting purchase requests.
///
/// None of these can safely be sent twice, so after a timeout the request is
/// read back and what the server holds decides what the user is told.
class PurchasingActions {
  PurchasingActions(this._ref);
  final Ref _ref;

  PurchasingRepository get _repo => _ref.read(purchasingRepositoryProvider);

  /// Creates a draft and, when [submit] is set, submits it for approval.
  Future<NewRequestResult> create({
    required List<NewPrItem> items,
    String? projectId,
    String? notes,
    bool submit = false,
  }) async {
    final me = _ref.read(currentUserIdProvider);
    final startedAt = DateTime.now();
    PurchaseRequestSummary created;
    String? note;
    try {
      created = await _repo.createRequest(
        items: items,
        projectId: projectId,
        notes: notes,
      );
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      // Newest drafts come first, so a request created just now is on page 1.
      PageResult<PurchaseRequestSummary>? page;
      try {
        page = await _repo.requests(
          status: PrStatus.draft,
          projectId: projectId,
        );
      } on AppException {
        page = null;
      }
      // Could not even look: the outcome stays unknown.
      if (page == null) rethrow;
      final since = startedAt.subtract(const Duration(minutes: 2));
      final match = page.items
          .where(
            (r) =>
                r.requestedById == me &&
                r.createdAt.isAfter(since) &&
                r.itemCount == items.length,
          )
          .firstOrNull;
      if (match == null) {
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and no request was created. Please try again.",
        );
      }
      created = match;
      note = 'The request was saved. The confirmation was slow, so we checked.';
    }
    _refreshLists();
    if (!submit) return NewRequestResult(created, note: note);
    try {
      final submitNote = await this.submit(created.id);
      return NewRequestResult(
        created,
        submitted: true,
        note: submitNote ?? note,
      );
    } on AppException catch (e) {
      return NewRequestResult(created, note: note, submitError: e);
    }
  }

  /// DRAFT → SUBMITTED.
  Future<String?> submit(String id) => _transition(
    id,
    () => _repo.submit(id),
    pending: PrStatus.draft,
    done: {PrStatus.submitted, PrStatus.approved, PrStatus.ordered},
  );

  /// SUBMITTED → APPROVED.
  Future<String?> approve(String id) => _transition(
    id,
    () => _repo.approve(id),
    pending: PrStatus.submitted,
    done: {PrStatus.approved, PrStatus.ordered},
  );

  /// SUBMITTED → REJECTED.
  Future<String?> reject(String id, {String? notes}) => _transition(
    id,
    () => _repo.reject(id, notes: notes),
    pending: PrStatus.submitted,
    done: {PrStatus.rejected},
  );

  Future<String?> _transition(
    String id,
    Future<void> Function() send, {
    required String pending,
    required Set<String> done,
  }) async {
    try {
      await send();
      _refreshAfterChange(id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        PurchaseRequestDetail? fresh;
        try {
          fresh = await _repo.request(id);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final status = fresh.summary.status;
        if (done.contains(status)) {
          _refreshAfterChange(id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (status == pending) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _refreshAfterChange(id);
        return 'This request has already moved on.';
      }
      if (e.kind == AppErrorKind.validation) {
        // The server refuses a change from the wrong status: it moved on.
        _refreshAfterChange(id);
        throw const AppException(
          AppErrorKind.validation,
          'This request has changed since you opened it. The page now shows its current status.',
        );
      }
      rethrow;
    }
  }

  static const _orderMovedMessage =
      'This order has changed since you opened it. The page now shows its current state.';

  /// Turns an approved request into a draft order. The request becomes ORDERED,
  /// so a repeat answers 400 and nothing is ever resent: after a timeout the
  /// request is read back, and ORDERED with an order on it means it went
  /// through. Returns the order's id (and a note when the outcome needs
  /// explaining); throws when nothing was recorded.
  Future<({String orderId, String? note})> createOrder(
    NewOrderInput input,
  ) async {
    void refresh() {
      _ref.invalidate(purchaseRequestDetailProvider(input.requestId));
      _ref.read(purchaseRequestsProvider.notifier).refresh();
      _ref.read(purchaseOrdersProvider.notifier).refresh();
    }

    try {
      final order = await _repo.createOrder(input);
      refresh();
      return (orderId: order.id, note: null);
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        PurchaseRequestDetail? fresh;
        try {
          fresh = await _repo.request(input.requestId);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        if (fresh.summary.status == PrStatus.ordered &&
            fresh.orders.isNotEmpty) {
          refresh();
          return (
            orderId: fresh.orders.last.id,
            note: 'The order was created. The confirmation was slow, so we checked.',
          );
        }
        if (fresh.summary.status == PrStatus.approved) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and no order was created. Please try again.",
          );
        }
        refresh();
        throw const AppException(
          AppErrorKind.validation,
          'This request has changed since you opened it. The page now shows its current state.',
        );
      }
      if (e.kind == AppErrorKind.validation) {
        // Only an approved request can be ordered: it was ordered already.
        refresh();
        throw const AppException(
          AppErrorKind.validation,
          'This request can no longer be ordered. It may already have an order.',
        );
      }
      rethrow;
    }
  }

  /// Marks a draft order as sent. It only sets the status, and a repeat answers
  /// 400, so after a timeout the order is read back: no longer a draft means it
  /// is done. Returns a note when the outcome needs explaining; throws when
  /// nothing was recorded.
  Future<String?> sendOrder(String orderId) async {
    try {
      await _repo.sendOrder(orderId);
      _refreshOrder(orderId);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        PurchaseOrderDetail? fresh;
        try {
          fresh = await _repo.order(orderId);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        if (fresh.summary.status != PoStatus.draft) {
          _refreshOrder(orderId);
          return 'Done. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was recorded. Please try again.",
        );
      }
      if (e.kind == AppErrorKind.validation) {
        // Not a draft any more: it was already sent (or cancelled).
        _refreshOrder(orderId);
        throw const AppException(AppErrorKind.validation, _orderMovedMessage);
      }
      rethrow;
    }
  }

  /// Saves changes to a draft order. The server sets the supplier, date, notes
  /// and lines to exactly what is sent, so after an uncertain failure it is sent
  /// once more. The order is read first: one that was sent, cancelled or
  /// received since it was opened is refused here rather than overwritten.
  Future<void> updateOrder(String orderId, EditOrderInput input) async {
    final before = await _repo.order(orderId);
    if (!before.canEdit) {
      _refreshOrder(orderId);
      throw const AppException(
        AppErrorKind.validation,
        'This order is no longer a draft, so it cannot be changed. The page now shows its current state.',
      );
    }

    Future<void> attempt() async {
      try {
        await _repo.updateOrder(orderId, input);
      } on AppException catch (e) {
        if (e.kind == AppErrorKind.validation) {
          // Say the order moved on only when it did; any other 400 keeps the
          // server's own words.
          PurchaseOrderDetail? fresh;
          try {
            fresh = await _repo.order(orderId);
          } on AppException {
            fresh = null;
          }
          if (fresh != null && !fresh.canEdit) {
            _refreshOrder(orderId);
            throw const AppException(
              AppErrorKind.validation,
              'This order is no longer a draft, so it cannot be changed. The page now shows its current state.',
            );
          }
        }
        rethrow;
      }
    }

    try {
      await attempt();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await attempt();
    }
    _refreshOrder(orderId);
  }

  /// Cancels an order that has nothing delivered against it, which also frees
  /// the request it came from to be ordered again. A repeat answers 400, so
  /// after a timeout the order is read back: cancelled means it is done.
  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded.
  Future<String?> cancelOrder(String orderId) async {
    void refresh() {
      _refreshOrder(orderId);
      _ref.invalidate(purchaseRequestDetailProvider);
      _refreshLists();
    }

    Future<PurchaseOrderDetail?> reread() async {
      try {
        return await _repo.order(orderId);
      } on AppException {
        return null;
      }
    }

    try {
      await _repo.cancelOrder(orderId);
      refresh();
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        final fresh = await reread();
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        if (fresh.summary.status == PoStatus.cancelled) {
          refresh();
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (fresh.canCancel) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        refresh();
        throw const AppException(AppErrorKind.validation, _orderMovedMessage);
      }
      if (e.kind == AppErrorKind.validation) {
        final fresh = await reread();
        refresh();
        if (fresh != null && fresh.summary.status == PoStatus.cancelled) {
          return 'This order was already cancelled.';
        }
        throw const AppException(AppErrorKind.validation, _orderMovedMessage);
      }
      rethrow;
    }
  }

  /// Records a delivery against an order: the quantities that arrived, by
  /// [OutstandingLine.key]. Returns a note when the outcome needs explaining;
  /// throws when nothing was recorded.
  ///
  /// A delivery adds to stock every time it is sent and the server has no way to
  /// tell a repeat from a second delivery, so it is never resent. The order is
  /// re-read first (what is outstanding is taken from the server as it is now),
  /// and after a timeout it is read back to see whether a delivery of mine
  /// arrived.
  Future<String?> receiveDelivery(
    String orderId, {
    required DateTime date,
    required Map<String, double> received,
    String? notes,
  }) async {
    final startedAt = DateTime.now();
    final me = _ref.read(currentUserIdProvider);
    final before = await _repo.order(orderId);
    if (!before.isReceivable) {
      _refreshOrder(orderId);
      throw const AppException(
        AppErrorKind.validation,
        'This order is no longer waiting for a delivery. The page now shows its current status.',
      );
    }

    final lines = <DeliveryInput>[];
    final entered = <String, double>{};
    final open = before.outstanding.where((l) => !l.isComplete).toList();
    for (final l in open) {
      final got = roundQty(received[l.key] ?? 0);
      if (got < 0 || got > l.outstanding) {
        _refreshOrder(orderId);
        throw const AppException(
          AppErrorKind.validation,
          'More was entered than is still outstanding. A delivery may have been recorded since you opened this. The page now shows what is left.',
        );
      }
      if (got > 0) entered[l.key] = got;
      lines.add(
        DeliveryInput(
          description: l.description,
          materialId: l.materialId,
          outstanding: l.outstanding,
          received: got,
        ),
      );
    }
    final openKeys = open.map((l) => l.key).toSet();
    if (received.entries.any((e) => e.value > 0 && !openKeys.contains(e.key))) {
      _refreshOrder(orderId);
      throw const AppException(AppErrorKind.validation, _orderMovedMessage);
    }
    if (entered.isEmpty) {
      throw const AppException(
        AppErrorKind.validation,
        'Enter how much of at least one item arrived.',
      );
    }

    try {
      await _repo.receiveDelivery(
        orderId,
        date: date,
        lines: lines,
        notes: notes,
      );
      _refreshOrder(orderId);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        PurchaseOrderDetail? fresh;
        try {
          fresh = await _repo.order(orderId);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final known = before.deliveries.map((d) => d.id).toSet();
        final added = fresh.deliveries
            .where((d) => !known.contains(d.id))
            .toList();
        final since = startedAt.subtract(const Duration(minutes: 2));
        final mine = added.any(
          (d) =>
              d.receivedById == me &&
              (d.createdAt ?? startedAt).isAfter(since) &&
              _sameQuantities(d, entered),
        );
        if (mine) {
          _refreshOrder(orderId);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (added.isEmpty) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _refreshOrder(orderId);
        throw const AppException(
          AppErrorKind.validation,
          'Another delivery was recorded on this order while we were checking. Look at its deliveries before trying again.',
        );
      }
      if (e.kind == AppErrorKind.validation) {
        // Say the order moved on only when it did; any other 400 keeps the
        // server's own words.
        PurchaseOrderDetail? fresh;
        try {
          fresh = await _repo.order(orderId);
        } on AppException {
          fresh = null;
        }
        if (fresh != null && !fresh.isReceivable) {
          _refreshOrder(orderId);
          throw const AppException(AppErrorKind.validation, _orderMovedMessage);
        }
      }
      rethrow;
    }
  }

  /// Does [note] hold exactly the quantities in [entered] (by line key)?
  static bool _sameQuantities(DeliveryNote note, Map<String, double> entered) {
    final got = <String, double>{};
    for (final l in note.lines) {
      final key = lineKey(l.materialId, l.description);
      got[key] = roundQty((got[key] ?? 0) + l.received);
    }
    got.removeWhere((_, v) => v <= 0);
    if (got.length != entered.length) return false;
    return entered.entries.every((e) => got[e.key] == e.value);
  }

  /// A delivery changes the order, its lines and the stock of its materials.
  void _refreshOrder(String id) {
    _ref.invalidate(purchaseOrderDetailProvider(id));
    _ref.invalidate(purchaseOrdersProvider);
    _ref.invalidate(materialCatalogProvider);
  }

  void _refreshAfterChange(String id) {
    _ref.invalidate(purchaseRequestDetailProvider(id));
    _refreshLists();
  }

  void _refreshLists() {
    _ref.invalidate(purchaseRequestsProvider);
  }
}

final purchasingActionsProvider = Provider<PurchasingActions>(
  (ref) => PurchasingActions(ref),
);
