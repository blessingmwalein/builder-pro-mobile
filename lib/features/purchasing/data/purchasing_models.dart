import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

String _personName(Object? raw) {
  final m = J.map(raw);
  return '${J.strOr(m['firstName'])} ${J.strOr(m['lastName'])}'.trim();
}

/// Purchase order statuses the backend uses.
abstract final class PoStatus {
  static const draft = 'DRAFT';
  static const sent = 'SENT';
  static const partial = 'PARTIAL';
  static const received = 'RECEIVED';
  static const cancelled = 'CANCELLED';
}

/// Purchase request statuses the backend uses.
abstract final class PrStatus {
  static const draft = 'DRAFT';
  static const submitted = 'SUBMITTED';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const ordered = 'ORDERED';
}

@immutable
class PrItem {
  const PrItem({
    required this.description,
    required this.quantity,
    required this.unit,
    this.estimatedUnitCost,
    this.materialName,
    this.materialId,
  });

  final String description;
  final double quantity;
  final String unit;
  final double? estimatedUnitCost;
  final String? materialName;

  /// The catalog material this line is for, when it has one. It travels on to
  /// the purchase order so a delivery adds to that material's stock.
  final String? materialId;

  /// Quantity × estimated unit cost, when the cost was entered.
  double? get estimatedTotal =>
      estimatedUnitCost == null ? null : quantity * estimatedUnitCost!;

  static PrItem? tryParse(Map<String, dynamic> m) {
    final description = J.str(m['description']);
    if (description == null) return null;
    return PrItem(
      description: description,
      quantity: J.number(m['quantity']) ?? 0,
      unit: J.strOr(m['unit']),
      estimatedUnitCost: J.number(m['estimatedUnitCost']),
      materialName: J.str(J.map(m['material'])['name']),
      materialId: J.str(m['materialId']) ?? J.str(J.map(m['material'])['id']),
    );
  }
}

@immutable
class OrderRef {
  const OrderRef({
    required this.id,
    required this.number,
    required this.status,
    required this.total,
  });
  final String id;
  final String number;
  final String status;
  final double total;

  static OrderRef? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return OrderRef(
      id: id,
      number: J.strOr(m['poNumber'], 'Order'),
      status: J.strOr(m['status'], 'DRAFT'),
      total: J.number(m['totalAmount']) ?? 0,
    );
  }
}

@immutable
class PurchaseRequestSummary {
  const PurchaseRequestSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.requestedBy,
    required this.requestedById,
    required this.createdAt,
    this.projectName,
    this.approvedBy,
    this.notes,
    this.itemCount = 0,
    this.orderCount = 0,
  });

  final String id;
  final String number;
  final String status;
  final String requestedBy;
  final String requestedById;
  final DateTime createdAt;
  final String? projectName;
  final String? approvedBy;
  final String? notes;
  final int itemCount;
  final int orderCount;

  bool get isDraft => status == PrStatus.draft;
  bool get isSubmitted => status == PrStatus.submitted;

  static PurchaseRequestSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final requester = J.map(m['requestedBy']);
    final count = J.map(m['_count']);
    final requestedBy = _personName(requester);
    final approved = _personName(m['approvedBy']);
    return PurchaseRequestSummary(
      id: id,
      number: J.strOr(m['prNumber'], 'Request'),
      status: J.strOr(m['status'], PrStatus.draft),
      requestedBy: requestedBy.isEmpty ? 'A colleague' : requestedBy,
      requestedById: J.strOr(m['requestedById'], J.strOr(requester['id'])),
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      projectName: J.str(J.map(m['project'])['name']),
      approvedBy: approved.isEmpty ? null : approved,
      notes: J.str(m['notes']),
      itemCount: J.integer(count['items']) ?? J.list(m['items']).length,
      orderCount: J.integer(count['orders']) ?? J.list(m['orders']).length,
    );
  }
}

@immutable
class PurchaseRequestDetail {
  const PurchaseRequestDetail({
    required this.summary,
    required this.items,
    required this.orders,
    this.approvedAt,
    this.rejectedAt,
  });

  final PurchaseRequestSummary summary;
  final List<PrItem> items;
  final List<OrderRef> orders;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  /// Sum of quantity × estimated cost over the items that have a cost.
  double get estimatedTotal =>
      items.fold(0.0, (s, i) => s + (i.estimatedTotal ?? 0));

  /// True when every item has an estimated cost, so [estimatedTotal] is complete.
  bool get estimateComplete =>
      items.isNotEmpty && items.every((i) => i.estimatedUnitCost != null);

  static PurchaseRequestDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = PurchaseRequestSummary.tryParse(m);
    if (summary == null) return null;
    return PurchaseRequestDetail(
      summary: summary,
      items: J
          .maps(m['items'])
          .map(PrItem.tryParse)
          .whereType<PrItem>()
          .toList(),
      orders: J
          .maps(m['orders'])
          .map(OrderRef.tryParse)
          .whereType<OrderRef>()
          .toList(),
      approvedAt: J.date(m['approvedAt']),
      rejectedAt: J.date(m['rejectedAt']),
    );
  }
}

@immutable
class PurchaseOrderSummary {
  const PurchaseOrderSummary({
    required this.id,
    required this.number,
    required this.status,
    required this.supplierName,
    required this.total,
    required this.createdAt,
    this.supplierId,
    this.expectedDelivery,
    this.itemCount = 0,
  });

  final String id;
  final String number;
  final String status;
  final String supplierName;
  final String? supplierId;
  final double total;
  final DateTime createdAt;
  final DateTime? expectedDelivery;
  final int itemCount;

  static PurchaseOrderSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final count = J.map(m['_count']);
    return PurchaseOrderSummary(
      id: id,
      number: J.strOr(m['poNumber'], 'Order'),
      status: J.strOr(m['status'], 'DRAFT'),
      supplierName: J.strOr(J.map(m['supplier'])['name'], 'Supplier'),
      supplierId: J.str(m['supplierId']) ?? J.str(J.map(m['supplier'])['id']),
      total: J.number(m['totalAmount']) ?? 0,
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      expectedDelivery: J.date(m['expectedDelivery']),
      itemCount: J.integer(count['items']) ?? J.list(m['items']).length,
    );
  }
}

@immutable
class PoItem {
  const PoItem({
    required this.description,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    this.materialId,
    this.unit = '',
  });
  final String description;
  final double quantity;
  final double unitCost;
  final double totalCost;

  /// The catalogue material this line is for, when it has one. Receiving a
  /// delivery adds to the stock of that material only.
  final String? materialId;
  final String unit;

  static PoItem? tryParse(Map<String, dynamic> m) {
    final description = J.str(m['description']);
    if (description == null) return null;
    final material = J.map(m['material']);
    return PoItem(
      description: description,
      quantity: J.number(m['quantity']) ?? 0,
      unitCost: J.number(m['unitCost']) ?? 0,
      totalCost: J.number(m['totalCost']) ?? 0,
      materialId: J.str(m['materialId']) ?? J.str(material['id']),
      unit: J.strOr(material['unit']),
    );
  }
}

/// Delivery quantities are kept to three decimals; this removes the float noise
/// that subtracting them leaves behind.
double roundQty(double v) => (v * 1000).round() / 1000;

/// One line of a recorded delivery.
@immutable
class DeliveryLine {
  const DeliveryLine({
    required this.description,
    required this.ordered,
    required this.received,
    this.materialId,
  });
  final String description;
  final double ordered;
  final double received;
  final String? materialId;

  static DeliveryLine? tryParse(Map<String, dynamic> m) {
    final description = J.str(m['description']);
    if (description == null) return null;
    return DeliveryLine(
      description: description,
      ordered: J.number(m['quantityOrdered']) ?? 0,
      received: J.number(m['quantityReceived']) ?? 0,
      materialId: J.str(m['materialId']),
    );
  }
}

/// A delivery recorded against an order.
@immutable
class DeliveryNote {
  const DeliveryNote({
    required this.id,
    required this.lines,
    required this.receivedById,
    this.deliveryDate,
    this.createdAt,
    this.notes,
  });
  final String id;
  final List<DeliveryLine> lines;
  final String receivedById;

  /// A calendar day (UTC midnight); show it with `Fmt.calendarDay`.
  final DateTime? deliveryDate;
  final DateTime? createdAt;
  final String? notes;

  static DeliveryNote? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    return DeliveryNote(
      id: id,
      receivedById: J.strOr(m['receivedById']),
      deliveryDate: J.date(m['deliveryDate']),
      createdAt: J.date(m['createdAt']),
      notes: J.str(m['notes']),
      lines: J
          .maps(m['items'])
          .map(DeliveryLine.tryParse)
          .whereType<DeliveryLine>()
          .toList(),
    );
  }
}

/// What an order still expects of one item: what was ordered, what earlier
/// deliveries brought, and what is left. Lines are matched to deliveries by
/// material (or, for a line with no material, by its description), because that
/// is all a delivery line carries.
@immutable
class OutstandingLine {
  const OutstandingLine({
    required this.key,
    required this.description,
    required this.unit,
    required this.ordered,
    required this.received,
    this.materialId,
  });
  final String key;
  final String description;
  final String unit;
  final double ordered;
  final double received;
  final String? materialId;

  double get outstanding => roundQty((ordered - received).clamp(0, ordered));
  bool get isComplete => outstanding <= 0;
}

String lineKey(String? materialId, String description) =>
    materialId != null && materialId.isNotEmpty
    ? 'm:$materialId'
    : 't:${description.trim().toLowerCase()}';

@immutable
class PurchaseOrderDetail {
  const PurchaseOrderDetail({
    required this.summary,
    required this.items,
    required this.deliveries,
    this.requestNumber,
    this.requestId,
    this.notes,
    this.deliveredAt,
  });

  final PurchaseOrderSummary summary;
  final List<PoItem> items;
  final List<DeliveryNote> deliveries;
  final String? requestNumber;
  final String? requestId;
  final String? notes;
  final DateTime? deliveredAt;

  int get deliveryCount => deliveries.length;

  /// An order can take a delivery once it has been sent, until it is complete.
  bool get isReceivable =>
      summary.status == PoStatus.sent || summary.status == PoStatus.partial;

  /// Only a draft can be changed: once it is sent the supplier has it.
  bool get canEdit => summary.status == PoStatus.draft;

  /// A draft, or a sent order that nothing has been delivered against.
  bool get canCancel =>
      (summary.status == PoStatus.draft || summary.status == PoStatus.sent) &&
      deliveries.isEmpty;

  /// Per item, what is still expected, after the deliveries already recorded.
  /// Two lines for the same material (or the same wording) are one item here.
  List<OutstandingLine> get outstanding {
    final ordered = <String, double>{};
    final first = <String, PoItem>{};
    for (final i in items) {
      final key = lineKey(i.materialId, i.description);
      ordered[key] = (ordered[key] ?? 0) + i.quantity;
      first.putIfAbsent(key, () => i);
    }
    final received = <String, double>{};
    for (final d in deliveries) {
      for (final l in d.lines) {
        final key = lineKey(l.materialId, l.description);
        received[key] = (received[key] ?? 0) + l.received;
      }
    }
    return [
      for (final e in ordered.entries)
        OutstandingLine(
          key: e.key,
          description: first[e.key]!.description,
          unit: first[e.key]!.unit,
          materialId: first[e.key]!.materialId,
          ordered: roundQty(e.value),
          received: roundQty(received[e.key] ?? 0),
        ),
    ];
  }

  /// True when something is still expected.
  bool get hasOutstanding => outstanding.any((l) => !l.isComplete);

  static PurchaseOrderDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = PurchaseOrderSummary.tryParse(m);
    if (summary == null) return null;
    final pr = J.map(m['purchaseRequest']);
    return PurchaseOrderDetail(
      summary: summary,
      items: J
          .maps(m['items'])
          .map(PoItem.tryParse)
          .whereType<PoItem>()
          .toList(),
      deliveries: J
          .maps(m['deliveryNotes'])
          .map(DeliveryNote.tryParse)
          .whereType<DeliveryNote>()
          .toList(),
      requestNumber: J.str(pr['prNumber']),
      requestId: J.str(pr['id']),
      notes: J.str(m['notes']),
      deliveredAt: J.date(m['deliveredAt']),
    );
  }
}

/// One line on the "new purchase request" form, as it is sent.
@immutable
class NewPrItem {
  const NewPrItem({
    required this.description,
    required this.quantity,
    required this.unit,
    this.estimatedUnitCost,
    this.materialId,
  });
  final String description;
  final double quantity;
  final String unit;
  final double? estimatedUnitCost;

  /// The catalog material this line is for, when chosen from the catalog.
  final String? materialId;
}

/// One line of a new purchase order.
@immutable
class NewPoItem {
  const NewPoItem({
    required this.description,
    required this.quantity,
    required this.unitCost,
    this.materialId,
  });
  final String description;
  final double quantity;
  final double unitCost;

  /// The catalog material, so a delivery adds to its stock.
  final String? materialId;
}

/// What the person typed to change a draft order. It is the whole order as it
/// should now be: the server replaces the lines with these, so sending it twice
/// leaves the same order.
@immutable
class EditOrderInput {
  const EditOrderInput({
    required this.supplierId,
    required this.items,
    this.expectedDelivery,
    this.notes,
  });
  final String supplierId;
  final List<NewPoItem> items;

  /// Null clears the date.
  final DateTime? expectedDelivery;

  /// Null or blank clears the notes.
  final String? notes;

  double get total => items.fold(0.0, (s, i) => s + i.quantity * i.unitCost);
}

/// What the person typed to turn an approved request into an order.
@immutable
class NewOrderInput {
  const NewOrderInput({
    required this.requestId,
    required this.supplierId,
    required this.items,
    this.expectedDelivery,
    this.notes,
  });
  final String requestId;
  final String supplierId;
  final List<NewPoItem> items;
  final DateTime? expectedDelivery;
  final String? notes;

  double get total => items.fold(0.0, (s, i) => s + i.quantity * i.unitCost);
}
