import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_repository.dart';
import 'auth/session_controller.dart';
import 'auth/session_state.dart';
import 'config/app_config.dart';
import 'errors/app_exception.dart';
import 'network/api_client.dart';
import 'network/server_features.dart';
import 'offline/app_database.dart';
import 'offline/database_connection.dart';
import 'permissions/permission_evaluator.dart';
import 'storage/token_store.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Test seam: lets tests inject fake HTTP while keeping the real client wiring.
final dioOverridesProvider = Provider<({Dio? main, Dio? refresh})>(
  (ref) => (main: null, refresh: null),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final overrides = ref.watch(dioOverridesProvider);
  final client = ApiClient(
    config: ref.watch(appConfigProvider),
    tokens: ref.watch(tokenStoreProvider),
    dio: overrides.main,
    refreshDio: overrides.refresh,
  );
  // Looked up lazily so there is no construction cycle with the session.
  client.onSessionExpired = () =>
      ref.read(sessionProvider.notifier).handleExpired();
  client.onSubscriptionBlocked = (AppException e) =>
      ref.read(sessionProvider.notifier).handleBlocked(e);
  client.onOfflineWritesSeen = (supported) =>
      ref.read(offlineWritesSupportedProvider.notifier).observe(supported);
  return client;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

/// Whether the session restores itself on creation. Tests switch this off to
/// drive bootstrap explicitly.
final sessionAutoBootstrapProvider = Provider<bool>((ref) => true);

final sessionProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

/// Effective permissions of the signed-in user (empty when signed out).
final permissionsProvider = Provider<PermissionEvaluator>((ref) {
  return ref.watch(sessionProvider.select((s) => s.permissions));
});

/// Hooks run on logout / session expiry to wipe user-specific local data
/// (cached tasks, drafts, queued operations) so nothing leaks to the next user.
class SessionCleanup {
  final List<Future<void> Function()> _hooks = [];
  final Map<String, Future<void> Function()> _keyed = {};
  final Map<String, Future<void> Function()> _before = {};

  void register(Future<void> Function() hook) => _hooks.add(hook);

  /// Like [register], but a second registration under the same [key] replaces
  /// the first, so a provider that rebuilds does not stack duplicates.
  void registerKeyed(String key, Future<void> Function() hook) =>
      _keyed[key] = hook;

  /// Runs when the person signs out, BEFORE the tokens are cleared, so it can
  /// still talk to the server (for example to stop alerts reaching this phone).
  /// Each hook is given a few seconds and then abandoned: it must never hold up
  /// signing out.
  void registerBeforeSignOut(String key, Future<void> Function() hook) =>
      _before[key] = hook;

  Future<void> runBeforeSignOut() async {
    for (final h in List.of(_before.values)) {
      try {
        await h().timeout(const Duration(seconds: 4));
      } catch (_) {
        // Never block sign-out.
      }
    }
  }

  Future<void> run() async {
    for (final h in [..._hooks, ..._keyed.values]) {
      try {
        await h();
      } catch (_) {
        // Cleanup must never block sign-out.
      }
    }
  }
}

final sessionCleanupProvider = Provider<SessionCleanup>((ref) {
  final cleanup = SessionCleanup();
  // Registered here (not where the database is first read) so a sign-out right
  // after a cold start still removes data cached by the previous run.
  cleanup.register(() => ref.read(appDatabaseProvider).wipe());
  return cleanup;
});

/// Local cache + queued changes. Tests override this with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openAppDatabaseConnection());
  ref.onDispose(db.close);
  return db;
});

/// Id of the signed-in user. Feature providers watch this so everything they
/// hold in memory resets when the account changes or the user signs out.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider.select((s) => s.me?.user.id)),
);

/// Counts app foreground events. Screens that show live data listen to it and
/// refresh when the worker comes back to the app.
class ResumeTick extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final appResumeProvider = NotifierProvider<ResumeTick, int>(ResumeTick.new);

/// Whether the phone reports a network connection. This is only a hint used to
/// trigger syncing and banners; requests are always attempted and judged by
/// their actual result.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});
