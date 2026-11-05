import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Equipment statuses the backend uses.
abstract final class EquipmentStatus {
  static const available = 'AVAILABLE';
  static const inUse = 'IN_USE';
  static const maintenance = 'MAINTENANCE';
  static const retired = 'RETIRED';
}

String _personName(Object? raw) {
  final m = J.map(raw);
  return '${J.strOr(m['firstName'])} ${J.strOr(m['lastName'])}'.trim();
}

/// One piece of equipment in the list. The daily rate and purchase cost the API
/// also sends are company costs and are deliberately not read.
@immutable
class EquipmentSummary {
  const EquipmentSummary({
    required this.id,
    required this.name,
    required this.status,
    this.categoryId,
    this.categoryName,
    this.serialNumber,
    this.assignmentCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String status;
  final String? categoryId;
  final String? categoryName;
  final String? serialNumber;
  final int assignmentCount;
  final DateTime? createdAt;

  bool get isAvailable => status == EquipmentStatus.available;
  bool get isInUse => status == EquipmentStatus.inUse;

  static EquipmentSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return EquipmentSummary(
      id: id,
      name: name,
      status: J.strOr(m['status'], EquipmentStatus.available),
      categoryId: J.str(J.map(m['category'])['id']) ?? J.str(m['categoryId']),
      categoryName: J.str(J.map(m['category'])['name']),
      serialNumber: J.str(m['serialNumber']),
      assignmentCount: J.integer(J.map(m['_count'])['allocations']) ?? 0,
      createdAt: J.date(m['createdAt']),
    );
  }
}

/// An equipment category (for example "Heavy plant").
@immutable
class EquipmentCategory {
  const EquipmentCategory({required this.id, required this.name});
  final String id;
  final String name;

  static EquipmentCategory? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return EquipmentCategory(id: id, name: name);
  }
}

/// One stretch of time the equipment was (or is) assigned to a project.
@immutable
class EquipmentAssignment {
  const EquipmentAssignment({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.startDate,
    required this.assignedBy,
    required this.assignedById,
    this.endDate,
    this.returnedAt,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String projectId;
  final String projectName;

  /// Calendar days (UTC midnight); show them with `Fmt.calendarDay`.
  final DateTime startDate;
  final DateTime? endDate;

  /// When it came back (an instant); null while it is still out.
  final DateTime? returnedAt;
  final String assignedBy;
  final String assignedById;
  final String? notes;
  final DateTime? createdAt;

  bool get isOpen => returnedAt == null;

  static EquipmentAssignment? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final start = J.date(m['startDate']);
    if (id == null || start == null) return null;
    final by = J.map(m['allocatedBy']);
    final name = _personName(by);
    return EquipmentAssignment(
      id: id,
      projectId: J.strOr(m['projectId'], J.strOr(J.map(m['project'])['id'])),
      projectName: J.strOr(J.map(m['project'])['name'], 'A project'),
      startDate: start,
      endDate: J.date(m['endDate']),
      returnedAt: J.date(m['returnedAt']),
      assignedBy: name.isEmpty ? 'A colleague' : name,
      assignedById: J.strOr(m['allocatedById'], J.strOr(by['id'])),
      notes: J.str(m['notes']),
      createdAt: J.date(m['createdAt']),
    );
  }
}

/// Equipment with its most recent assignments (the API sends the last 10).
@immutable
class EquipmentDetail {
  const EquipmentDetail({
    required this.summary,
    required this.assignments,
    this.description,
  });

  final EquipmentSummary summary;
  final String? description;

  /// Newest first.
  final List<EquipmentAssignment> assignments;

  List<EquipmentAssignment> get openAssignments =>
      assignments.where((a) => a.isOpen).toList();

  /// The one assignment that can be returned from the app: the item is in use
  /// and exactly one open assignment is known. With none in the recent list, or
  /// more than one, which one to close is not clear, so it is left to the web.
  EquipmentAssignment? get returnable {
    if (!summary.isInUse) return null;
    final open = openAssignments;
    return open.length == 1 ? open.single : null;
  }

  static EquipmentDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = EquipmentSummary.tryParse(m);
    if (summary == null) return null;
    return EquipmentDetail(
      summary: summary,
      description: J.str(m['description']),
      assignments: J
          .list(m['allocations'])
          .map(EquipmentAssignment.tryParse)
          .whereType<EquipmentAssignment>()
          .toList(),
    );
  }
}
