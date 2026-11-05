import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'purchasing_models.dart';

/// One line of a delivery being recorded.
class DeliveryInput {
  const DeliveryInput({
    required this.description,
    required this.outstanding,
    required this.received,
    this.materialId,
  });
  final String description;
  final String? materialId;

  /// What the order still expects of this item (sent as the ordered quantity).
  final double outstanding;

  /// What arrived now.
  final double received;
}

/// `/procurement/*`: purchase requests and orders.
///
/// Create, submit, approve and reject cannot be repeated (create makes another
/// request; the others answer 400 the second time), so callers reconcile with a
/// read after an uncertain failure.
class PurchasingRepository {
  PurchasingRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  Future<PageResult<PurchaseRequestSummary>> requests({
    String? status,
    String? projectId,
    int page = 1,
  }) async {
    final body = await _api.get(
      'procurement/purchase-requests',
      query: {
        'page': page,
        'limit': pageSize,
        'status': status,
        'projectId': projectId,
      },
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(PurchaseRequestSummary.tryParse)
          .whereType<PurchaseRequestSummary>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  Future<PurchaseRequestDetail> request(String id) async {
    final d = PurchaseRequestDetail.tryParse(
      await _api.get('procurement/purchase-requests/$id'),
    );
    if (d == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected purchase request response.',
      );
    }
    return d;
  }

  /// Creates a DRAFT request. NOT repeatable.
  Future<PurchaseRequestSummary> createRequest({
    required List<NewPrItem> items,
    String? projectId,
    String? notes,
  }) async {
    final body = await _api.post(
      'procurement/purchase-requests',
      body: {
        'projectId': ?projectId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'items': [
          for (final i in items)
            {
              'description': i.description,
              'materialId': ?i.materialId,
              'quantity': i.quantity,
              'unit': i.unit,
              'estimatedUnitCost': ?i.estimatedUnitCost,
            },
        ],
      },
    );
    final created = PurchaseRequestSummary.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The request may have been created.',
      );
    }
    return created;
  }

  Future<void> submit(String id) async {
    await _api.post('procurement/purchase-requests/$id/submit');
  }

  Future<void> approve(String id) async {
    await _api.post('procurement/purchase-requests/$id/approve');
  }

  /// DRAFT → SENT. Only changes the status: the server sends nothing to the
  /// supplier. A repeat answers 400 ("only DRAFT orders can be sent").
  Future<void> sendOrder(String id) async {
    await _api.post('procurement/purchase-orders/$id/send');
  }

  /// Rejecting overwrites the request's own notes with [notes] on the server
  /// (backend-gaps G31), so the reason is also kept in the confirmation.
  Future<void> reject(String id, {String? notes}) async {
    await _api.post(
      'procurement/purchase-requests/$id/reject',
      body: {
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  Future<PageResult<PurchaseOrderSummary>> orders({
    String? status,
    int page = 1,
  }) async {
    final body = await _api.get(
      'procurement/purchase-orders',
      query: {'page': page, 'limit': pageSize, 'status': status},
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items
          .map(PurchaseOrderSummary.tryParse)
          .whereType<PurchaseOrderSummary>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// Records a delivery. NOT repeatable: every call adds the received quantities
  /// to stock again and makes another delivery note.
  ///
  /// The server decides "received in full" from the lines it is sent (the total
  /// received against the total ordered *in this request*), so every line still
  /// outstanding must be included, with what was received now (possibly 0) and
  /// what is outstanding as the ordered quantity.
  Future<void> receiveDelivery(
    String orderId, {
    required DateTime date,
    required List<DeliveryInput> lines,
    String? notes,
  }) async {
    await _api.post(
      'procurement/purchase-orders/$orderId/deliver',
      body: {
        'deliveryDate': Fmt.isoDay(date),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'items': [
          for (final l in lines)
            {
              'description': l.description,
              'materialId': ?l.materialId,
              'quantityOrdered': l.outstanding,
              'quantityReceived': l.received,
            },
        ],
      },
    );
  }

  /// `POST /procurement/purchase-orders` (needs `materials.manage`). Makes a
  /// DRAFT order from an APPROVED request, which then becomes ORDERED, so a
  /// second call answers 400. Nothing is sent to the supplier.
  Future<PurchaseOrderSummary> createOrder(NewOrderInput input) async {
    final body = await _api.post(
      'procurement/purchase-orders',
      body: {
        'supplierId': input.supplierId,
        'purchaseRequestId': input.requestId,
        if (input.expectedDelivery != null)
          'expectedDelivery': input.expectedDelivery!.toUtc().toIso8601String(),
        if (input.notes != null && input.notes!.trim().isNotEmpty)
          'notes': input.notes!.trim(),
        'items': [
          for (final i in input.items)
            {
              'description': i.description,
              'materialId': ?i.materialId,
              'quantity': i.quantity,
              'unitCost': i.unitCost,
            },
        ],
      },
    );
    final created = PurchaseOrderSummary.tryParse(body);
    if (created == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The order may have been created.',
      );
    }
    return created;
  }

  /// `PUT /procurement/purchase-orders/:id` (needs `materials.manage`; a draft
  /// only). Sets the supplier, date, notes and every line, so it is safe to
  /// repeat. A null date or blank notes clears them.
  Future<void> updateOrder(String id, EditOrderInput input) async {
    final notes = input.notes?.trim();
    await _api.put(
      'procurement/purchase-orders/$id',
      body: {
        'supplierId': input.supplierId,
        'expectedDelivery': input.expectedDelivery?.toUtc().toIso8601String(),
        'notes': notes == null || notes.isEmpty ? null : notes,
        'items': [
          for (final i in input.items)
            {
              'description': i.description,
              'materialId': ?i.materialId,
              'quantity': i.quantity,
              'unitCost': i.unitCost,
            },
        ],
      },
    );
  }

  /// `POST /procurement/purchase-orders/:id/cancel` (needs `materials.manage`).
  /// A draft, or a sent order with no delivery recorded. The request it came
  /// from goes back to Approved. A repeat answers 400 (already cancelled).
  Future<void> cancelOrder(String id) async {
    await _api.post('procurement/purchase-orders/$id/cancel');
  }

  Future<PurchaseOrderDetail> order(String id) async {
    final d = PurchaseOrderDetail.tryParse(
      await _api.get('procurement/purchase-orders/$id'),
    );
    if (d == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected purchase order response.',
      );
    }
    return d;
  }
}
