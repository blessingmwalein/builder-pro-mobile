import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'equipment_models.dart';

/// `/equipment/*`.
///
/// Assigning and returning cannot be repeated blindly: the server checks the
/// item's status (so a repeat answers 400), but a stale return could close the
/// wrong assignment. Callers re-read the item before returning and reconcile
/// with a read after an uncertain failure.
class EquipmentRepository {
  EquipmentRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  Future<PageResult<EquipmentSummary>> list({
    String? status,
    int page = 1,
  }) async {
    final body = await _api.get(
      'equipment',
      query: {'page': page, 'limit': pageSize, 'status': status},
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(EquipmentSummary.tryParse)
          .whereType<EquipmentSummary>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// The company's equipment categories, by name.
  Future<List<EquipmentCategory>> categories() async {
    final body = await _api.get('equipment/categories');
    return J
        .maps(body)
        .map(EquipmentCategory.tryParse)
        .whereType<EquipmentCategory>()
        .toList();
  }

  /// Adds a piece of equipment (AVAILABLE). NOT repeatable: a repeat adds
  /// another. Costs are never sent.
  Future<EquipmentSummary> create({
    required String name,
    String? description,
    String? serialNumber,
    String? categoryId,
  }) async {
    final body = await _api.post(
      'equipment',
      body: {
        'name': name.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (serialNumber != null && serialNumber.trim().isNotEmpty)
          'serialNumber': serialNumber.trim(),
        'categoryId': ?categoryId,
      },
    );
    final created = EquipmentSummary.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The equipment may have been added.',
      );
    }
    return created;
  }

  /// Sets the details of an item (all four are sent, so a blank clears it). It
  /// only sets fields, so it may be sent once more after an uncertain failure.
  Future<void> updateDetails(
    String id, {
    required String name,
    String? description,
    String? serialNumber,
    String? categoryId,
  }) async {
    String? blankToNull(String? v) =>
        v == null || v.trim().isEmpty ? null : v.trim();
    await _api.patch(
      'equipment/$id',
      body: {
        'name': name.trim(),
        'description': blankToNull(description),
        'serialNumber': blankToNull(serialNumber),
        'categoryId': categoryId,
      },
    );
  }

  /// Sets the status. Only a plain set, so it may be sent once more.
  Future<void> setStatus(String id, String status) async {
    await _api.patch('equipment/$id', body: {'status': status});
  }

  Future<EquipmentDetail> get(String id) async {
    final d = EquipmentDetail.tryParse(await _api.get('equipment/$id'));
    if (d == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected equipment response.',
      );
    }
    return d;
  }

  /// Assigns an available item to a project. The dates are calendar days, sent
  /// as `yyyy-MM-dd` like the web app does.
  Future<void> assign(
    String id, {
    required String projectId,
    required DateTime start,
    DateTime? end,
    String? notes,
  }) async {
    await _api.post(
      'equipment/$id/allocate',
      body: {
        'projectId': projectId,
        'startDate': Fmt.isoDay(start),
        if (end != null) 'endDate': Fmt.isoDay(end),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  /// Marks one assignment returned and the item available.
  Future<void> returnItem(String id, String assignmentId) async {
    await _api.post('equipment/$id/return/$assignmentId');
  }
}
