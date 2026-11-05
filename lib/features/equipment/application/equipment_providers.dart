import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/state/paged_catalog.dart';
import '../data/equipment_models.dart';
import '../data/equipment_repository.dart';

final equipmentRepositoryProvider = Provider<EquipmentRepository>(
  (ref) => EquipmentRepository(ref.watch(apiClientProvider)),
);

class EquipmentCatalog extends PagedCatalog<EquipmentSummary> {
  @override
  Future<PageResult<EquipmentSummary>> fetch({String? filter, int page = 1}) =>
      ref.read(equipmentRepositoryProvider).list(status: filter, page: page);

  @override
  String idOf(EquipmentSummary item) => item.id;
}

final equipmentCatalogProvider =
    NotifierProvider<EquipmentCatalog, PagedState<EquipmentSummary>>(
      EquipmentCatalog.new,
    );

/// The company's equipment categories (for the add / edit form).
final equipmentCategoriesProvider =
    FutureProvider.autoDispose<List<EquipmentCategory>>((ref) {
      ref.watch(currentUserIdProvider);
      return ref.watch(equipmentRepositoryProvider).categories();
    });

final equipmentDetailProvider = FutureProvider.autoDispose
    .family<EquipmentDetail, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(equipmentRepositoryProvider).get(id);
    });

const _changedMessage =
    'This equipment has changed since you opened it. The page now shows its current state.';
const _unavailableMessage =
    'This equipment is no longer available. The page now shows its current state.';

/// Assigning equipment to a project and taking it back.
///
/// Neither is queued or resent blindly. Assigning is checked against the item's
/// status by the server (a repeat answers 400), but returning closes the one
/// assignment it is told to, so a stale return could free equipment that has
/// since been sent elsewhere: it is re-read first, and read back after a
/// timeout.
class EquipmentActions {
  EquipmentActions(this._ref);
  final Ref _ref;

  EquipmentRepository get _repo => _ref.read(equipmentRepositoryProvider);

  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded.
  Future<String?> assign(
    String id, {
    required String projectId,
    required DateTime start,
    DateTime? end,
    String? notes,
  }) async {
    final startedAt = DateTime.now();
    try {
      await _repo.assign(
        id,
        projectId: projectId,
        start: start,
        end: end,
        notes: notes,
      );
      _changed(id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        final fresh = await _read(id);
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final me = _ref.read(currentUserIdProvider);
        final since = startedAt.subtract(const Duration(minutes: 2));
        final mine = fresh.openAssignments.any(
          (a) =>
              a.projectId == projectId &&
              a.assignedById == me &&
              (a.createdAt ?? startedAt).isAfter(since),
        );
        if (fresh.summary.isInUse && mine) {
          _changed(id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (fresh.summary.isAvailable) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _changed(id);
        throw const AppException(AppErrorKind.validation, _unavailableMessage);
      }
      if (e.kind == AppErrorKind.validation) {
        // The server refuses an item that is not available. Say that only when
        // it is true; any other 400 keeps the server's own words.
        final fresh = await _read(id);
        if (fresh != null && !fresh.summary.isAvailable) {
          _changed(id);
          throw const AppException(
            AppErrorKind.validation,
            _unavailableMessage,
          );
        }
      }
      rethrow;
    }
  }

  /// Adds a piece of equipment. It is never resent (a repeat would add another),
  /// so after an uncertain failure the newest items are read back: one with the
  /// same name made in the last two minutes means it arrived. Returns a note when
  /// the outcome needs explaining; throws when nothing was recorded.
  Future<String?> create({
    required String name,
    String? description,
    String? serialNumber,
    String? categoryId,
  }) async {
    final startedAt = DateTime.now();
    try {
      await _repo.create(
        name: name,
        description: description,
        serialNumber: serialNumber,
        categoryId: categoryId,
      );
      _ref.invalidate(equipmentCatalogProvider);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        PageResult<EquipmentSummary>? fresh;
        try {
          fresh = await _repo.list();
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final since = startedAt.subtract(const Duration(minutes: 2));
        final arrived = fresh.items.any(
          (i) =>
              i.name == name.trim() &&
              (i.createdAt ?? startedAt).isAfter(since),
        );
        if (arrived) {
          _ref.invalidate(equipmentCatalogProvider);
          return 'Added. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and nothing was added. Please try again.",
        );
      }
      rethrow;
    }
  }

  /// Changes an item's name, notes, serial number and category. It only sets
  /// fields, so after an uncertain failure it is sent once more; a second
  /// failure is reported.
  Future<void> updateDetails(
    String id, {
    required String name,
    String? description,
    String? serialNumber,
    String? categoryId,
  }) async {
    Future<void> send() => _repo.updateDetails(
      id,
      name: name,
      description: description,
      serialNumber: serialNumber,
      categoryId: categoryId,
    );
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _changed(id);
  }

  /// Moves an item that is not out on a project between available, maintenance
  /// and retired. An item in use is refused: its open assignment has to be
  /// closed first, or the item would say one thing and its history another.
  /// Sent once more after an uncertain failure.
  Future<void> setStatus(String id, String status) async {
    final current = await _repo.get(id);
    if (current.summary.isInUse || status == EquipmentStatus.inUse) {
      _changed(id);
      throw const AppException(
        AppErrorKind.validation,
        'This item is in use on a project. Mark it returned first.',
      );
    }
    Future<void> send() => _repo.setStatus(id, status);
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _changed(id);
  }

  /// Takes back the one open assignment of an item that is in use.
  Future<String?> returnItem(String id, String assignmentId) async {
    // Re-read first: closing a stale assignment id would free the item even if
    // it has been sent to another site since.
    final before = await _repo.get(id);
    final target = before.assignments
        .where((a) => a.id == assignmentId)
        .firstOrNull;
    if (target == null ||
        !target.isOpen ||
        before.returnable?.id != assignmentId) {
      _changed(id);
      throw const AppException(AppErrorKind.validation, _changedMessage);
    }
    try {
      await _repo.returnItem(id, assignmentId);
      _changed(id);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        final fresh = await _read(id);
        if (fresh == null) rethrow;
        final now = fresh.assignments
            .where((a) => a.id == assignmentId)
            .firstOrNull;
        if (now != null && !now.isOpen) {
          _changed(id);
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (now != null && now.isOpen && fresh.summary.isInUse) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _changed(id);
        throw const AppException(AppErrorKind.validation, _changedMessage);
      }
      if (e.kind == AppErrorKind.validation) {
        _changed(id);
        throw const AppException(AppErrorKind.validation, _changedMessage);
      }
      rethrow;
    }
  }

  Future<EquipmentDetail?> _read(String id) async {
    try {
      return await _repo.get(id);
    } on AppException {
      return null;
    }
  }

  void _changed(String id) {
    _ref.invalidate(equipmentDetailProvider(id));
    _ref.invalidate(equipmentCatalogProvider);
  }
}

final equipmentActionsProvider = Provider<EquipmentActions>(
  (ref) => EquipmentActions(ref),
);
