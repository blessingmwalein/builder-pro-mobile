import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'approval_models.dart';

/// Time approval over `/time-tracking`. Needs `timesheets.*`: without it the
/// list endpoint only returns the caller's own entries.
class ApprovalsRepository {
  ApprovalsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 50;

  /// Entries waiting for a decision, newest first. NO `workerId` is sent: the
  /// point is to see everyone's. `page` and `limit` are always sent.
  Future<ApprovalPage> pending({int page = 1}) async {
    final body = await _api.get(
      'time-tracking',
      query: {'page': page, 'limit': pageSize, 'status': 'PENDING'},
    );
    final paged = J.paged(body);
    return ApprovalPage(
      paged.items
          .map(ApprovalEntry.tryParse)
          .whereType<ApprovalEntry>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
      total: paged.total,
    );
  }

  /// `PUT /time-tracking/:id/approve`. Setting a status is idempotent, so it is
  /// safe to repeat after an uncertain failure. The server answers 400 for an
  /// entry that is still clocked in.
  Future<void> decide(
    String id, {
    required bool approve,
    String? comment,
  }) async {
    await _api.put(
      'time-tracking/$id/approve',
      body: {
        'status': approve ? 'APPROVED' : 'REJECTED',
        if (comment != null && comment.trim().isNotEmpty)
          'approvalComment': comment.trim(),
      },
    );
  }
}
