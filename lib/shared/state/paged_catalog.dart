import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/providers.dart';

/// One page of results from a list endpoint.
@immutable
class PageResult<T> {
  const PageResult(this.items, {required this.page, required this.hasMore});
  final List<T> items;
  final int page;
  final bool hasMore;
}

@immutable
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.filter,
    this.page = 0,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
  });

  final List<T> items;

  /// Optional single filter (e.g. a status). Null = everything.
  final String? filter;
  final int page;
  final bool hasMore;

  /// The first page for the current filter is loading.
  final bool loading;
  final bool loadingMore;

  /// The first page failed; the list cannot be shown.
  final AppException? error;

  /// A later page failed; the loaded items stay on screen.
  final AppException? loadMoreError;

  PagedState<T> copyWith({
    List<T>? items,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    AppException? error,
    AppException? loadMoreError,
    bool clearErrors = false,
  }) => PagedState<T>(
    items: items ?? this.items,
    filter: filter,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearErrors ? null : (error ?? this.error),
    loadMoreError: clearErrors ? null : (loadMoreError ?? this.loadMoreError),
  );
}

/// A paged list with an optional filter: first page, "show more", refresh.
///
/// * A newer request always wins over a slower older one.
/// * A failed first page is an error state (never an empty list); a failed
///   later page keeps what is already shown.
/// * Everything resets when the signed-in user changes.
abstract class PagedCatalog<T> extends Notifier<PagedState<T>> {
  /// Reads one page. Must send `page` and `limit` to the API.
  Future<PageResult<T>> fetch({String? filter, int page = 1});

  /// Stable id, used to drop duplicates when pages overlap.
  String idOf(T item);

  int _generation = 0;

  @override
  PagedState<T> build() {
    ref.watch(currentUserIdProvider);
    Future<void>.microtask(() => _loadFirst(null));
    return PagedState<T>();
  }

  Future<void> setFilter(String? filter) {
    if (filter == state.filter && state.error == null) return Future.value();
    return _loadFirst(filter);
  }

  Future<void> refresh() => _loadFirst(state.filter);

  /// Drops one item from the loaded list (it was decided, deleted…).
  void removeById(String id) {
    state = state.copyWith(
      items: state.items.where((i) => idOf(i) != id).toList(),
    );
  }

  Future<void> _loadFirst(String? filter) async {
    final gen = ++_generation;
    state = PagedState<T>(filter: filter);
    try {
      final page = await fetch(filter: filter);
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
    state = state.copyWith(loadingMore: true, clearErrors: true);
    try {
      final page = await fetch(filter: state.filter, page: state.page + 1);
      if (gen != _generation || !ref.mounted) return;
      final known = state.items.map(idOf).toSet();
      state = state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((i) => !known.contains(idOf(i))),
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
