import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/server_features.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../../shared/services/location_service.dart';
import '../../sync/application/sync_providers.dart';
import '../../sync/data/queued_write_models.dart';
import '../data/time_models.dart';
import '../data/time_repository.dart';
import 'clock_location.dart';

final timeRepositoryProvider = Provider<TimeRepository?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  return TimeRepository(ref.watch(apiClientProvider), userId: uid);
});

/// Ids of a shift that is saved on the phone but not on the server yet start
/// with this, followed by the id of the saved clock-in.
const localEntryPrefix = 'local:';

/// Where the clock state stands.
class ClockState {
  const ClockState(
    this.active, {
    this.lastKnown = false,
    this.savedOnPhone = false,
  });

  /// The open time entry, or null when the worker is not clocked in.
  final TimeEntry? active;

  /// True when the server could not be reached and this is the last saved state.
  final bool lastKnown;

  /// The open entry is a shift saved on this phone, not yet on the server.
  final bool savedOnPhone;
}

/// What the server knows, with the clock events saved on the phone applied in
/// the order they happened: a saved clock-in starts a shift, a saved clock-out
/// ends it.
TimeEntry? applyQueuedClockEvents(TimeEntry? server, List<QueuedWrite> saved) {
  var current = server;
  for (final w in saved) {
    if (w.kind == WriteKind.clockIn) {
      final p = w.asClockIn;
      if (p == null) continue;
      current = TimeEntry(
        id: '$localEntryPrefix${w.id}',
        projectId: p.projectId,
        projectName: p.projectName,
        projectCode: p.projectCode,
        taskId: p.taskId,
        taskTitle: p.taskTitle,
        clockInAt: p.occurredAt,
      );
    } else if (w.kind == WriteKind.clockOut) {
      current = null;
    }
  }
  return current;
}

/// Clock-in / clock-out for the signed-in worker.
///
/// Time is stamped by the server and the API has no idempotency key, so a
/// request whose outcome is unknown (timeout after sending) is never repeated
/// blindly: the controller asks the server what happened first.
///
/// Without a connection (and once the server has said it reads the time an
/// event really happened) a clock-in or clock-out is saved on the phone with
/// that time and sent later by the write queue, exactly once.
class ClockController extends AsyncNotifier<ClockState> {
  static const _scope = 'time_active';
  static const _key = 'current';

  bool _inFlight = false;

  /// What the server said last (or the saved copy of it).
  TimeEntry? _base;
  bool _lastKnown = false;

  /// Clock events saved on the phone, oldest first.
  List<QueuedWrite> _saved = const [];

  /// A saved event was just recorded: wait for the server's answer before
  /// redrawing so the screen does not flash "not clocked in".
  bool _holding = false;

  /// The first load has finished. Until then nothing may set the state: it
  /// would replace what the load is about to return.
  bool _ready = false;

  /// True while a clock-in/out request is running (the UI disables the button).
  bool get busy => _inFlight;

  @override
  Future<ClockState> build() async {
    final uid = ref.watch(currentUserIdProvider);
    final repo = ref.watch(timeRepositoryProvider);
    if (uid == null || repo == null) return const ClockState(null);
    _ready = false;
    ref.listen<int>(appResumeProvider, (_, _) => _quietRefresh());
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      if (prev?.value == false && next.value == true) _quietRefresh();
    });
    ref.listen<AsyncValue<List<QueuedWrite>>>(queuedWritesProvider, (_, next) {
      final saved = next.value;
      if (saved != null) _onSavedChanged(saved);
    });

    _saved = _clockEvents(await ref.read(writeQueueProvider)?.all());
    try {
      final active = await repo.active();
      await _remember(uid, active);
      _base = active;
      _lastKnown = false;
      _ready = true;
      return _compose();
    } on AppException catch (e) {
      if (!e.isRetryable) rethrow;
      final cached = await _recall(uid);
      // With nothing cached and nothing saved there is nothing to show.
      if (cached == null && _saved.isEmpty) rethrow;
      _base = cached?.active;
      _lastKnown = true;
      _ready = true;
      return _compose();
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  /// Re-reads the server state without flashing a spinner or touching a
  /// request that is in progress.
  Future<void> refreshQuietly() => _quietRefresh();

  Future<void> _quietRefresh() async {
    if (_inFlight) return;
    final repo = ref.read(timeRepositoryProvider);
    final uid = ref.read(currentUserIdProvider);
    if (repo == null || uid == null) return;
    try {
      final active = await repo.active();
      await _remember(uid, active);
      _setBase(active);
    } on AppException {
      // Keep what is on screen; the next refresh will try again.
    }
  }

  ClockState _compose() {
    final active = applyQueuedClockEvents(_base, _saved);
    return ClockState(
      active,
      lastKnown: _lastKnown,
      savedOnPhone: active?.id.startsWith(localEntryPrefix) ?? false,
    );
  }

  void _emit() {
    if (!_ready || _holding || !ref.mounted) return;
    state = AsyncData(_compose());
  }

  void _setBase(TimeEntry? active) {
    _base = active;
    _lastKnown = false;
    _emit();
  }

  static List<QueuedWrite> _clockEvents(List<QueuedWrite>? all) =>
      (all ?? const <QueuedWrite>[])
          .where((w) => WriteKind.isTime(w.kind))
          .toList();

  void _onSavedChanged(List<QueuedWrite> all) {
    final before = _saved.length;
    _saved = _clockEvents(all);
    if (_saved.length < before) {
      // A saved event was recorded (or discarded): ask the server before
      // drawing, so the screen does not briefly say "not clocked in".
      _holding = true;
      unawaited(
        _quietRefresh().whenComplete(() {
          _holding = false;
          _emit();
        }),
      );
      return;
    }
    _emit();
  }

  bool get _canSaveOffline =>
      ref.read(offlineWritesSupportedProvider) &&
      ref.read(writeQueueProvider) != null;

  /// The phone itself says there is no connection, so do not wait out a
  /// connection attempt before saving.
  bool get _phoneIsOffline => ref.read(connectivityProvider).value == false;

  /// Where the phone is, only when this person chose to record it, and never
  /// at the cost of the clock itself: any problem or a slow fix is just "no
  /// position" and the clock event goes ahead without one.
  Future<GeoPoint?> _locationIfChosen() async {
    try {
      final on = await ref.read(clockLocationProvider.future);
      if (!on) return null;
      return await ref.read(locationServiceProvider).currentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Starts the clock. Returns a short note when the outcome needs explaining
  /// (for example the worker was already clocked in elsewhere); null otherwise.
  /// Throws [AppException] when nothing was recorded.
  Future<String?> clockIn(
    ProjectRef project, {
    String? taskId,
    String? taskTitle,
  }) async {
    if (_inFlight) return null;
    _inFlight = true;
    final repo = ref.read(timeRepositoryProvider)!;
    final uid = ref.read(currentUserIdProvider)!;
    final startedAt = DateTime.now();
    GeoPoint? point;
    try {
      point = await _locationIfChosen();
      if (_phoneIsOffline && _canSaveOffline) {
        return await _saveClockIn(project, taskId, taskTitle, point);
      }
      final entry = await repo
          .clockIn(projectId: project.id, taskId: taskId, at: point)
          .then((e) => e.withProject(project, taskTitle: taskTitle));
      await _remember(uid, entry);
      _setBase(entry);
      _refreshTotals();
      return null;
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.validation &&
          e.message.toLowerCase().contains('open time entry')) {
        await _quietReloadFrom(repo, uid);
        return "You were already clocked in, so no new entry was started.";
      }
      if (e.isNetwork && _canSaveOffline) {
        // Nothing was delivered, so saving it for later cannot double it.
        return await _saveClockIn(project, taskId, taskTitle, point);
      }
      if (e.outcomeUnknown) {
        final seen = await _lookup(repo);
        // Could not even ask the server: the outcome stays unknown.
        if (!seen.reached) rethrow;
        final active = seen.entry;
        if (active != null &&
            !active.clockInAt.isBefore(
              startedAt.subtract(const Duration(minutes: 2)),
            )) {
          final entry = active.projectName == null
              ? active.withProject(project, taskTitle: taskTitle)
              : active;
          await _remember(uid, entry);
          _setBase(entry);
          _refreshTotals();
          return 'You are clocked in. The confirmation was slow, so we checked.';
        }
        if (active == null) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and you are not clocked in. Please try again.",
          );
        }
      }
      rethrow;
    } finally {
      _inFlight = false;
    }
  }

  /// Stops the clock. Same return/throw rules as [clockIn].
  Future<String?> clockOut({int breakMinutes = 0}) async {
    final current = state.value?.active;
    if (_inFlight || current == null) return null;
    _inFlight = true;
    final repo = ref.read(timeRepositoryProvider)!;
    final uid = ref.read(currentUserIdProvider)!;
    GeoPoint? point;
    try {
      point = await _locationIfChosen();
      if (current.id.startsWith(localEntryPrefix)) {
        // The server does not have this shift yet: the clock-out goes after the
        // saved clock-in, in order.
        return await _saveClockOut(current, breakMinutes, point);
      }
      if (_phoneIsOffline && _canSaveOffline) {
        return await _saveClockOut(current, breakMinutes, point);
      }
      await repo.clockOut(current.id, breakMinutes: breakMinutes, at: point);
      await _remember(uid, null);
      _setBase(null);
      _refreshTotals();
      return null;
    } on AppException catch (e) {
      final alreadyClosed =
          e.kind == AppErrorKind.notFound ||
          (e.kind == AppErrorKind.validation &&
              e.message.toLowerCase().contains('already closed'));
      if (alreadyClosed) {
        await _quietReloadFrom(repo, uid);
        _refreshTotals();
        return 'That time entry was already closed.';
      }
      if (e.isNetwork && _canSaveOffline) {
        return await _saveClockOut(current, breakMinutes, point);
      }
      if (e.outcomeUnknown) {
        final seen = await _lookup(repo);
        if (!seen.reached) rethrow;
        final active = seen.entry;
        if (active == null) {
          await _remember(uid, null);
          _setBase(null);
          _refreshTotals();
          return 'You are clocked out. The confirmation was slow, so we checked.';
        }
        if (active.id == current.id) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and you are still clocked in. Please try again.",
          );
        }
      }
      rethrow;
    } finally {
      _inFlight = false;
    }
  }

  /// Saves a clock-in on the phone with the moment it happened.
  Future<String> _saveClockIn(
    ProjectRef project,
    String? taskId,
    String? taskTitle,
    GeoPoint? point,
  ) async {
    final queue = ref.read(writeQueueProvider)!;
    await queue.enqueue(
      kind: WriteKind.clockIn,
      stream: WriteKind.timeStream,
      payload: ClockInWrite(
        projectId: project.id,
        projectName: project.name,
        projectCode: project.code,
        taskId: taskId,
        taskTitle: taskTitle,
        occurredAt: eventTime(),
        position: point?.rounded,
      ).toJson(),
    );
    _saved = _clockEvents(await queue.all());
    _emit();
    unawaited(queue.flush());
    return 'Clocked in. Saved on this phone and sent when there is a connection.';
  }

  /// Saves a clock-out on the phone with the moment it happened, after the
  /// clock-in it closes (saved too, or already on the server).
  Future<String> _saveClockOut(
    TimeEntry current,
    int breakMinutes,
    GeoPoint? point,
  ) async {
    final queue = ref.read(writeQueueProvider)!;
    final isSaved = current.id.startsWith(localEntryPrefix);
    await queue.enqueue(
      kind: WriteKind.clockOut,
      stream: WriteKind.timeStream,
      payload: ClockOutWrite(
        occurredAt: eventTime(),
        entryId: isSaved ? null : current.id,
        dependsOn: isSaved
            ? current.id.substring(localEntryPrefix.length)
            : null,
        breakMinutes: breakMinutes,
        position: point?.rounded,
      ).toJson(),
    );
    _saved = _clockEvents(await queue.all());
    _emit();
    unawaited(queue.flush());
    return 'Clocked out. Saved on this phone and sent when there is a connection.';
  }

  /// Asks the server for the open entry. [reached] is false when it could not
  /// be asked, which must not be mistaken for "nobody is clocked in".
  Future<({bool reached, TimeEntry? entry})> _lookup(
    TimeRepository repo,
  ) async {
    try {
      return (reached: true, entry: await repo.active());
    } on AppException {
      return (reached: false, entry: null);
    }
  }

  Future<void> _quietReloadFrom(TimeRepository repo, String uid) async {
    try {
      final active = await repo.active();
      await _remember(uid, active);
      _setBase(active);
    } on AppException {
      // Leave the screen as it is.
    }
  }

  void _refreshTotals() {
    ref.invalidate(weekSummaryProvider);
    ref.invalidate(recentEntriesProvider);
  }

  // The last known state is stored so a worker who opens the app with no signal
  // still sees that they are clocked in. What the worker did since without a
  // connection is in the write queue, which is applied on top of it.
  Future<void> _remember(String uid, TimeEntry? active) async {
    final db = ref.read(appDatabaseProvider);
    await db.putCache(
      uid,
      _scope,
      _key,
      jsonEncode(active?.toJson() ?? const <String, dynamic>{}),
    );
  }

  Future<ClockState?> _recall(String uid) async {
    final row = await ref.read(appDatabaseProvider).getCache(uid, _scope, _key);
    if (row == null) return null;
    try {
      return ClockState(TimeEntry.tryParse(jsonDecode(row.json)));
    } catch (_) {
      return null;
    }
  }
}

final clockProvider = AsyncNotifierProvider<ClockController, ClockState>(
  ClockController.new,
);

/// This week's totals (Monday–Sunday, worker's local week).
final weekSummaryProvider = FutureProvider<WeeklySummary>((ref) async {
  final repo = ref.watch(timeRepositoryProvider);
  if (repo == null) {
    return WeeklySummary(
      weekStart: Fmt.weekStart(DateTime.now()),
      totalRegularHours: 0,
      totalOvertimeHours: 0,
      entries: const [],
    );
  }
  ref.watch(appResumeProvider);
  return repo.weeklySummary(Fmt.weekStart(DateTime.now()));
});

/// The worker's latest time entries, newest first.
final recentEntriesProvider = FutureProvider<List<TimeEntry>>((ref) async {
  final repo = ref.watch(timeRepositoryProvider);
  if (repo == null) return const [];
  ref.watch(appResumeProvider);
  return repo.entries(limit: 15);
});
