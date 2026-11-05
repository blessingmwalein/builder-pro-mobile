import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// A material category (Cement, Electrical…). The company's list is the one on
/// the web app: the server adds the standard ones the first time it is read.
@immutable
class MaterialCategoryRef {
  const MaterialCategoryRef({
    required this.id,
    required this.code,
    required this.name,
  });

  final String id;
  final String code;
  final String name;

  static MaterialCategoryRef? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return MaterialCategoryRef(id: id, code: J.strOr(m['code']), name: name);
  }
}

/// `Cement & concrete` → `CEMENT_CONCRETE`: the code the server keeps for a new
/// category (it upper-cases and replaces anything but letters, digits and
/// underscores itself; this just makes the code readable).
String categoryCodeFor(String name) {
  final code = name
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return code.length > 24 ? code.substring(0, 24) : code;
}

/// Where materials are bought or delivered from.
@immutable
class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.website,
    this.notes,
    this.materialCount = 0,
  });

  final String id;
  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? website;
  final String? notes;
  final int materialCount;

  static Supplier? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return Supplier(
      id: id,
      name: name,
      email: J.str(m['email']),
      phone: J.str(m['phone']),
      address: J.str(m['address']),
      website: J.str(m['website']),
      notes: J.str(m['notes']),
      materialCount: J.integer(J.map(m['_count'])['materials']) ?? 0,
    );
  }
}

/// What the person typed for a new supplier.
@immutable
class SupplierInput {
  const SupplierInput({
    required this.name,
    this.email,
    this.phone,
    this.address,
    this.website,
    this.notes,
  });

  final String name;
  final String? email;
  final String? phone;
  final String? address;
  final String? website;
  final String? notes;

  Map<String, dynamic> toBody() {
    String? t(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    return {
      'name': name.trim(),
      'email': ?t(email),
      'phone': ?t(phone),
      'address': ?t(address),
      'website': ?t(website),
      'notes': ?t(notes),
    };
  }
}

/// What the person typed for a material, new or changed.
@immutable
class MaterialInput {
  const MaterialInput({
    required this.name,
    required this.unit,
    required this.unitCost,
    this.sku,
    this.categoryId,
    this.supplierId,
    this.reorderAt,
    this.description,
    this.openingStock,
    this.reason,
  });

  final String name;
  final String unit;
  final double unitCost;
  final String? sku;
  final String? categoryId;
  final String? supplierId;
  final double? reorderAt;
  final String? description;

  /// Stock counted when the material is first added (new materials only).
  final double? openingStock;

  /// Why the price changed: the server insists on one when it does.
  final String? reason;

  Map<String, dynamic> _common() {
    String? t(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    return {
      'name': name.trim(),
      'unit': unit.trim(),
      'unitCost': unitCost,
      'sku': ?t(sku),
      'categoryId': ?categoryId,
      'supplierId': ?supplierId,
      'reorderAt': ?reorderAt,
      'description': ?t(description),
    };
  }

  Map<String, dynamic> toCreateBody() => {
    ..._common(),
    'stockOnHand': ?openingStock,
  };

  Map<String, dynamic> toUpdateBody() => {
    ..._common(),
    'reason': ?(reason == null || reason!.trim().isEmpty
        ? null
        : reason!.trim()),
  };
}
