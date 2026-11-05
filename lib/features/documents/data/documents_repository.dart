import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'document_models.dart';

/// `/projects/:projectId/documents`.
///
/// Uploading creates a new document every time (no idempotency key), so it is
/// never resent; callers look the list up again after an uncertain failure.
class DocumentsRepository {
  DocumentsRepository(this._api);

  final ApiClient _api;

  /// A project's documents, newest first within each stage (one plain array).
  Future<List<ProjectDocument>> list(String projectId) async {
    final body = await _api.get('projects/$projectId/documents');
    final docs = J
        .list(body)
        .map(ProjectDocument.tryParse)
        .whereType<ProjectDocument>()
        .toList();
    docs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return docs;
  }

  /// Multipart field `file`; `name` and `type` ride along. NOT repeatable.
  /// The server writes the file to its own disk, so on hosting without a
  /// writable disk this fails (backend-gaps G5).
  Future<ProjectDocument> upload({
    required String projectId,
    required String path,
    required String fileName,
    required String contentType,
    required String type,
    String? name,
    void Function(int sent, int total)? onProgress,
  }) async {
    final body = await _api.postMultipart(
      'projects/$projectId/documents',
      () => FormData.fromMap({
        'file': MultipartFile.fromFileSync(
          path,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
        'type': type,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
      onProgress: onProgress,
    );
    final doc = ProjectDocument.tryParse(body);
    if (doc == null) {
      throw const AppException(
        AppErrorKind.uncertain,
        'The server replied, but the reply could not be read. The document may have been saved.',
      );
    }
    return doc;
  }
}
