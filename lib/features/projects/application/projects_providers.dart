import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../tasks/data/task_list_repository.dart';
import '../../today/application/today_providers.dart';
import '../data/project_models.dart';
import '../data/projects_repository.dart';

final projectsRepositoryProvider = Provider<ProjectsRepository>(
  (ref) => ProjectsRepository(ref.watch(apiClientProvider)),
);

class ProjectsState {
  const ProjectsState({
    this.items = const [],
    this.query = '',
    this.status,
    this.page = 0,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
  });

  final List<ProjectSummary> items;
  final String query;

  /// Null = every status.
  final String? status;
  final int page;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final AppException? error;
  final AppException? loadMoreError;

  ProjectsState copyWith({
    List<ProjectSummary>? items,
    String? query,
    String? status,
    bool clearStatus = false,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppException? error,
    AppException? loadMoreError,
    bool clearError = false,
  }) => ProjectsState(
    items: items ?? this.items,
    query: query ?? this.query,
    status: clearStatus ? null : (status ?? this.status),
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

/// Project list with search, a status filter and paging.
class ProjectsCatalog extends Notifier<ProjectsState> {
  /// Bumped per request so a slow older reply cannot overwrite a newer one.
  int _generation = 0;

  @override
  ProjectsState build() {
    ref.watch(currentUserIdProvider);
    Future<void>.microtask(() => _loadFirst(query: '', status: null));
    return const ProjectsState();
  }

  Future<void> search(String query) {
    final q = query.trim();
    if (q == state.query && state.error == null) return Future.value();
    return _loadFirst(query: q, status: state.status);
  }

  Future<void> setStatus(String? status) {
    if (status == state.status && state.error == null) return Future.value();
    return _loadFirst(query: state.query, status: status);
  }

  Future<void> refresh() =>
      _loadFirst(query: state.query, status: state.status);

  Future<void> _loadFirst({
    required String query,
    required String? status,
  }) async {
    final gen = ++_generation;
    state = ProjectsState(query: query, status: status);
    try {
      final page = await ref
          .read(projectsRepositoryProvider)
          .list(search: query, status: status);
      if (gen != _generation || !ref.mounted) return;
      state = state.copyWith(
        items: page.items,
        page: page.page,
        hasMore: page.hasMore,
        loading: false,
      );
    } on AppException catch (e) {
      if (gen != _generation || !ref.mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final gen = _generation;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(projectsRepositoryProvider)
          .list(
            search: state.query,
            status: state.status,
            page: state.page + 1,
          );
      if (gen != _generation || !ref.mounted) return;
      final known = state.items.map((p) => p.id).toSet();
      state = state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((p) => !known.contains(p.id)),
        ],
        page: page.page,
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on AppException catch (e) {
      if (gen != _generation || !ref.mounted) return;
      state = state.copyWith(loadingMore: false, loadMoreError: e);
    }
  }
}

final projectsCatalogProvider =
    NotifierProvider<ProjectsCatalog, ProjectsState>(ProjectsCatalog.new);

/// One project with its team.
final projectDetailProvider = FutureProvider.autoDispose
    .family<ProjectSummary, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(projectsRepositoryProvider).detail(id);
    });

/// Every task of one project, all statuses (the server sorts by priority, then
/// due date). Capped at [TaskListRepository.pageSize]; `truncated` says so.
final projectTasksProvider = FutureProvider.autoDispose
    .family<TaskPage, String>((ref, projectId) {
      ref.watch(currentUserIdProvider);
      return ref.watch(taskListRepositoryProvider).list(projectId: projectId);
    });
