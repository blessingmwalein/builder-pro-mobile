import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../finance/application/finance_providers.dart'
    show companyDashboardProvider;
import '../../team/application/team_providers.dart';
import '../data/project_models.dart';
import '../data/projects_repository.dart';
import 'projects_providers.dart';

/// What the person changed on a project's basic details. Only what is set is
/// sent, so a field left alone is never overwritten with an old value. The server
/// cannot clear a date or the client, so these only ever change to another one.
class ProjectEdit {
  const ProjectEdit({
    this.name,
    this.description,
    this.projectType,
    this.siteAddress,
    this.startDate,
    this.endDate,
    this.clientId,
  });

  final String? name;
  final String? description;
  final String? projectType;
  final String? siteAddress;

  /// Calendar days (the date part is what counts).
  final DateTime? startDate;
  final DateTime? endDate;
  final String? clientId;

  bool get isEmpty => toBody().isEmpty;

  Map<String, dynamic> toBody() => {
    'name': ?name?.trim(),
    'description': ?description?.trim(),
    'projectType': ?projectType,
    'siteAddress': ?siteAddress?.trim(),
    if (startDate != null) 'startDate': _day(startDate!),
    if (endDate != null) 'endDate': _day(endDate!),
    'clientId': ?clientId,
  };

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Changing a project's status, details and manager (`projects.*`).
///
/// Each change is checked against the project as the server has it before it is
/// sent, and refused if someone else moved it since the screen was opened, so a
/// stale screen never overwrites a newer change. After a lost answer the project
/// is read back instead of resending: it says whether the change arrived.
class ProjectActions {
  ProjectActions(this._ref);
  final Ref _ref;

  ProjectsRepository get _repo => _ref.read(projectsRepositoryProvider);

  void _refresh(String id) {
    _ref.invalidate(projectDetailProvider(id));
    _ref.read(projectsCatalogProvider.notifier).refresh();
    _ref.invalidate(companyDashboardProvider);
  }

  Future<ProjectSummary?> _reread(String id) async {
    try {
      return await _repo.detail(id);
    } on AppException {
      return null;
    }
  }

  static const _timedOut =
      "That didn't go through and nothing was changed. Please try again.";
  static const _slow = 'Done. The confirmation was slow, so we checked.';

  /// Moves the project to [target] with [send], which is either the plain status
  /// change or the closing call. Returns a note when the outcome needs
  /// explaining; throws when nothing was changed.
  Future<String?> _moveStatus(
    ProjectSummary shown,
    String target,
    Future<void> Function() send,
  ) async {
    final before = await _repo.detail(shown.id);
    if (before.status != shown.status) {
      _refresh(shown.id);
      throw AppException(
        AppErrorKind.validation,
        'This project is now ${ProjectStatus.label(before.status)}. It was ${ProjectStatus.label(shown.status)} when you opened it. The page shows its current status.',
      );
    }
    try {
      await send();
      _refresh(shown.id);
      return null;
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      final fresh = await _reread(shown.id);
      // Could not even ask: the outcome stays unknown.
      if (fresh == null) rethrow;
      if (fresh.status == target) {
        _refresh(shown.id);
        return _slow;
      }
      if (fresh.status == shown.status) {
        throw const AppException(AppErrorKind.timeout, _timedOut);
      }
      _refresh(shown.id);
      throw AppException(
        AppErrorKind.validation,
        'This project is now ${ProjectStatus.label(fresh.status)}. The page shows its current status.',
      );
    }
  }

  /// Draft, Active, On hold or Archived. (Completed goes through [close], which
  /// also records the end date and the final cost summary.)
  Future<String?> changeStatus(ProjectSummary shown, String target) =>
      _moveStatus(
        shown,
        target,
        () => _repo.update(shown.id, {'status': target}),
      );

  /// Closes the project as completed, with optional closing notes.
  Future<String?> close(ProjectSummary shown, {String? notes}) => _moveStatus(
    shown,
    ProjectStatus.completed,
    () => _repo.close(shown.id, notes: notes),
  );

  /// Saves changed basic details. It sets the fields given, so it is sent once
  /// more after a lost answer.
  Future<void> updateDetails(String projectId, ProjectEdit edit) async {
    final body = edit.toBody();
    if (body.isEmpty) return;
    try {
      await _repo.update(projectId, body);
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await _repo.update(projectId, body);
    }
    _refresh(projectId);
  }

  /// Makes [userId] the project manager. Refused if a manager was assigned (or
  /// changed) since the screen was opened. Returns a note when the outcome needs
  /// explaining; throws when nothing was changed.
  Future<String?> assignManager(ProjectSummary shown, String userId) async {
    final before = await _repo.detail(shown.id);
    if (before.projectManagerId != shown.projectManagerId) {
      _refresh(shown.id);
      throw const AppException(
        AppErrorKind.validation,
        'The project manager was changed since you opened this. The page now shows who it is.',
      );
    }
    if (before.projectManagerId == userId) {
      return 'They are already the project manager.';
    }
    try {
      await _repo.update(shown.id, {'projectManagerId': userId});
      _refresh(shown.id);
      return null;
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      final fresh = await _reread(shown.id);
      // Could not even ask: the outcome stays unknown.
      if (fresh == null) rethrow;
      if (fresh.projectManagerId == userId) {
        _refresh(shown.id);
        return _slow;
      }
      if (fresh.projectManagerId == shown.projectManagerId) {
        throw const AppException(AppErrorKind.timeout, _timedOut);
      }
      _refresh(shown.id);
      throw const AppException(
        AppErrorKind.validation,
        'The project manager was changed while we were checking. The page now shows who it is.',
      );
    }
  }
}

final projectActionsProvider = Provider<ProjectActions>(
  (ref) => ProjectActions(ref),
);

/// A person's name from their id, for showing who the project manager is when
/// they are not on the project team. Null when the person cannot be read (it
/// needs permission to see the team list).
final personNameProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  userId,
) async {
  ref.watch(currentUserIdProvider);
  try {
    return (await ref.watch(teamRepositoryProvider).byId(userId))?.name;
  } on AppException {
    return null;
  }
});
