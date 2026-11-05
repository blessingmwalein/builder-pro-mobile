import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// One line of a purchase being recorded.
@immutable
class PurchaseLineInput {
  const PurchaseLineInput({
    required this.materialId,
    required this.quantity,
    required this.unitCost,
  });
  final String materialId;
  final double quantity;
  final double unitCost;
}

/// What the person typed to record material bought straight from a supplier,
/// with no purchase order. [purchasedAt] is kept to the millisecond: it is how a
/// purchase that got no answer is found again before anything is sent twice.
@immutable
class NewPurchaseInput {
  const NewPurchaseInput({
    required this.supplierId,
    required this.items,
    required this.purchasedAt,
    this.projectId,
    this.purchaseNumber,
    this.notes,
  });
  final String supplierId;
  final List<PurchaseLineInput> items;
  final DateTime purchasedAt;
  final String? projectId;

  /// The supplier's invoice or receipt number.
  final String? purchaseNumber;
  final String? notes;

  double get total => items.fold(0.0, (s, i) => s + i.quantity * i.unitCost);
}

/// One material on a recorded purchase.
@immutable
class PurchaseLine {
  const PurchaseLine({
    required this.materialName,
    required this.unit,
    required this.quantity,
    required this.unitCost,
  });
  final String materialName;
  final String unit;
  final double quantity;
  final double unitCost;

  double get total => quantity * unitCost;
}

/// A purchase recorded against stock: `GET /materials/purchases/list`.
@immutable
class MaterialPurchase {
  const MaterialPurchase({
    required this.id,
    required this.purchasedAt,
    required this.total,
    required this.lines,
    this.number,
    this.supplierId,
    this.supplierName,
    this.projectId,
    this.projectName,
    this.notes,
  });

  final String id;
  final DateTime purchasedAt;
  final double total;
  final List<PurchaseLine> lines;
  final String? number;
  final String? supplierId;
  final String? supplierName;
  final String? projectId;
  final String? projectName;
  final String? notes;

  /// Whether this is the purchase [input] made. The exact moment (to the
  /// millisecond) and the total are what tell it apart from any other.
  bool isSameAs(NewPurchaseInput input) =>
      purchasedAt.toUtc().millisecondsSinceEpoch ==
          input.purchasedAt.toUtc().millisecondsSinceEpoch &&
      (total - input.total).abs() < 0.005 &&
      (supplierId == null || supplierId == input.supplierId);

  static MaterialPurchase? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final purchasedAt = J.date(m['purchasedAt']);
    if (id == null || purchasedAt == null) return null;
    final supplier = J.map(m['supplier']);
    final project = J.map(m['project']);
    return MaterialPurchase(
      id: id,
      purchasedAt: purchasedAt,
      total: J.number(m['totalAmount']) ?? 0,
      number: J.str(m['purchaseNumber']),
      supplierId: J.str(m['supplierId']) ?? J.str(supplier['id']),
      supplierName: J.str(supplier['name']),
      projectId: J.str(m['projectId']) ?? J.str(project['id']),
      projectName: J.str(project['name']),
      notes: J.str(m['notes']),
      lines: J.maps(m['logs']).map((l) {
        final material = J.map(l['material']);
        return PurchaseLine(
          materialName: J.strOr(material['name'], 'Material'),
          unit: J.strOr(material['unit']),
          quantity: J.number(l['quantity']) ?? 0,
          unitCost: J.number(l['unitCost']) ?? 0,
        );
      }).toList(),
    );
  }
}
