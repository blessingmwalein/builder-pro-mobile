import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../data/document_models.dart';
import '../data/documents_repository.dart';

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DocumentsRepository(ref.watch(apiClientProvider)),
);

/// A project's documents.
final projectDocumentsProvider = FutureProvider.autoDispose
    .family<List<ProjectDocument>, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(documentsRepositoryProvider).list(projectId);
    });

/// Adding a document to a project.
class DocumentActions {
  DocumentActions(this._ref);
  final Ref _ref;

  DocumentsRepository get _repo => _ref.read(documentsRepositoryProvider);

  /// Uploads one file. It is never resent (a second upload would be a second
  /// document), so after an uncertain failure the list is read back: a new
  /// document of the user's own with the same name, made in the last few
  /// minutes, means it arrived. Returns a note when the outcome needs
  /// explaining; throws when nothing was recorded.
  Future<String?> upload({
    required String projectId,
    required String path,
    required String fileName,
    required String contentType,
    required String type,
    void Function(int sent, int total)? onProgress,
  }) async {
    final startedAt = DateTime.now();
    final me = _ref.read(currentUserIdProvider);
    List<ProjectDocument> before;
    try {
      before = await _repo.list(projectId);
    } on AppException {
      before = const [];
    }
    try {
      await _repo.upload(
        projectId: projectId,
        path: path,
        fileName: fileName,
        contentType: contentType,
        type: type,
        onProgress: onProgress,
      );
      _ref.invalidate(projectDocumentsProvider(projectId));
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        List<ProjectDocument>? fresh;
        try {
          fresh = await _repo.list(projectId);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final known = before.map((d) => d.id).toSet();
        final since = startedAt.subtract(const Duration(minutes: 3));
        final arrived = fresh.any(
          (d) =>
              !known.contains(d.id) &&
              d.name == fileName &&
              d.uploaderId == me &&
              d.createdAt.isAfter(since),
        );
        if (arrived) {
          _ref.invalidate(projectDocumentsProvider(projectId));
          return 'Done. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and no document was added. Please try again.",
        );
      }
      rethrow;
    }
  }
}

final documentActionsProvider = Provider<DocumentActions>(
  (ref) => DocumentActions(ref),
);
