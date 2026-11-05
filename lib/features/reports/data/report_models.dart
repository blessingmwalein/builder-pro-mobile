import 'package:flutter/foundation.dart';

import '../../../core/utils/json.dart';

/// A stage that should have finished by now and has not.
@immutable
class OverdueStage {
  const OverdueStage({
    required this.name,
    required this.status,
    required this.daysOverdue,
  });
  final String name;
  final String status;
  final int daysOverdue;

  static OverdueStage? tryParse(Map<String, dynamic> m) {
    final name = J.str(m['name']);
    if (name == null) return null;
    return OverdueStage(
      name: name,
      status: J.strOr(m['status'], 'PENDING'),
      daysOverdue: J.integer(m['daysOverdue']) ?? 0,
    );
  }
}

/// One active or on-hold project in the delay report.
@immutable
class DelayRow {
  const DelayRow({
    required this.id,
    required this.name,
    required this.status,
    required this.completionPercent,
    required this.daysDelayed,
    required this.overdueStages,
    this.code,
    this.endDate,
  });

  final String id;
  final String name;
  final String? code;
  final String status;
  final DateTime? endDate;
  final int completionPercent;

  /// Days past the project's end date; 0 when it is not late.
  final int daysDelayed;
  final List<OverdueStage> overdueStages;

  bool get isDelayed => daysDelayed > 0;

  static DelayRow? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['id']);
    final name = J.str(m['name']);
    if (id == null || name == null) return null;
    return DelayRow(
      id: id,
      name: name,
      code: J.str(m['code']),
      status: J.strOr(m['status'], 'ACTIVE'),
      endDate: J.date(m['endDate']),
      completionPercent: J.integer(m['completionPercent']) ?? 0,
      daysDelayed: J.integer(m['daysDelayed']) ?? 0,
      overdueStages: J
          .maps(m['blockedStages'])
          .map(OverdueStage.tryParse)
          .whereType<OverdueStage>()
          .toList(),
    );
  }
}

/// Which projects are behind, and which stages are overdue.
@immutable
class DelayReport {
  const DelayReport({required this.rows, this.generatedAt});

  /// Most delayed first.
  final List<DelayRow> rows;
  final DateTime? generatedAt;

  int get delayed => rows.where((r) => r.isDelayed).length;
  int get onTrack => rows.length - delayed;

  static DelayReport parse(Object? raw) {
    final m = J.map(raw);
    final rows =
        J.maps(m['rows']).map(DelayRow.tryParse).whereType<DelayRow>().toList()
          ..sort((a, b) => b.daysDelayed.compareTo(a.daysDelayed));
    return DelayReport(rows: rows, generatedAt: J.date(m['generatedAt']));
  }
}

/// Task completion and hours for one project.
@immutable
class ProductivityRow {
  const ProductivityRow({
    required this.projectId,
    required this.projectName,
    required this.total,
    required this.done,
    required this.inProgress,
    required this.blocked,
    required this.estimatedHours,
    required this.actualHours,
  });

  final String projectId;
  final String projectName;
  final int total;
  final int done;
  final int inProgress;
  final int blocked;
  final double estimatedHours;
  final double actualHours;

  /// Whole percent of tasks done; 0 when there are none.
  int get completionRate => total == 0 ? 0 : ((done * 100) / total).round();

  static ProductivityRow? tryParse(Map<String, dynamic> m) {
    final id = J.str(m['projectId']);
    final name = J.str(m['projectName']);
    if (id == null || name == null) return null;
    return ProductivityRow(
      projectId: id,
      projectName: name,
      total: J.integer(m['total']) ?? 0,
      done: J.integer(m['done']) ?? 0,
      inProgress: J.integer(m['inProgress']) ?? 0,
      blocked: J.integer(m['blocked']) ?? 0,
      estimatedHours: J.number(m['estimatedHours']) ?? 0,
      actualHours: J.number(m['actualHours']) ?? 0,
    );
  }
}

/// Task completion and hours worked, project by project (approved time only).
@immutable
class ProductivityReport {
  const ProductivityReport({required this.rows});

  /// Projects with the most tasks first.
  final List<ProductivityRow> rows;

  int get totalTasks => rows.fold(0, (s, r) => s + r.total);
  int get doneTasks => rows.fold(0, (s, r) => s + r.done);
  int get completionRate =>
      totalTasks == 0 ? 0 : ((doneTasks * 100) / totalTasks).round();

  static ProductivityReport parse(Object? raw) {
    final m = J.map(raw);
    final rows =
        J
            .maps(m['rows'])
            .map(ProductivityRow.tryParse)
            .whereType<ProductivityRow>()
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
    return ProductivityReport(rows: rows);
  }
}
