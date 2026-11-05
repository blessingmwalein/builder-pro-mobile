import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// Project stage statuses the backend uses.
abstract final class StageStatus {
  static const pending = 'PENDING';
  static const inProgress = 'IN_PROGRESS';
  static const completed = 'COMPLETED';
  static const blocked = 'BLOCKED';
  static const skipped = 'SKIPPED';

  /// In the order a person would pick them.
  static const all = [pending, inProgress, blocked, completed, skipped];
}

/// `PROJECT_INITIATION` → `Project initiation`.
String workflowLabel(String code) {
  final words = code
      .trim()
      .toLowerCase()
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Stages';
  final text = words.join(' ');
  return text[0].toUpperCase() + text.substring(1);
}

/// One stage of a project's lifecycle (for example "Foundations" under the
/// "Execution" workflow).
@immutable
class ProjectStage {
  const ProjectStage({
    required this.id,
    required this.workflowCode,
    required this.name,
    required this.order,
    required this.status,
    required this.requiresApproval,
    this.plannedStart,
    this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.approvedBy,
    this.approvedAt,
    this.notes,
  });

  final String id;
  final String workflowCode;
  final String name;
  final int order;
  final String status;
  final bool requiresApproval;

  /// Calendar days (UTC midnight); show them with `Fmt.calendarDay`.
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? notes;

  bool get isCompleted => status == StageStatus.completed;

  /// Counts towards "x of y stages done".
  bool get isFinished =>
      status == StageStatus.completed || status == StageStatus.skipped;

  /// Waiting for someone with the right to approve it.
  bool get awaitsApproval => requiresApproval && !isCompleted;

  static ProjectStage? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = J.str(m['stageName']);
    if (id == null || name == null) return null;
    final by = J.map(m['approvedBy']);
    final approver = '${J.strOr(by['firstName'])} ${J.strOr(by['lastName'])}'
        .trim();
    return ProjectStage(
      id: id,
      workflowCode: J.strOr(m['workflowCode']),
      name: name,
      order: J.integer(m['stageOrder']) ?? 0,
      status: J.strOr(m['status'], StageStatus.pending),
      requiresApproval: J.boolean(m['requiresApproval']),
      plannedStart: J.date(m['plannedStartDate']),
      plannedEnd: J.date(m['plannedEndDate']),
      actualStart: J.date(m['actualStartDate']),
      actualEnd: J.date(m['actualEndDate']),
      approvedBy: approver.isEmpty ? null : approver,
      approvedAt: J.date(m['approvedAt']),
      notes: J.str(m['notes']),
    );
  }
}

/// The stages of one workflow, in order.
@immutable
class StageGroup {
  const StageGroup(this.code, this.stages);
  final String code;
  final List<ProjectStage> stages;

  String get label => workflowLabel(code);
  int get finished => stages.where((s) => s.isFinished).length;
}

/// Splits a flat stage list into workflows, each in stage order. The API
/// already sorts this way; this keeps the screen right if it ever does not.
List<StageGroup> groupStages(List<ProjectStage> stages) {
  final byCode = <String, List<ProjectStage>>{};
  for (final s in stages) {
    byCode.putIfAbsent(s.workflowCode, () => []).add(s);
  }
  final codes = byCode.keys.toList()..sort();
  return [
    for (final code in codes)
      StageGroup(
        code,
        byCode[code]!..sort((a, b) => a.order.compareTo(b.order)),
      ),
  ];
}
