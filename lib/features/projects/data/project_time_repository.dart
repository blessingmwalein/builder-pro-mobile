import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import 'project_time_models.dart';

/// A project's clock-ins, for people who may see everyone's time
/// (`timesheets.view_all`).
class ProjectTimeRepository {
  ProjectTimeRepository(this._api);

  final ApiClient _api;

  /// The server's largest page.
  static const pageSize = 100;

  /// Reading stops after this many pages; the newest entries come first, so what
  /// is left out is the oldest.
  static const maxPages = 30;

  /// Every entry the app reads at most.
  static const maxEntries = pageSize * maxPages;

  /// `GET /time-tracking?projectId=…`, newest first, a page at a time (`page` and
  /// `limit` are always sent). Only the hours, times, status and the worker's name
  /// are kept: the pay the server also sends is never read.
  Future<ProjectTimeData> forProject(String projectId) async {
    final byId = <String, TimeSlice>{};
    var more = true;
    var page = 1;
    while (more && page <= maxPages) {
      final paged = J.paged(
        await _api.get(
          'time-tracking',
          query: {'projectId': projectId, 'page': page, 'limit': pageSize},
        ),
      );
      for (final item in paged.items) {
        final s = TimeSlice.tryParse(item);
        // An entry added while paging can shift the pages: keep each once.
        if (s != null) byId[s.id] = s;
      }
      more = paged.hasMore;
      page++;
    }
    return ProjectTimeData(slices: byId.values.toList(), truncated: more);
  }
}
