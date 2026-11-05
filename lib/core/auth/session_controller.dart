import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exception.dart';
import '../providers.dart';
import '../storage/token_store.dart';
import 'auth_models.dart';
import 'session_state.dart';

/// Owns the signed-in session: bootstrap/restore, login, logout and recovery.
class SessionController extends Notifier<SessionState> {
  Future<void>? _bootstrapping;

  @override
  SessionState build() {
    if (ref.watch(sessionAutoBootstrapProvider)) {
      Future<void>.microtask(bootstrap);
    }
    return const SessionState.bootstrapping();
  }

  /// Restores a stored session at app start. Concurrent calls share one run.
  Future<void> bootstrap() {
    return _bootstrapping ??= _bootstrap().whenComplete(
      () => _bootstrapping = null,
    );
  }

  Future<void> _bootstrap() async {
    final api = ref.read(apiClientProvider);
    final store = ref.read(tokenStoreProvider);
    final has = await api.restore();
    if (!ref.mounted) return;
    if (!has) {
      state = const SessionState.unauthenticated();
      return;
    }
    await _loadMe(cached: await _readCachedMe(store));
  }

  /// Signs in. Throws [AppException] so the login form can show it.
  Future<void> login({
    required String email,
    required String password,
    String? companySlug,
  }) async {
    final api = ref.read(apiClientProvider);
    final repo = ref.read(authRepositoryProvider);

    final tokens = await repo.login(
      email: email,
      password: password,
      companySlug: companySlug,
    );
    await api.setTokens(
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
    );
    try {
      final me = await repo.me();
      await _accept(me);
    } on AppException catch (e) {
      if (e.kind == AppErrorKind.subscription) {
        // Credentials are valid but the company is blocked. Keep the tokens so
        // "Check again" works after an administrator renews the subscription.
        state = SessionState.subscriptionBlocked(e);
        return;
      }
      await api.clearSession();
      rethrow;
    }
  }

  /// Re-reads `/auth/me` (permissions can change). Used on resume and "Check again".
  Future<void> refreshMe() async {
    final store = ref.read(tokenStoreProvider);
    await _loadMe(cached: await _readCachedMe(store));
  }

  Future<void> logout() async {
    // First, while the tokens still work (stop alerts reaching this phone).
    await ref.read(sessionCleanupProvider).runBeforeSignOut();
    await ref.read(apiClientProvider).clearSession();
    await ref.read(sessionCleanupProvider).run();
    state = const SessionState.unauthenticated();
  }

  /// Called by the API client when the refresh token is rejected.
  void handleExpired() {
    if (state.status == SessionStatus.unauthenticated ||
        state.status == SessionStatus.expired) {
      return;
    }
    unawaited(_wipe());
    state = const SessionState.expired();
  }

  /// Called by the API client on any HTTP 402.
  void handleBlocked(AppException error) {
    if (state.status == SessionStatus.subscriptionBlocked) return;
    state = SessionState.subscriptionBlocked(error, me: state.me);
  }

  Future<void> _wipe() async {
    await ref.read(apiClientProvider).clearSession();
    await ref.read(sessionCleanupProvider).run();
  }

  Future<void> _loadMe({Me? cached}) async {
    try {
      final me = await ref.read(authRepositoryProvider).me();
      await _accept(me);
    } on AppException catch (e) {
      switch (e.kind) {
        case AppErrorKind.subscription:
          state = SessionState.subscriptionBlocked(e, me: cached);
        case AppErrorKind.unauthorized:
          // The client already attempted a refresh; handleExpired() cleaned up.
          if (state.status != SessionStatus.expired) {
            await _wipe();
            state = const SessionState.expired();
          }
        case AppErrorKind.offline:
        case AppErrorKind.timeout:
        case AppErrorKind.uncertain:
          if (cached != null) {
            state = SessionState.authenticated(cached, offline: true);
          } else {
            state = SessionState.startupFailed(e);
          }
        default:
          state = SessionState.startupFailed(e);
      }
    }
  }

  Future<void> _accept(Me me) async {
    final api = ref.read(apiClientProvider);
    final store = ref.read(tokenStoreProvider);
    if (me.tenant.slug.isNotEmpty) await api.setTenantSlug(me.tenant.slug);
    await store.saveMeCache(jsonEncode(me.toJson()));
    state = SessionState.authenticated(me);
  }

  Future<Me?> _readCachedMe(TokenStore store) async {
    final raw = await store.readMeCache();
    if (raw == null) return null;
    try {
      return Me.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
