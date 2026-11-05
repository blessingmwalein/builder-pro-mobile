import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/project_time_models.dart';
import '../data/project_time_repository.dart';

final projectTimeRepositoryProvider = Provider<ProjectTimeRepository>(
  (ref) => ProjectTimeRepository(ref.watch(apiClientProvider)),
);

/// Every clock-in on one project (needs `timesheets.view_all`). Reads again when
/// the app comes back to the front, so people clocked in now stay current.
final projectTimeProvider = FutureProvider.autoDispose
    .family<ProjectTimeData, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      ref.watch(appResumeProvider);
      return ref.watch(projectTimeRepositoryProvider).forProject(projectId);
    });
