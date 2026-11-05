import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// A catalog item. Stock and cost arrive as strings (Prisma decimals).
@immutable
class MaterialItem {
  const MaterialItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.unitCost,
    required this.stockOnHand,
    this.sku,
    this.category,
    this.categoryId,
    this.supplierName,
    this.supplierId,
    this.reorderAt,
    this.description,
  });

  final String id;
  final String name;
  final String unit;
  final double unitCost;
  final double stockOnHand;
  final String? sku;
  final String? category;
  final String? categoryId;
  final String? supplierName;
  final String? supplierId;

  /// Stock level at which it is time to order more.
  final double? reorderAt;
  final String? description;

  /// At or below its reorder level (when one is set).
  bool get isLow => reorderAt != null && stockOnHand <= reorderAt!;

  /// The shape the API sends, so [tryParse] reads the saved copy back.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit,
    'unitCost': unitCost,
    'stockOnHand': stockOnHand,
    'sku': sku,
    'category': category,
    'categoryId': categoryId,
    'supplierId': supplierId,
    'reorderAt': reorderAt,
    'description': description,
    if (supplierName != null)
      'supplier': {'id': supplierId, 'name': supplierName},
  };

  /// Whether this item matches what was typed in the search box.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [
      name,
      sku,
      category,
    ].whereType<String>().any((s) => s.toLowerCase().contains(q));
  }

  static MaterialItem? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final categoryRef = J.map(m['categoryRef']);
    return MaterialItem(
      id: id,
      name: J.strOr(m['name'], 'Material'),
      unit: J.strOr(m['unit']),
      unitCost: J.number(m['unitCost']) ?? 0,
      stockOnHand: J.number(m['stockOnHand']) ?? 0,
      sku: J.str(m['sku']),
      category: J.str(categoryRef['name']) ?? J.str(m['category']),
      categoryId: J.str(m['categoryId']) ?? J.str(categoryRef['id']),
      supplierName: J.str(J.map(m['supplier'])['name']),
      supplierId: J.str(m['supplierId']) ?? J.str(J.map(m['supplier'])['id']),
      reorderAt: J.number(m['reorderAt']),
      description: J.str(m['description']),
    );
  }
}

/// A usage log the worker just recorded (the log has no user field, so the app
/// only lists what was recorded on this device).
@immutable
class MaterialLogEntry {
  const MaterialLogEntry({
    required this.id,
    required this.materialId,
    required this.materialName,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.projectId,
    required this.projectName,
    required this.usedAt,
    this.notes,
  });

  final String id;
  final String materialId;
  final String materialName;
  final String unit;
  final double quantity;
  final double unitCost;
  final String projectId;
  final String projectName;
  final DateTime usedAt;
  final String? notes;

  /// Reads a server log (`POST /materials/usage` reply or a `GET /materials/logs`
  /// row). Names the reply does not carry come from [fallback*].
  static MaterialLogEntry? tryParse(
    Map<String, dynamic> m, {
    String? fallbackMaterialName,
    String? fallbackUnit,
    String? fallbackProjectName,
  }) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final material = J.map(m['material']);
    final project = J.map(m['project']);
    return MaterialLogEntry(
      id: id,
      materialId: J.strOr(m['materialId'], J.strOr(material['id'])),
      materialName:
          J.str(material['name']) ?? fallbackMaterialName ?? 'Material',
      unit: J.str(material['unit']) ?? fallbackUnit ?? '',
      quantity: J.number(m['quantity']) ?? 0,
      unitCost: J.number(m['unitCost']) ?? 0,
      projectId: J.strOr(m['projectId'], J.strOr(project['id'])),
      projectName: J.str(project['name']) ?? fallbackProjectName ?? 'Project',
      usedAt: J.date(m['usedAt']) ?? J.date(m['createdAt']) ?? DateTime.now(),
      notes: J.str(m['notes']),
    );
  }
}

@immutable
class MaterialPage {
  const MaterialPage(this.items, {required this.page, required this.hasMore});
  final List<MaterialItem> items;
  final int page;
  final bool hasMore;
}
