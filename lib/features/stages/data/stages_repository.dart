import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'stage_models.dart';

/// `/projects/:projectId/stages`.
///
/// Changing a status only sets a field (the web app sends the same single
/// field), so it may be sent once more after an uncertain failure. Approving
/// answers 400 the second time ("already completed"), so callers read the
/// stages back instead of resending it.
class StagesRepository {
  StagesRepository(this._api);

  final ApiClient _api;

  /// The stages of a project, as one plain array (not paged).
  Future<List<ProjectStage>> list(String projectId) async {
    final body = await _api.get('projects/$projectId/stages');
    return J
        .maps(body)
        .map(ProjectStage.tryParse)
        .whereType<ProjectStage>()
        .toList();
  }

  Future<void> setStatus(
    String projectId,
    String stageId,
    String status,
  ) async {
    await _api.patch(
      'projects/$projectId/stages/$stageId',
      body: {'status': status},
    );
  }

  Future<void> approve(String projectId, String stageId) async {
    await _api.post('projects/$projectId/stages/$stageId/approve', body: {});
  }
}
