import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Change request statuses the backend uses.
abstract final class CrStatus {
  static const draft = 'DRAFT';
  static const submitted = 'SUBMITTED';
  static const underReview = 'UNDER_REVIEW';
  static const approved = 'APPROVED';
  static const rejected = 'REJECTED';
  static const implemented = 'IMPLEMENTED';
}

/// The change request types the backend uses.
abstract final class CrType {
  static const clientInitiated = 'CLIENT_INITIATED';
  static const internal = 'INTERNAL';
  static const designChange = 'DESIGN_CHANGE';
  static const scopeChange = 'SCOPE_CHANGE';
  static const all = [clientInitiated, internal, designChange, scopeChange];
}

/// One cost line on the "new change request" form, as it is sent.
@immutable
class NewCrItem {
  const NewCrItem({required this.description, this.quantity, this.unitCost});
  final String description;
  final double? quantity;
  final double? unitCost;
}

/// What approving with this cost and time does to the project, in plain words.
/// The server adds the approved cost to the project's budget and the approved
/// days to its end date, and only when they are above zero.
String changeApprovalEffect({
  required double? cost,
  required int? days,
  required String Function(double) money,
}) {
  final addsCost = cost != null && cost > 0;
  final addsDays = days != null && days > 0;
  final parts = <String>[
    addsCost
        ? '${money(cost)} is added to the project\'s budget.'
        : 'The project\'s budget does not change.',
    addsDays
        ? 'The project\'s end date moves $days ${days == 1 ? 'day' : 'days'} later (if it has one).'
        : 'The end date does not change.',
  ];
  return parts.join(' ');
}

/// `CLIENT_INITIATED` → `Client initiated`.
String crTypeLabel(String type) {
  final words = type
      .toLowerCase()
      .split('_')
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Change';
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}

String _personName(Object? raw) {
  final m = J.map(raw);
  return '${J.strOr(m['firstName'])} ${J.strOr(m['lastName'])}'.trim();
}

/// One line of a change request's cost estimate.
@immutable
class CrItem {
  const CrItem({
    required this.description,
    this.category,
    this.quantity,
    this.unitCost,
    this.estimatedCost,
  });

  final String description;
  final String? category;
  final double? quantity;
  final double? unitCost;
  final double? estimatedCost;

  static CrItem? tryParse(Map<String, dynamic> m) {
    final description = J.str(m['description']);
    if (description == null) return null;
    return CrItem(
      description: description,
      category: J.str(m['category']),
      quantity: J.number(m['quantity']),
      unitCost: J.number(m['unitCost']),
      estimatedCost: J.number(m['estimatedCost']),
    );
  }
}

/// A change request in a project's list.
@immutable
class ChangeRequestSummary {
  const ChangeRequestSummary({
    required this.id,
    required this.number,
    required this.title,
    required this.status,
    required this.type,
    required this.requestedBy,
    required this.requestedById,
    required this.createdAt,
    this.estimatedCost,
    this.estimatedDays,
    this.approvedCost,
    this.approvedDays,
    this.itemCount = 0,
  });

  final String id;
  final String number;
  final String title;
  final String status;
  final String type;
  final String requestedBy;
  final String requestedById;
  final DateTime createdAt;
  final double? estimatedCost;
  final int? estimatedDays;
  final double? approvedCost;
  final int? approvedDays;
  final int itemCount;

  /// The cost to talk about: what was approved, else what is estimated.
  double? get cost => approvedCost ?? estimatedCost;
  int? get days => approvedDays ?? estimatedDays;

  static ChangeRequestSummary? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final title = J.str(m['title']);
    if (id == null || title == null) return null;
    final by = _personName(m['requestedBy']);
    return ChangeRequestSummary(
      id: id,
      number: J.strOr(m['requestNumber'], 'Change request'),
      title: title,
      status: J.strOr(m['status'], CrStatus.draft),
      type: J.strOr(m['type']),
      requestedBy: by.isEmpty ? 'A colleague' : by,
      requestedById: J.strOr(
        m['requestedById'],
        J.strOr(J.map(m['requestedBy'])['id']),
      ),
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      estimatedCost: J.number(m['estimatedCost']),
      estimatedDays: J.integer(m['estimatedDays']),
      approvedCost: J.number(m['approvedCost']),
      approvedDays: J.integer(m['approvedDays']),
      itemCount:
          J.integer(J.map(m['_count'])['items']) ?? J.list(m['items']).length,
    );
  }
}

/// One change request with its description, cost lines and notes.
@immutable
class ChangeRequestDetail {
  const ChangeRequestDetail({
    required this.summary,
    required this.description,
    required this.items,
    this.reviewedBy,
    this.reviewedById = '',
    this.approvedBy,
    this.approvedById = '',
    this.reviewNotes,
    this.approvalNotes,
    this.rejectionNotes,
    this.reviewedAt,
    this.approvedAt,
    this.rejectedAt,
    this.implementedAt,
  });

  final ChangeRequestSummary summary;
  final String description;
  final List<CrItem> items;
  final String? reviewedBy;

  /// Empty when the server did not record who (backend-gaps G38 / B6).
  final String reviewedById;

  /// For a rejected request this is who rejected it: the server records the
  /// rejecter in the approver column (backend-gaps G47).
  final String? approvedBy;
  final String approvedById;
  final String? reviewNotes;
  final String? approvalNotes;
  final String? rejectionNotes;
  final DateTime? reviewedAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? implementedAt;

  /// The cost lines added up, when any of them has a cost.
  double? get itemsTotal {
    final costs = items.map((i) => i.estimatedCost).whereType<double>();
    if (costs.isEmpty) return null;
    final sum = costs.fold<double>(0, (a, b) => a + b);
    return (sum * 100).round() / 100;
  }

  static ChangeRequestDetail? tryParse(Object? raw) {
    final m = J.map(raw);
    final summary = ChangeRequestSummary.tryParse(m);
    if (summary == null) return null;
    final reviewer = _personName(m['reviewedBy']);
    final approver = _personName(m['approvedBy']);
    return ChangeRequestDetail(
      summary: summary,
      description: J.strOr(m['description']),
      items: J
          .maps(m['items'])
          .map(CrItem.tryParse)
          .whereType<CrItem>()
          .toList(),
      reviewedBy: reviewer.isEmpty ? null : reviewer,
      reviewedById: J.strOr(
        m['reviewedById'],
        J.strOr(J.map(m['reviewedBy'])['id']),
      ),
      approvedBy: approver.isEmpty ? null : approver,
      approvedById: J.strOr(
        m['approvedById'],
        J.strOr(J.map(m['approvedBy'])['id']),
      ),
      reviewNotes: J.str(m['reviewNotes']),
      approvalNotes: J.str(m['approvalNotes']),
      rejectionNotes: J.str(m['rejectionNotes']),
      reviewedAt: J.date(m['reviewedAt']),
      approvedAt: J.date(m['approvedAt']),
      rejectedAt: J.date(m['rejectedAt']),
      implementedAt: J.date(m['implementedAt']),
    );
  }
}
