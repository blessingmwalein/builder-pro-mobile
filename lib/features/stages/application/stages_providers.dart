import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../data/stage_models.dart';
import '../data/stages_repository.dart';

final stagesRepositoryProvider = Provider<StagesRepository>(
  (ref) => StagesRepository(ref.watch(apiClientProvider)),
);

/// The stages of one project.
final projectStagesProvider = FutureProvider.autoDispose
    .family<List<ProjectStage>, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(stagesRepositoryProvider).list(projectId);
    });

/// Moving a stage between statuses and approving it.
class StageActions {
  StageActions(this._ref);
  final Ref _ref;

  StagesRepository get _repo => _ref.read(stagesRepositoryProvider);

  /// Sets a stage's status. It only sets a field, so after an uncertain failure
  /// it is sent once more; a second failure is reported.
  Future<void> setStatus(
    String projectId,
    String stageId,
    String status,
  ) async {
    Future<void> send() => _repo.setStatus(projectId, stageId, status);
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _ref.invalidate(projectStagesProvider(projectId));
  }

  /// Approves a stage that needs approval, which also completes it. A second
  /// approval answers 400, so after a timeout the stages are read back: a
  /// completed stage is what the user asked for, whoever completed it.
  /// Returns a note when the outcome needs explaining; throws when nothing was
  /// recorded.
  Future<String?> approve(String projectId, String stageId) async {
    try {
      await _repo.approve(projectId, stageId);
      _ref.invalidate(projectStagesProvider(projectId));
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        List<ProjectStage>? fresh;
        try {
          fresh = await _repo.list(projectId);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final now = fresh.where((s) => s.id == stageId).firstOrNull;
        if (now != null && now.isCompleted) {
          _ref.invalidate(projectStagesProvider(projectId));
          return 'Done. The confirmation was slow, so we checked.';
        }
        if (now != null) {
          throw const AppException(
            AppErrorKind.timeout,
            "That didn't go through and nothing was recorded. Please try again.",
          );
        }
        _ref.invalidate(projectStagesProvider(projectId));
        throw const AppException(
          AppErrorKind.validation,
          'This stage is no longer on the project. The page now shows its current stages.',
        );
      }
      if (e.kind == AppErrorKind.validation) {
        // Not needing approval, or already completed: the stages moved on.
        _ref.invalidate(projectStagesProvider(projectId));
      }
      rethrow;
    }
  }
}

final stageActionsProvider = Provider<StageActions>((ref) => StageActions(ref));
