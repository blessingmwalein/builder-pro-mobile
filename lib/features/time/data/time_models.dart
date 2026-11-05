import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// A project the worker can clock in on. Derived from their own assigned tasks
/// and time history (the API has no assignment-scoped project list for workers).
@immutable
class ProjectRef {
  const ProjectRef({required this.id, required this.name, this.code});

  final String id;
  final String name;
  final String? code;

  String get label => code == null ? name : '$code · $name';

  static ProjectRef? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    if (id == null) return null;
    return ProjectRef(
      id: id,
      name: J.strOr(m['name'], 'Project'),
      code: J.str(m['code']),
    );
  }

  @override
  bool operator ==(Object other) => other is ProjectRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One clock-in/clock-out record. Decimals arrive as strings; [J] tolerates both.
@immutable
class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.projectId,
    required this.clockInAt,
    this.projectName,
    this.projectCode,
    this.taskId,
    this.taskTitle,
    this.clockOutAt,
    this.breakMinutes = 0,
    this.regularHours = 0,
    this.overtimeHours = 0,
    this.status = 'PENDING',
    this.isManual = false,
    this.notes,
  });

  final String id;
  final String projectId;
  final String? projectName;
  final String? projectCode;
  final String? taskId;
  final String? taskTitle;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final int breakMinutes;
  final double regularHours;
  final double overtimeHours;
  final String status;
  final bool isManual;
  final String? notes;

  bool get isOpen => clockOutAt == null;
  double get totalHours => regularHours + overtimeHours;

  /// Worked time so far (open entry) or in total (closed), minus breaks.
  Duration workedAt(DateTime now) {
    final end = clockOutAt ?? now;
    final d = end.difference(clockInAt) - Duration(minutes: breakMinutes);
    return d.isNegative ? Duration.zero : d;
  }

  ProjectRef get project => ProjectRef(
    id: projectId,
    name: projectName ?? 'Project',
    code: projectCode,
  );

  TimeEntry withProject(ProjectRef p, {String? taskTitle}) => TimeEntry(
    id: id,
    projectId: projectId,
    projectName: p.name,
    projectCode: p.code,
    taskId: taskId,
    taskTitle: taskTitle ?? this.taskTitle,
    clockInAt: clockInAt,
    clockOutAt: clockOutAt,
    breakMinutes: breakMinutes,
    regularHours: regularHours,
    overtimeHours: overtimeHours,
    status: status,
    isManual: isManual,
    notes: notes,
  );

  /// Same shape the API sends, so [tryParse] can read the offline copy back.
  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'project': {'id': projectId, 'name': projectName, 'code': projectCode},
    'taskId': taskId,
    if (taskId != null) 'task': {'id': taskId, 'title': taskTitle},
    'clockInAt': clockInAt.toUtc().toIso8601String(),
    'clockOutAt': clockOutAt?.toUtc().toIso8601String(),
    'breakMinutes': breakMinutes,
    'regularHours': regularHours,
    'overtimeHours': overtimeHours,
    'status': status,
    'isManualEntry': isManual,
    'notes': notes,
  };

  /// Null when the body is empty (GET /time-tracking/active answers 200 with no
  /// body when nobody is clocked in) or has no usable id/clock-in time.
  static TimeEntry? tryParse(Object? raw) {
    final m = J.map(raw);
    final id = J.str(m['id']);
    final clockIn = J.date(m['clockInAt']);
    if (id == null || clockIn == null) return null;
    final project = J.map(m['project']);
    final task = J.map(m['task']);
    return TimeEntry(
      id: id,
      projectId: J.strOr(m['projectId'], J.strOr(project['id'])),
      projectName: J.str(project['name']),
      projectCode: J.str(project['code']),
      taskId: J.str(m['taskId']) ?? J.str(task['id']),
      taskTitle: J.str(task['title']),
      clockInAt: clockIn,
      clockOutAt: J.date(m['clockOutAt']),
      breakMinutes: J.integer(m['breakMinutes']) ?? 0,
      regularHours: J.number(m['regularHours']) ?? 0,
      overtimeHours: J.number(m['overtimeHours']) ?? 0,
      status: J.strOr(m['status'], 'PENDING'),
      isManual: J.boolean(m['isManualEntry']),
      notes: J.str(m['notes']),
    );
  }
}

@immutable
class WeeklySummary {
  const WeeklySummary({
    required this.weekStart,
    required this.totalRegularHours,
    required this.totalOvertimeHours,
    required this.entries,
  });

  final DateTime weekStart;
  final double totalRegularHours;
  final double totalOvertimeHours;
  final List<TimeEntry> entries;

  double get totalHours => totalRegularHours + totalOvertimeHours;

  static WeeklySummary parse(Object? raw, {required DateTime fallbackStart}) {
    final m = J.map(raw);
    return WeeklySummary(
      weekStart: J.date(m['weekStart']) ?? fallbackStart,
      totalRegularHours: J.number(m['totalRegularHours']) ?? 0,
      totalOvertimeHours: J.number(m['totalOvertimeHours']) ?? 0,
      entries: J
          .maps(m['entries'])
          .map(TimeEntry.tryParse)
          .whereType<TimeEntry>()
          .toList(),
    );
  }
}
