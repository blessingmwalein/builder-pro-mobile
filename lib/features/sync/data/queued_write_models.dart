import 'dart:convert';

import '../../../core/offline/app_database.dart';
import '../../../core/utils/json.dart';
import '../../../shared/services/location_service.dart';

/// The kinds of write the app saves when there is no connection.
abstract final class WriteKind {
  static const clockIn = 'clock_in';
  static const clockOut = 'clock_out';
  static const materialUsage = 'material_usage';

  /// Everything on the clock is one stream, so events go in the order they
  /// happened and a clock-out never overtakes its clock-in.
  static const timeStream = 'time';

  static const timeKinds = [clockIn, clockOut];

  static bool isTime(String kind) => timeKinds.contains(kind);
}

/// When an event really happened, to the millisecond and in UTC. The server
/// stores exactly this, so it doubles as the way to recognise the event later.
DateTime eventTime([DateTime? at]) {
  final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

bool sameMoment(DateTime a, DateTime b) =>
    a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;

Map<String, dynamic> _decode(String payload) {
  try {
    final v = jsonDecode(payload);
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

double? _gps(Map<String, dynamic> m, String key) => J.number(m[key]);

/// A clock-in saved on the phone.
class ClockInWrite {
  const ClockInWrite({
    required this.projectId,
    required this.occurredAt,
    this.projectName,
    this.projectCode,
    this.taskId,
    this.taskTitle,
    this.position,
  });

  final String projectId;
  final String? projectName;
  final String? projectCode;
  final String? taskId;
  final String? taskTitle;
  final DateTime occurredAt;
  final GeoPoint? position;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'projectName': projectName,
    'projectCode': projectCode,
    'taskId': taskId,
    'taskTitle': taskTitle,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'lat': position?.latitude,
    'lng': position?.longitude,
  };

  static ClockInWrite? tryParse(String payload) {
    final m = _decode(payload);
    final projectId = J.str(m['projectId']);
    final at = J.date(m['occurredAt']);
    if (projectId == null || at == null) return null;
    final lat = _gps(m, 'lat');
    final lng = _gps(m, 'lng');
    return ClockInWrite(
      projectId: projectId,
      projectName: J.str(m['projectName']),
      projectCode: J.str(m['projectCode']),
      taskId: J.str(m['taskId']),
      taskTitle: J.str(m['taskTitle']),
      occurredAt: at,
      position: lat != null && lng != null ? GeoPoint(lat, lng) : null,
    );
  }
}

/// A clock-out saved on the phone. It closes either an entry the server
/// already has ([entryId]) or the one a queued clock-in will create
/// ([dependsOn]; the server's id arrives as [dependsOnResult]).
class ClockOutWrite {
  const ClockOutWrite({
    required this.occurredAt,
    this.entryId,
    this.dependsOn,
    this.dependsOnResult,
    this.breakMinutes = 0,
    this.position,
  });

  final DateTime occurredAt;
  final String? entryId;
  final String? dependsOn;
  final String? dependsOnResult;
  final int breakMinutes;
  final GeoPoint? position;

  /// The entry to close, once it is known.
  String? get targetEntryId => entryId ?? dependsOnResult;

  Map<String, dynamic> toJson() => {
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'entryId': entryId,
    'dependsOn': dependsOn,
    'dependsOnResult': dependsOnResult,
    'breakMinutes': breakMinutes,
    'lat': position?.latitude,
    'lng': position?.longitude,
  };

  static ClockOutWrite? tryParse(String payload) {
    final m = _decode(payload);
    final at = J.date(m['occurredAt']);
    if (at == null) return null;
    final lat = _gps(m, 'lat');
    final lng = _gps(m, 'lng');
    return ClockOutWrite(
      occurredAt: at,
      entryId: J.str(m['entryId']),
      dependsOn: J.str(m['dependsOn']),
      dependsOnResult: J.str(m['dependsOnResult']),
      breakMinutes: J.integer(m['breakMinutes']) ?? 0,
      position: lat != null && lng != null ? GeoPoint(lat, lng) : null,
    );
  }
}

/// Material used on a project, saved on the phone.
class MaterialUsageWrite {
  const MaterialUsageWrite({
    required this.projectId,
    required this.projectName,
    required this.materialId,
    required this.materialName,
    required this.unit,
    required this.quantity,
    required this.unitCost,
    required this.occurredAt,
    this.notes,
  });

  final String projectId;
  final String projectName;
  final String materialId;
  final String materialName;
  final String unit;
  final double quantity;
  final double unitCost;
  final DateTime occurredAt;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'projectId': projectId,
    'projectName': projectName,
    'materialId': materialId,
    'materialName': materialName,
    'unit': unit,
    'quantity': quantity,
    'unitCost': unitCost,
    'notes': notes,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };

  static MaterialUsageWrite? tryParse(String payload) {
    final m = _decode(payload);
    final projectId = J.str(m['projectId']);
    final materialId = J.str(m['materialId']);
    final quantity = J.number(m['quantity']);
    final at = J.date(m['occurredAt']);
    if (projectId == null ||
        materialId == null ||
        quantity == null ||
        at == null) {
      return null;
    }
    return MaterialUsageWrite(
      projectId: projectId,
      projectName: J.strOr(m['projectName'], 'Project'),
      materialId: materialId,
      materialName: J.strOr(m['materialName'], 'Material'),
      unit: J.strOr(m['unit']),
      quantity: quantity,
      unitCost: J.number(m['unitCost']) ?? 0,
      notes: J.str(m['notes']),
      occurredAt: at,
    );
  }
}

extension QueuedWriteParsing on QueuedWrite {
  ClockInWrite? get asClockIn => ClockInWrite.tryParse(payload);
  ClockOutWrite? get asClockOut => ClockOutWrite.tryParse(payload);
  MaterialUsageWrite? get asUsage => MaterialUsageWrite.tryParse(payload);
}
