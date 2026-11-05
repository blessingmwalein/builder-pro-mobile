import '../../../core/network/api_client.dart';
import '../../../core/utils/json.dart';
import '../../../shared/state/paged_catalog.dart';
import 'team_models.dart';

/// `GET /users`: the company's active people (needs `employees.*` or
/// `settings.*`). Read only; inviting and managing people stays on the web app.
class TeamRepository {
  TeamRepository(this._api);

  final ApiClient _api;

  static const pageSize = 20;

  /// `GET /users/:id`: one person (needs `employees.*` or `settings.*`).
  Future<TeamMember?> byId(String id) async =>
      TeamMember.tryParse(await _api.get('users/$id'));

  /// Active people, newest first. [search] matches the name or the email.
  Future<PageResult<TeamMember>> list({String? search, int page = 1}) async {
    final body = await _api.get(
      'users',
      query: {
        'page': page,
        'limit': pageSize,
        'isActive': true,
        'search': search?.trim(),
      },
    );
    final paged = J.paged(body);
    return PageResult(
      paged.items.map(TeamMember.tryParse).whereType<TeamMember>().toList(),
      page: paged.page,
      hasMore: paged.hasMore,
    );
  }
}
