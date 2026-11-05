import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'request_models.dart';

/// `/approvals`: multi-step requests (purchase orders, change requests…).
/// The app reads only the requests waiting for the signed-in user.
class RequestsRepository {
  RequestsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /approvals?myPending=true`. Without `myPending` the API returns every
  /// request in the company, so it is always sent.
  Future<PageResult<ApprovalRequest>> mine({int page = 1}) async {
    final body = await _api.get(
      'approvals',
      query: {'page': page, 'limit': pageSize, 'myPending': 'true'},
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(ApprovalRequest.tryParse)
          .whereType<ApprovalRequest>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// `GET /approvals/pending/count`.
  Future<int> pendingCount() async {
    final body = await _api.get('approvals/pending/count');
    return J.integer(J.map(body)['count']) ?? 0;
  }

  Future<ApprovalRequest> get(String id) async {
    final r = ApprovalRequest.tryParse(await _api.get('approvals/$id'));
    if (r == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected response.',
      );
    }
    return r;
  }

  /// `POST /approvals/:id/steps/:stepId/decide`. NOT repeatable: a second try on
  /// a decided step answers 400, so callers reconcile with [get] after an
  /// uncertain failure.
  Future<void> decide(
    String requestId,
    String stepId, {
    required bool approve,
    String? comment,
  }) async {
    await _api.post(
      'approvals/$requestId/steps/$stepId/decide',
      body: {
        'decision': approve ? 'APPROVED' : 'REJECTED',
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
    );
  }
}
