import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';
import '../../../shared/state/paged_catalog.dart';
import '../data/client_models.dart';
import '../data/clients_repository.dart';

final clientsRepositoryProvider = Provider<ClientsRepository>(
  (ref) => ClientsRepository(ref.watch(apiClientProvider)),
);

/// The client list; its single filter is the search text.
class ClientsCatalog extends PagedCatalog<ClientSummary> {
  @override
  Future<PageResult<ClientSummary>> fetch({String? filter, int page = 1}) =>
      ref.read(clientsRepositoryProvider).list(search: filter, page: page);

  @override
  String idOf(ClientSummary item) => item.id;
}

final clientsCatalogProvider =
    NotifierProvider<ClientsCatalog, PagedState<ClientSummary>>(
      ClientsCatalog.new,
    );

final clientDetailProvider = FutureProvider.autoDispose
    .family<ClientDetail, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(clientsRepositoryProvider).get(id);
    });

/// The people with a client portal login for a client (they can be messaged).
final clientPortalUsersProvider = FutureProvider.autoDispose
    .family<List<ClientPortalUser>, String>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.watch(clientsRepositoryProvider).portalUsers(id);
    });

/// Adding and changing clients.
class ClientActions {
  ClientActions(this._ref);
  final Ref _ref;

  ClientsRepository get _repo => _ref.read(clientsRepositoryProvider);

  /// Adds a client. It is never resent (a repeat would add another), so after
  /// an uncertain failure the clients are searched by name: one with that name
  /// made in the last two minutes means it arrived. Returns a note when the
  /// outcome needs explaining; throws when nothing was recorded.
  Future<String?> create(ClientInput input) async {
    final startedAt = DateTime.now();
    try {
      await _repo.create(input);
      _ref.invalidate(clientsCatalogProvider);
      return null;
    } on AppException catch (e) {
      if (e.outcomeUnknown) {
        PageResult<ClientSummary>? fresh;
        try {
          fresh = await _repo.list(search: input.name);
        } on AppException {
          fresh = null;
        }
        // Could not even ask: the outcome stays unknown.
        if (fresh == null) rethrow;
        final since = startedAt.subtract(const Duration(minutes: 2));
        final arrived = fresh.items.any(
          (c) =>
              c.name == input.name.trim() &&
              (c.createdAt ?? startedAt).isAfter(since),
        );
        if (arrived) {
          _ref.invalidate(clientsCatalogProvider);
          return 'Added. The confirmation was slow, so we checked.';
        }
        throw const AppException(
          AppErrorKind.timeout,
          "That didn't go through and no client was added. Please try again.",
        );
      }
      rethrow;
    }
  }

  /// Changes a client. It only sets fields, so after an uncertain failure it is
  /// sent once more; a second failure is reported.
  Future<void> update(String id, ClientInput input) async {
    Future<void> send() => _repo.update(id, input);
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    _ref.invalidate(clientDetailProvider(id));
    _ref.invalidate(clientsCatalogProvider);
  }
}

final clientActionsProvider = Provider<ClientActions>(
  (ref) => ClientActions(ref),
);
