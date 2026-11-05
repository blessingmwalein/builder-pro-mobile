import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'project_models.dart';

/// `/projects` read access for supervisors and managers.
class ProjectsRepository {
  ProjectsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// Newest first. `page` and `limit` are always sent.
  Future<ProjectPage> list({
    String? search,
    String? status,
    int page = 1,
  }) async {
    final body = await _api.get(
      'projects',
      query: {
        'page': page,
        'limit': pageSize,
        'search': search?.trim(),
        'status': status,
      },
    );
    final paged = J.paged(body);
    return ProjectPage(
      paged.items
          .map(ProjectSummary.tryParse)
          .whereType<ProjectSummary>()
          .toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }

  /// `GET /projects/:id` — includes the team. Money fields in the reply are
  /// ignored (see [ProjectSummary]).
  Future<ProjectSummary> detail(String id) async {
    final body = await _api.get('projects/$id');
    final project = ProjectSummary.tryParse(body);
    if (project == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected project response.',
      );
    }
    return project;
  }

  /// `PUT /projects/:id` (needs `projects.*`). Only the fields in [changes] are
  /// sent, and the server leaves the rest alone, so sending it twice leaves the
  /// same project. It cannot clear a date or the client.
  Future<void> update(String id, Map<String, dynamic> changes) async {
    await _api.put('projects/$id', body: changes);
  }

  /// `POST /projects/:id/close` (needs `projects.*`): marks the project
  /// completed, 100% done, ends it today and saves a final cost summary. The
  /// summary in the reply is not read: it lists each worker's pay.
  Future<void> close(String id, {String? notes}) async {
    final n = notes?.trim();
    await _api.post(
      'projects/$id/close',
      body: {if (n != null && n.isNotEmpty) 'notes': n},
    );
  }
}
