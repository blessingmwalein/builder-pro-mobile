import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../shared/services/location_service.dart';
import 'time_models.dart';

/// `/time-tracking/*` for the signed-in worker's own time.
///
/// Time is stamped by the server and there is no idempotency key, so callers
/// must never repeat clock-in/clock-out blindly after an uncertain failure —
/// they reconcile with [active] first.
class TimeRepository {
  TimeRepository(this._api, {required this.userId});

  final ApiClient _api;

  /// Always sent as `workerId`: users with `timesheets.*` would otherwise get
  /// every colleague's entries from the list endpoint.
  final String userId;

  /// The open entry, or null when not clocked in (the API answers 200 with an
  /// empty body in that case).
  Future<TimeEntry?> active() async {
    final body = await _api.get('time-tracking/active');
    return TimeEntry.tryParse(body);
  }

  /// [at] is where the phone is, when the person has chosen to record it.
  ///
  /// [occurredAt] is for a clock-in saved on a phone with no signal: the moment
  /// the worker really clocked in, which the server then records instead of its
  /// own time. Only send it to a server that said it understands (see
  /// `server_features.dart`); the server flags such an entry as manual and
  /// recognises a repeat of the same moment.
  Future<TimeEntry> clockIn({
    required String projectId,
    String? taskId,
    GeoPoint? at,
    DateTime? occurredAt,
  }) async {
    final body = await _api.post(
      'time-tracking/clock-in',
      body: {
        'projectId': projectId,
        'taskId': ?taskId,
        'gpsInLat': ?at?.latitude,
        'gpsInLng': ?at?.longitude,
        'clockedInAt': ?occurredAt?.toUtc().toIso8601String(),
      },
    );
    return _entryOrUncertain(body);
  }

  /// [occurredAt]: see [clockIn].
  Future<TimeEntry> clockOut(
    String entryId, {
    int breakMinutes = 0,
    GeoPoint? at,
    DateTime? occurredAt,
  }) async {
    final body = await _api.put(
      'time-tracking/$entryId/clock-out',
      body: {
        'breakMinutes': breakMinutes,
        'gpsOutLat': ?at?.latitude,
        'gpsOutLng': ?at?.longitude,
        'clockedOutAt': ?occurredAt?.toUtc().toIso8601String(),
      },
    );
    return _entryOrUncertain(body);
  }

  /// Newest first. [from]/[to] are instants.
  Future<List<TimeEntry>> entries({
    DateTime? from,
    DateTime? to,
    int page = 1,
    int limit = 20,
  }) async {
    final body = await _api.get(
      'time-tracking',
      query: {
        'page': page,
        'limit': limit,
        'workerId': userId,
        'from': from?.toUtc().toIso8601String(),
        'to': to?.toUtc().toIso8601String(),
      },
    );
    return J
        .paged(body)
        .items
        .map(TimeEntry.tryParse)
        .whereType<TimeEntry>()
        .toList();
  }

  /// [weekStart] is the worker's LOCAL Monday 00:00, sent as an instant so the
  /// server's 7-day window lines up with the worker's week (a bare date would
  /// be read as UTC midnight and shift early-morning shifts into the last week).
  Future<WeeklySummary> weeklySummary(DateTime weekStart) async {
    final body = await _api.get(
      'time-tracking/weekly-summary',
      query: {'weekStart': weekStart.toUtc().toIso8601String()},
    );
    return WeeklySummary.parse(body, fallbackStart: weekStart);
  }

  /// The server accepted the write but the reply was unreadable: the outcome is
  /// unknown, so the caller reconciles instead of reporting a false failure.
  TimeEntry _entryOrUncertain(Object? body) {
    final entry = TimeEntry.tryParse(body);
    if (entry != null) return entry;
    throw const AppException(
      AppErrorKind.uncertain,
      'The server replied, but the reply could not be read. Your action may have been saved.',
    );
  }
}
