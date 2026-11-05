import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../shared/state/paged_catalog.dart';
import '../data/team_models.dart';
import '../data/team_repository.dart';

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(apiClientProvider)),
);

/// The people list; its single filter is the search text.
class TeamCatalog extends PagedCatalog<TeamMember> {
  @override
  Future<PageResult<TeamMember>> fetch({String? filter, int page = 1}) =>
      ref.read(teamRepositoryProvider).list(search: filter, page: page);

  @override
  String idOf(TeamMember item) => item.id;
}

final teamCatalogProvider =
    NotifierProvider<TeamCatalog, PagedState<TeamMember>>(TeamCatalog.new);
