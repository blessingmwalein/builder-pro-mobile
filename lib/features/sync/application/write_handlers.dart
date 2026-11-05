import '../../../core/offline/app_database.dart';
import '../../../core/offline/write_queue.dart';
import '../../materials/data/material_models.dart';
import '../../materials/data/materials_repository.dart';
import '../../time/data/time_repository.dart';
import '../data/queued_write_models.dart';

const _unreadable = ReadyCheck.refuse(
  'This saved entry could not be read, so it cannot be sent. Discard it.',
);

/// Sends a clock-in saved offline. Held back until the server has said it reads
/// the real time of a clock event: without that it would stamp the time of
/// sending instead of the time the worker clocked in.
class ClockInHandler implements WriteHandler {
  ClockInHandler(this._repo, this._serverReadsEventTime);

  final TimeRepository _repo;
  final bool Function() _serverReadsEventTime;

  @override
  String get kind => WriteKind.clockIn;

  @override
  Future<ReadyCheck> readiness(QueuedWrite write, List<QueuedWrite> all) async {
    if (write.asClockIn == null) return _unreadable;
    return _serverReadsEventTime() ? ReadyCheck.ready : ReadyCheck.wait;
  }

  @override
  Future<String?> send(QueuedWrite write) async {
    final p = write.asClockIn!;
    final entry = await _repo.clockIn(
      projectId: p.projectId,
      taskId: p.taskId,
      at: p.position?.rounded,
      occurredAt: p.occurredAt,
    );
    return entry.id;
  }

  /// The server keeps the exact moment, so an earlier attempt shows up as an
  /// entry of this worker that started at it.
  @override
  Future<WriteArrival> arrived(QueuedWrite write) async {
    final p = write.asClockIn!;
    final entries = await _repo.entries(
      from: p.occurredAt.subtract(const Duration(minutes: 5)),
      to: p.occurredAt.add(const Duration(minutes: 5)),
      limit: 50,
    );
    for (final e in entries) {
      if (sameMoment(e.clockInAt, p.occurredAt)) {
        return WriteArrival.found(e.id);
      }
    }
    return const WriteArrival.missing();
  }
}

/// Sends a clock-out saved offline, for an entry the server already has or one
/// that a queued clock-in is about to create.
class ClockOutHandler implements WriteHandler {
  ClockOutHandler(this._repo, this._serverReadsEventTime);

  final TimeRepository _repo;
  final bool Function() _serverReadsEventTime;

  @override
  String get kind => WriteKind.clockOut;

  @override
  Future<ReadyCheck> readiness(QueuedWrite write, List<QueuedWrite> all) async {
    final p = write.asClockOut;
    if (p == null) return _unreadable;
    if (p.targetEntryId == null) {
      // It closes the entry a clock-in will create: wait for that clock-in, and
      // if it is gone (discarded) this can never be sent.
      final waitingFor = p.dependsOn;
      if (waitingFor != null && all.any((w) => w.id == waitingFor)) {
        return ReadyCheck.wait;
      }
      return const ReadyCheck.refuse(
        'The clock-in for this shift is no longer saved, so this clock-out cannot be sent. Discard it.',
      );
    }
    return _serverReadsEventTime() ? ReadyCheck.ready : ReadyCheck.wait;
  }

  @override
  Future<String?> send(QueuedWrite write) async {
    final p = write.asClockOut!;
    await _repo.clockOut(
      p.targetEntryId!,
      breakMinutes: p.breakMinutes,
      at: p.position?.rounded,
      occurredAt: p.occurredAt,
    );
    return null;
  }

  /// The entry is closed at exactly the moment this clock-out recorded.
  @override
  Future<WriteArrival> arrived(QueuedWrite write) async {
    final p = write.asClockOut!;
    final id = p.targetEntryId!;
    final entries = await _repo.entries(
      from: p.occurredAt.subtract(const Duration(days: 3)),
      to: p.occurredAt,
      limit: 50,
    );
    for (final e in entries) {
      final out = e.clockOutAt;
      if (e.id == id && out != null && sameMoment(out, p.occurredAt)) {
        return const WriteArrival.found();
      }
    }
    return const WriteArrival.missing();
  }
}

/// Sends material usage saved offline. The server already stores the time it is
/// given, so this needs nothing new from it.
class MaterialUsageHandler implements WriteHandler {
  MaterialUsageHandler(this._repo);

  final MaterialsRepository _repo;

  @override
  String get kind => WriteKind.materialUsage;

  @override
  Future<ReadyCheck> readiness(
    QueuedWrite write,
    List<QueuedWrite> all,
  ) async => write.asUsage == null ? _unreadable : ReadyCheck.ready;

  @override
  Future<String?> send(QueuedWrite write) async {
    final p = write.asUsage!;
    final log = await _repo.logUsage(
      material: MaterialItem(
        id: p.materialId,
        name: p.materialName,
        unit: p.unit,
        unitCost: p.unitCost,
        stockOnHand: 0,
      ),
      projectId: p.projectId,
      projectName: p.projectName,
      quantity: p.quantity,
      notes: p.notes,
      usedAt: p.occurredAt,
    );
    return log.id;
  }

  /// A log of the same project and material, with this quantity, used at
  /// exactly this moment.
  @override
  Future<WriteArrival> arrived(QueuedWrite write) async {
    final p = write.asUsage!;
    final logs = await _repo.recentLogs(
      projectId: p.projectId,
      materialId: p.materialId,
      limit: 20,
    );
    for (final l in logs) {
      if (sameMoment(l.usedAt, p.occurredAt) &&
          (l.quantity - p.quantity).abs() < 0.0005) {
        return WriteArrival.found(l.id);
      }
    }
    return const WriteArrival.missing();
  }
}
