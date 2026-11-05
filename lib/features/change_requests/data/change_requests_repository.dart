import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'change_request_models.dart';

/// `/projects/:projectId/change-requests`. Raising, submitting, reviewing,
/// approving, rejecting and implementing. Every write here is a status change
/// the server answers with 400 when repeated, so none is ever resent. Approving
/// also changes the project's budget and end date (see [approve]).
class ChangeRequestsRepository {
  ChangeRequestsRepository(this._api);

  final ApiClient _api;

  /// All of a project's change requests, newest first (one plain array).
  Future<List<ChangeRequestSummary>> list(String projectId) async {
    final body = await _api.get('projects/$projectId/change-requests');
    return J
        .maps(body)
        .map(ChangeRequestSummary.tryParse)
        .whereType<ChangeRequestSummary>()
        .toList();
  }

  /// Raises a change request as a DRAFT. NOT repeatable: a repeat adds another.
  Future<ChangeRequestSummary> create(
    String projectId, {
    required String title,
    required String description,
    required String type,
    List<NewCrItem> items = const [],
  }) async {
    final body = await _api.post(
      'projects/$projectId/change-requests',
      body: {
        'title': title.trim(),
        'description': description.trim(),
        'type': type,
        if (items.isNotEmpty)
          'items': [
            for (final i in items)
              {
                'description': i.description.trim(),
                'quantity': ?i.quantity,
                'unitCost': ?i.unitCost,
              },
          ],
      },
    );
    final created = ChangeRequestSummary.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The change request may have been created.',
      );
    }
    return created;
  }

  /// DRAFT → SUBMITTED. A repeat answers 400.
  Future<void> submit(String projectId, String id) async {
    await _api.post('projects/$projectId/change-requests/$id/submit');
  }

  /// SUBMITTED → UNDER_REVIEW, recording the reviewer and, when given, the
  /// reviewer's own estimate of cost and time.
  Future<void> review(
    String projectId,
    String id, {
    double? estimatedCost,
    int? estimatedDays,
    String? notes,
  }) async {
    await _api.post(
      'projects/$projectId/change-requests/$id/review',
      body: {
        'estimatedCost': ?estimatedCost,
        'estimatedDays': ?estimatedDays,
        if (_has(notes)) 'reviewNotes': notes!.trim(),
      },
    );
  }

  /// UNDER_REVIEW → APPROVED. Inside one server transaction an approved cost
  /// above zero is ADDED to the project's baseline budget and approved days
  /// above zero push its end date later. Not undoable from the app.
  Future<void> approve(
    String projectId,
    String id, {
    double? approvedCost,
    int? approvedDays,
    String? notes,
  }) async {
    await _api.post(
      'projects/$projectId/change-requests/$id/approve',
      body: {
        'approvedCost': ?approvedCost,
        'approvedDays': ?approvedDays,
        if (_has(notes)) 'approvalNotes': notes!.trim(),
      },
    );
  }

  /// → REJECTED, with the reason the requester will read.
  Future<void> reject(
    String projectId,
    String id, {
    required String notes,
  }) async {
    await _api.post(
      'projects/$projectId/change-requests/$id/reject',
      body: {'rejectionNotes': notes.trim()},
    );
  }

  /// APPROVED → IMPLEMENTED.
  Future<void> implement(String projectId, String id) async {
    await _api.post('projects/$projectId/change-requests/$id/implement');
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  Future<ChangeRequestDetail> get(String projectId, String id) async {
    final d = ChangeRequestDetail.tryParse(
      await _api.get('projects/$projectId/change-requests/$id'),
    );
    if (d == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected change request response.',
      );
    }
    return d;
  }
}
