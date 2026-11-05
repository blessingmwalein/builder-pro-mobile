import 'dart:convert';

import 'package:builder_pro_mobile/core/auth/auth_repository.dart';
import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/core/offline/app_database.dart';
import 'package:builder_pro_mobile/core/providers.dart';
import 'package:builder_pro_mobile/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

Dio _dio(FakeAdapter a) => Dio(
  BaseOptions(
    baseUrl: 'https://api.test/api/v1/',
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ),
)..httpClientAdapter = a;

class Env {
  Env() {
    container = ProviderContainer(
      overrides: [
        sessionAutoBootstrapProvider.overrideWithValue(false),
        tokenStoreProvider.overrideWithValue(store),
        appDatabaseProvider.overrideWithValue(db),
        dioOverridesProvider.overrideWithValue((
          main: _dio(main),
          refresh: _dio(refresh),
        )),
      ],
      retry: (_, _) => null,
    );
    container.read(sessionCleanupProvider).register(() async => cleaned++);
  }

  final store = MemoryTokenStore();
  final db = AppDatabase(NativeDatabase.memory());
  final main = FakeAdapter();
  final refresh = FakeAdapter();
  late final ProviderContainer container;
  int cleaned = 0;

  SessionState get state => container.read(sessionProvider);
  Future<void> bootstrap() =>
      container.read(sessionProvider.notifier).bootstrap();

  Reply tokens() => Reply.json({
    'accessToken': 'acc',
    'refreshToken': 'ref',
    'tokenType': 'Bearer',
    'expiresIn': '15m',
  }, status: 201);

  void dispose() {
    container.dispose();
    db.close();
  }
}

void main() {
  late Env env;
  setUp(() => env = Env());
  tearDown(() => env.dispose());

  test('bootstrap with no stored session → unauthenticated', () async {
    await env.bootstrap();
    expect(env.state.status, SessionStatus.unauthenticated);
  });

  test('login success stores tokens, slug and permissions', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    env.main.on('GET', 'auth/me', (_) => Reply.json(meJson()));

    await env.container
        .read(sessionProvider.notifier)
        .login(email: 'tendai@acme.test', password: 'password1');

    expect(env.state.status, SessionStatus.authenticated);
    expect(env.state.permissions.has('tasks.complete'), isTrue);
    expect(env.state.permissions.has('invoices.view'), isFalse);
    expect(await env.store.readAccessToken(), 'acc');
    expect(await env.store.readTenantSlug(), 'acme');
    expect(await env.store.readMeCache(), isNotNull);

    // The login call must not carry credentials; /auth/me must.
    expect(
      env.main.last('POST', 'auth/login').headers.containsKey('Authorization'),
      isFalse,
    );
    expect(
      env.main.last('GET', 'auth/me').headers['Authorization'],
      'Bearer acc',
    );
  });

  test('wrong password throws and leaves the user signed out', () async {
    env.main.on(
      'POST',
      'auth/login',
      (_) => Reply.json({'message': 'Invalid credentials'}, status: 401),
    );
    await expectLater(
      env.container
          .read(sessionProvider.notifier)
          .login(email: 'a@b.co', password: 'badbadbad'),
      throwsA(isA<AppException>()),
    );
    expect(await env.store.readAccessToken(), isNull);
  });

  test('email in several companies: error is recognised and companySlug is sent on retry', () async {
    env.main.on('POST', 'auth/login', (o) {
      final body = o.data as Map;
      return body.containsKey('companySlug')
          ? env.tokens()
          : Reply.json({
              'message': 'Multiple accounts found for this email. Please include companySlug.',
            }, status: 401);
    });
    env.main.on('GET', 'auth/me', (_) => Reply.json(meJson()));
    final c = env.container.read(sessionProvider.notifier);

    try {
      await c.login(email: 'a@b.co', password: 'password1');
      fail('should have thrown');
    } on AppException catch (e) {
      expect(isMultipleAccountsError(e), isTrue);
    }

    await c.login(email: 'a@b.co', password: 'password1', companySlug: 'acme');
    expect(env.state.status, SessionStatus.authenticated);
    expect(
      env.main.last('POST', 'auth/login').data,
      containsPair('companySlug', 'acme'),
    );
  });

  test('402 on /auth/me after login → subscription blocked, tokens kept for "Check again"', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    var blocked = true;
    env.main.on(
      'GET',
      'auth/me',
      (_) => blocked
          ? Reply.json({
              'statusCode': 402,
              'message': 'Your free trial has expired.',
              'code': 'TRIAL_EXPIRED',
            }, status: 402)
          : Reply.json(meJson()),
    );

    await env.container
        .read(sessionProvider.notifier)
        .login(email: 'a@b.co', password: 'password1');
    expect(env.state.status, SessionStatus.subscriptionBlocked);
    expect(env.state.subscriptionCode, 'TRIAL_EXPIRED');
    expect(await env.store.readRefreshToken(), 'ref');

    blocked = false;
    await env.container.read(sessionProvider.notifier).refreshMe();
    expect(env.state.status, SessionStatus.authenticated);
  });

  test('server error during login clears the half-created session', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    env.main.on('GET', 'auth/me', (_) => Reply.json({}, status: 500));
    await expectLater(
      env.container
          .read(sessionProvider.notifier)
          .login(email: 'a@b.co', password: 'password1'),
      throwsA(isA<AppException>()),
    );
    expect(await env.store.readRefreshToken(), isNull);
  });

  test('bootstrap restores a stored session', () async {
    await env.store.saveTokens(accessToken: 'acc', refreshToken: 'ref');
    await env.store.saveTenantSlug('acme');
    env.main.on(
      'GET',
      'auth/me',
      (_) => Reply.json(meJson(permissions: supervisorPerms)),
    );

    await env.bootstrap();

    expect(env.state.status, SessionStatus.authenticated);
    expect(env.state.permissions.has('timesheets.view_all'), isTrue);
    expect(env.state.offline, isFalse);
  });

  test(
    'bootstrap offline with a cached profile opens read-only offline',
    () async {
      await env.store.saveTokens(accessToken: 'acc', refreshToken: 'ref');
      await env.store.saveMeCache(jsonEncode(meJson()));
      env.main.on(
        'GET',
        'auth/me',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );

      await env.bootstrap();

      expect(env.state.status, SessionStatus.authenticated);
      expect(env.state.offline, isTrue);
      expect(await env.store.readRefreshToken(), 'ref'); // not logged out
    },
  );

  test(
    'bootstrap offline with nothing cached → startup failed (retryable)',
    () async {
      await env.store.saveTokens(accessToken: 'acc', refreshToken: 'ref');
      env.main.on(
        'GET',
        'auth/me',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      await env.bootstrap();
      expect(env.state.status, SessionStatus.startupFailed);
      expect(await env.store.readRefreshToken(), 'ref');
    },
  );

  test(
    'refresh token rejected at startup → expired, storage and caches wiped',
    () async {
      await env.store.saveTokens(accessToken: 'old', refreshToken: 'ref');
      env.main.on('GET', 'auth/me', (_) => Reply.json({}, status: 401));
      env.refresh.on(
        'POST',
        'auth/refresh',
        (_) => Reply.json({'message': 'Invalid refresh token'}, status: 401),
      );

      await env.bootstrap();
      await Future<void>.delayed(
        Duration.zero,
      ); // let the fire-and-forget wipe finish

      expect(env.state.status, SessionStatus.expired);
      expect(await env.store.readRefreshToken(), isNull);
      expect(env.cleaned, greaterThan(0));
    },
  );

  test('logout clears credentials, runs cleanup hooks and signs out', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    env.main.on('GET', 'auth/me', (_) => Reply.json(meJson()));
    final c = env.container.read(sessionProvider.notifier);
    await c.login(email: 'a@b.co', password: 'password1');

    await c.logout();

    expect(env.state.status, SessionStatus.unauthenticated);
    expect(await env.store.readAccessToken(), isNull);
    expect(await env.store.readMeCache(), isNull);
    expect(env.cleaned, 1);
  });

  test('logout wipes cached tasks and queued offline changes', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    env.main.on('GET', 'auth/me', (_) => Reply.json(meJson()));
    final c = env.container.read(sessionProvider.notifier);
    await c.login(email: 'a@b.co', password: 'password1');
    await env.db.replaceCache('u1', 'task', [(key: 'a', json: '{"id":"a"}')]);
    await env.db.putCache('u1', 'time_active', 'current', '{"id":"te1"}');
    await env.db.enqueue(
      id: 'op1',
      userId: 'u1',
      kind: 'task_status',
      targetId: 'a',
      payload: '{"status":"DONE"}',
    );

    await c.logout();

    expect(await env.db.readCache('u1', 'task'), isEmpty);
    expect(await env.db.getCache('u1', 'time_active', 'current'), isNull);
    expect(await env.db.outboxFor('u1'), isEmpty);
  });

  test('an expired session also wipes them', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    env.main.on('GET', 'auth/me', (_) => Reply.json(meJson()));
    final c = env.container.read(sessionProvider.notifier);
    await c.login(email: 'a@b.co', password: 'password1');
    await env.db.putCache('u1', 'task', 'a', '{"id":"a"}');

    c.handleExpired();
    await pumpEventQueue(times: 20);

    expect(env.state.status, SessionStatus.expired);
    expect(await env.db.readCache('u1', 'task'), isEmpty);
  });

  test('permissions update when /auth/me changes', () async {
    env.main.on('POST', 'auth/login', (_) => env.tokens());
    var perms = workerPerms;
    env.main.on(
      'GET',
      'auth/me',
      (_) => Reply.json(meJson(permissions: perms)),
    );
    final c = env.container.read(sessionProvider.notifier);
    await c.login(email: 'a@b.co', password: 'password1');
    expect(env.state.permissions.has('materials.log'), isTrue);

    perms = ['tasks.view'];
    await c.refreshMe();
    expect(env.state.permissions.has('materials.log'), isFalse);
  });
}
