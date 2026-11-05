import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/permissions/feature_permissions.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../finance/application/finance_providers.dart';
import '../../purchasing/application/purchasing_providers.dart';
import '../../../shared/state/paged_catalog.dart';
import '../data/request_models.dart';
import '../data/requests_repository.dart';

final requestsRepositoryProvider = Provider<RequestsRepository>(
  (ref) => RequestsRepository(ref.watch(apiClientProvider)),
);

/// How many requests wait for the signed-in user.
final pendingRequestCountProvider = FutureProvider.autoDispose<int>((ref) {
  ref.watch(currentUserIdProvider);
  ref.watch(appResumeProvider);
  return ref.watch(requestsRepositoryProvider).pendingCount();
});

/// Requests waiting for the signed-in user's decision.
class RequestsCatalog extends PagedCatalog<ApprovalRequest> {
  @override
  Future<PageResult<ApprovalRequest>> fetch({String? filter, int page = 1}) =>
      ref.read(requestsRepositoryProvider).mine(page: page);

  @override
  String idOf(ApprovalRequest item) => item.id;

  /// Deciding a purchase request or order here also moves that record on the
  /// server (the approvals engine sets its status), so the purchasing screens
  /// must not keep showing it as it was.
  void _purchasingMoved(ApprovalRequest request) {
    if (!request.entityType.startsWith('PROCUREMENT_')) return;
    ref.invalidate(purchaseRequestsProvider);
    ref.invalidate(purchaseOrdersProvider);
    ref.invalidate(purchaseRequestDetailProvider);
    ref.invalidate(purchaseOrderDetailProvider);
  }

  /// Approves or rejects the signed-in user's step on [request]. Returns a note
  /// when the outcome needs explaining; throws when nothing was recorded.
  ///
  /// A decision cannot be sent twice (the second try answers 400), so after a
  /// timeout the request is read back and the user's own step is checked.
  Future<String?> decide(
    ApprovalRequest request, {
    required bool approve,
    String? comment,
  }) async {
    final me = ref.read(currentUserIdProvider);
    final step = me == null ? null : request.pendingStepFor(me);
    if (step == null) {
      removeById(request.id);
      throw const AppException(
        AppErrorKind.validation,
        'This request is no longer waiting for you.',
      );
    }
    final repo = ref.read(requestsRepositoryProvider);
    final wanted = approve ? 'APPROVED' : 'REJECTED';
    try {
      await repo.decide(
        request.id,
        step.id,
        approve: approve,
        comment: comment,
      );
      removeById(request.id);
      ref.invalidate(pendingRequestCountProvider);
      _purchasingMoved(request);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        ApprovalRequest? fresh;
        try {
          fresh = await repo.get(request.id);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final mine = fresh.stepById(step.id);
        if (mine != null && mine.status == wanted) {
          removeById(request.id);
          ref.invalidate(pendingRequestCountProvider);
          _purchasingMoved(request);
          return 'Your decision was recorded. The confirmation was slow, so we checked.';
        }
        if (mine != null && mine.isPending && fresh.status == 'PENDING') {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        removeById(request.id);
        ref.invalidate(pendingRequestCountProvider);
        _purchasingMoved(request);
        return 'This request has already been decided.';
      }
      if (e.kind == AppErrorKind.validation) {
        // Already decided (by you elsewhere, or the request was withdrawn).
        await refresh();
        ref.invalidate(pendingRequestCountProvider);
        throw AppException(AppErrorKind.validation, e.message);
      }
      rethrow;
    }
  }
}

final requestsCatalogProvider =
    NotifierProvider<RequestsCatalog, PagedState<ApprovalRequest>>(
      RequestsCatalog.new,
    );

/// What a request is actually about, in one line, when the app is allowed to
/// look it up: purchase requests and purchase orders (the approvals API itself
/// carries only a type and an id). Null for everything else, for users without
/// purchasing access, and whenever the lookup fails, so the card falls back to
/// "who asked and any note" and never shows a guess.
final requestContextProvider = FutureProvider.autoDispose
    .family<String?, ({String type, String id})>((ref, key) async {
      if (!ref.watch(permissionsProvider).hasAny(Feature.purchasingView)) {
        return null;
      }
      final repo = ref.watch(purchasingRepositoryProvider);
      final currency = ref.watch(currencyProvider);
      try {
        switch (key.type) {
          case 'PROCUREMENT_PR':
            final d = await repo.request(key.id);
            final n = d.items.length;
            return [
              '$n ${n == 1 ? 'item' : 'items'}',
              if (d.estimatedTotal > 0)
                '${d.estimateComplete ? '' : 'at least '}${Fmt.money(d.estimatedTotal, currency)} estimated',
              if (d.summary.projectName != null) d.summary.projectName!,
            ].join(' · ');
          case 'PROCUREMENT_PO':
            final d = await repo.order(key.id);
            final n = d.items.length;
            return [
              d.summary.supplierName,
              Fmt.money(d.summary.total, currency),
              '$n ${n == 1 ? 'item' : 'items'}',
            ].join(' · ');
          default:
            return null;
        }
      } on AppException {
        return null;
      }
    });
