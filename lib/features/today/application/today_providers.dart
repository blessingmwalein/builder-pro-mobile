import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../tasks/data/task_list_repository.dart';

final taskListRepositoryProvider = Provider<TaskListRepository>(
  (ref) => TaskListRepository(ref.watch(apiClientProvider)),
);

/// Open tasks across the company, for the supervisor's overview. Reloads when
/// the user returns to the app.
final openTasksProvider = FutureProvider<OpenTasks>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const OpenTasks([], truncated: false);
  ref.watch(appResumeProvider);
  return ref.watch(taskListRepositoryProvider).open();
});
