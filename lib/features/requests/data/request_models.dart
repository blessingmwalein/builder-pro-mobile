import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// What a request is about. The API sends only the type and an id, never the
/// amount or contents (backend-gaps G26), so the app can say what KIND of thing
/// it is and nothing more.
String entityTypeLabel(String type) => switch (type) {
  'BUDGET' => 'Budget',
  'PROCUREMENT_PR' => 'Purchase request',
  'PROCUREMENT_PO' => 'Purchase order',
  'DOCUMENT' => 'Document',
  'STAGE' => 'Project stage',
  'CHANGE_REQUEST' => 'Change request',
  _ => _words(type),
};

/// What approving a request of this kind really does, for the confirmation.
///
/// The approvals engine only moves the linked record for purchase requests and
/// orders, and for change requests it sets the status without applying the
/// approved cost or days. Budgets, documents and stages are not touched at all
/// (backend-gaps G39), so approving them records a decision and nothing else.
/// Null when there is nothing to add.
String? approvalEffect(String type) => switch (type) {
  'PROCUREMENT_PO' =>
    'Once every approver has approved, the order is marked as sent.',
  'CHANGE_REQUEST' => "This marks the change request approved but does not apply its cost or days to the project, and they can't be applied afterwards. To apply them, approve it from the project's change requests instead.",
  'BUDGET' || 'DOCUMENT' || 'STAGE' =>
    'This records your decision only. It does not change the ${entityTypeLabel(type).toLowerCase()} itself. Do that on the web app.',
  _ => null,
};

String _words(String raw) => raw
    .toLowerCase()
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

@immutable
class RequestStep {
  const RequestStep({
    required this.id,
    required this.order,
    required this.approverId,
    required this.approverName,
    required this.status,
    this.comment,
    this.decidedAt,
  });

  final String id;
  final int order;
  final String approverId;
  final String approverName;
  final String status;
  final String? comment;
  final DateTime? decidedAt;

  bool get isPending => status == 'PENDING';

  static RequestStep? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    if (id == null) return null;
    final who = J.map(m['approver']);
    final name = '${J.strOr(who['firstName'])} ${J.strOr(who['lastName'])}'
        .trim();
    return RequestStep(
      id: id,
      order: J.integer(m['stepOrder']) ?? 0,
      approverId: J.strOr(m['approverId'], J.strOr(who['id'])),
      approverName: name.isEmpty ? 'Approver' : name,
      status: J.strOr(m['status'], 'PENDING'),
      comment: J.str(m['comment']),
      decidedAt: J.date(m['decidedAt']),
    );
  }
}

@immutable
class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.status,
    required this.requestedBy,
    required this.createdAt,
    required this.steps,
    this.notes,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String status;
  final String requestedBy;
  final DateTime createdAt;
  final List<RequestStep> steps;
  final String? notes;

  String get typeLabel => entityTypeLabel(entityType);

  /// The step waiting for [userId], if any.
  RequestStep? pendingStepFor(String userId) {
    for (final s in steps) {
      if (s.approverId == userId && s.isPending) return s;
    }
    return null;
  }

  RequestStep? stepById(String stepId) {
    for (final s in steps) {
      if (s.id == stepId) return s;
    }
    return null;
  }

  static ApprovalRequest? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    final who = J.map(m['requestedBy']);
    final name = '${J.strOr(who['firstName'])} ${J.strOr(who['lastName'])}'
        .trim();
    return ApprovalRequest(
      id: id,
      entityType: J.strOr(m['entityType'], 'OTHER'),
      entityId: J.strOr(m['entityId']),
      status: J.strOr(m['status'], 'PENDING'),
      requestedBy: name.isEmpty ? 'A colleague' : name,
      createdAt: J.date(m['createdAt']) ?? DateTime.now(),
      notes: J.str(m['notes']),
      steps:
          J
              .maps(m['steps'])
              .map(RequestStep.tryParse)
              .whereType<RequestStep>()
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order)),
    );
  }
}
