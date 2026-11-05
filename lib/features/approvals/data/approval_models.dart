import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// A worker's time entry as a supervisor sees it when approving time.
/// Pay rates and labour cost are deliberately not read: approvers decide on
/// hours, not money.
@immutable
class ApprovalEntry {
  const ApprovalEntry({
    required this.id,
    required this.workerId,
    required this.workerName,
    required this.projectName,
    required this.clockInAt,
    this.projectCode,
    this.taskTitle,
    this.clockOutAt,
    this.breakMinutes = 0,
    this.totalHours = 0,
    this.isManual = false,
    this.notes,
    this.status = 'PENDING',
  });

  final String id;
  final String workerId;
  final String workerName;
  final String projectName;
  final String? projectCode;
  final String? taskTitle;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final int breakMinutes;

  /// Regular + overtime hours as calculated by the server at clock-out.
  final double totalHours;

  /// Entered by hand (not clocked), so it deserves a closer look.
  final bool isManual;
  final String? notes;
  final String status;

  /// Still clocked in: the server refuses to approve an open entry.
  bool get isOpen => clockOutAt == null;

  Duration workedAt(DateTime now) {
    final d =
        (clockOutAt ?? now).difference(clockInAt) -
        Duration(minutes: breakMinutes);
    return d.isNegative ? Duration.zero : d;
  }

  String get projectLabel =>
      projectCode == null ? projectName : '$projectCode · $projectName';

  static ApprovalEntry? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final clockIn = J.date(m['clockInAt']);
    if (id == null || clockIn == null) return null;
    final worker = J.map(m['worker']);
    final project = J.map(m['project']);
    final task = J.map(m['task']);
    final name =
        '${J.strOr(worker['firstName'])} ${J.strOr(worker['lastName'])}'.trim();
    return ApprovalEntry(
      id: id,
      workerId: J.strOr(m['workerId'], J.strOr(worker['id'])),
      workerName: name.isEmpty ? 'Team member' : name,
      projectName: J.strOr(project['name'], 'Project'),
      projectCode: J.str(project['code']),
      taskTitle: J.str(task['title']),
      clockInAt: clockIn,
      clockOutAt: J.date(m['clockOutAt']),
      breakMinutes: J.integer(m['breakMinutes']) ?? 0,
      totalHours:
          (J.number(m['regularHours']) ?? 0) +
          (J.number(m['overtimeHours']) ?? 0),
      isManual: J.boolean(m['isManualEntry']),
      notes: J.str(m['notes']),
      status: J.strOr(m['status'], 'PENDING'),
    );
  }
}

@immutable
class ApprovalPage {
  const ApprovalPage(
    this.entries, {
    required this.page,
    required this.hasMore,
    required this.total,
  });
  final List<ApprovalEntry> entries;
  final int page;
  final bool hasMore;
  final int total;
}
