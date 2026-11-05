import 'package:builder_pro_mobile/core/config/app_config.dart';
import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/core/network/api_client.dart';
import 'package:builder_pro_mobile/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';

const _config = AppConfig(apiBaseUrl: 'https://api.test/api/v1');

class Harness {
  Harness() {
    api = ApiClient(
      config: _config,
      tokens: store,
      dio: Dio(
        BaseOptions(
          baseUrl: 'https://api.test/api/v1/',
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      )..httpClientAdapter = main,
      refreshDio: Dio(
        BaseOptions(
          baseUrl: 'https://api.test/api/v1/',
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      )..httpClientAdapter = refresh,
    );
    api.onSessionExpired = () => expired++;
    api.onSubscriptionBlocked = (e) => blockedCodes.add(e.code);
  }

  final store = MemoryTokenStore();
  final main = FakeAdapter();
  final refresh = FakeAdapter();
  late final ApiClient api;
  int expired = 0;
  final blockedCodes = <String?>[];

  Future<void> signIn({
    String access = 'old-access',
    String refreshToken = 'old-refresh',
  }) async {
    await api.setTokens(accessToken: access, refreshToken: refreshToken);
    await api.setTenantSlug('acme');
  }
}

Reply _tokens(String a, String r) => Reply.json({
  'accessToken': a,
  'refreshToken': r,
  'tokenType': 'Bearer',
  'expiresIn': '15m',
}, status: 201);

void main() {
  group('headers', () {
    test('adds bearer token and tenant slug to authenticated calls', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('GET', 'tasks/my-queue', (_) => Reply.json([]));
      await h.api.get('tasks/my-queue');
      final sent = h.main.last('GET', 'tasks/my-queue').headers;
      expect(sent['Authorization'], 'Bearer old-access');
      expect(sent['x-tenant-slug'], 'acme');
    });

    test('public calls send no credentials', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('POST', 'auth/login', (_) => _tokens('a', 'r'));
      await h.api.post(
        'auth/login',
        auth: false,
        body: {'email': 'a@b.c', 'password': 'x'},
      );
      final sent = h.main.last('POST', 'auth/login').headers;
      expect(sent.containsKey('Authorization'), isFalse);
      expect(sent.containsKey('x-tenant-slug'), isFalse);
    });

    test(
      'empty 200 body (e.g. time-tracking/active when idle) returns null',
      () async {
        final h = Harness();
        await h.signIn();
        h.main.on('GET', 'time-tracking/active', (_) => Reply.empty());
        expect(await h.api.get('time-tracking/active'), isNull);
      },
    );
  });

  group('401 handling', () {
    test('refreshes once, retries the request with the new token', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('GET', 'tasks/my-queue', (o) {
        return o.headers['Authorization'] == 'Bearer new-access'
            ? Reply.json([1])
            : Reply.json({'message': 'Unauthorized'}, status: 401);
      });
      h.refresh.on(
        'POST',
        'auth/refresh',
        (_) => _tokens('new-access', 'new-refresh'),
      );

      final data = await h.api.get('tasks/my-queue');

      expect(data, [1]);
      expect(h.refresh.count('POST', 'auth/refresh'), 1);
      expect(await h.store.readRefreshToken(), 'new-refresh');
      expect(h.expired, 0);
    });

    test('concurrent 401s share ONE refresh (refresh tokens rotate)', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('GET', 'tasks/my-queue', (o) {
        return o.headers['Authorization'] == 'Bearer new-access'
            ? Reply.json([])
            : Reply.json({}, status: 401);
      });
      h.main.on('GET', 'time-tracking/active', (o) {
        return o.headers['Authorization'] == 'Bearer new-access'
            ? Reply.empty()
            : Reply.json({}, status: 401);
      });
      h.main.on('GET', 'materials', (o) {
        return o.headers['Authorization'] == 'Bearer new-access'
            ? Reply.json({'items': []})
            : Reply.json({}, status: 401);
      });
      h.refresh.on(
        'POST',
        'auth/refresh',
        (_) => _tokens('new-access', 'new-refresh'),
      );

      await Future.wait([
        h.api.get('tasks/my-queue'),
        h.api.get('time-tracking/active'),
        h.api.get('materials'),
      ]);

      expect(h.refresh.count('POST', 'auth/refresh'), 1);
    });

    test('rejected refresh token ends the session', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('GET', 'tasks/my-queue', (_) => Reply.json({}, status: 401));
      h.refresh.on(
        'POST',
        'auth/refresh',
        (_) => Reply.json({'message': 'Invalid refresh token'}, status: 401),
      );

      await expectLater(
        h.api.get('tasks/my-queue'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.unauthorized,
          ),
        ),
      );
      expect(h.expired, 1);
    });

    test(
      'network failure while refreshing does NOT log the user out',
      () async {
        final h = Harness();
        await h.signIn();
        h.main.on('GET', 'tasks/my-queue', (_) => Reply.json({}, status: 401));
        h.refresh.on(
          'POST',
          'auth/refresh',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );

        await expectLater(
          h.api.get('tasks/my-queue'),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.offline,
            ),
          ),
        );
        expect(h.expired, 0);
        expect(await h.store.readRefreshToken(), 'old-refresh');
      },
    );

    test('a 5xx during refresh also keeps the session', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('GET', 'tasks/my-queue', (_) => Reply.json({}, status: 401));
      h.refresh.on('POST', 'auth/refresh', (_) => Reply.json({}, status: 503));

      await expectLater(
        h.api.get('tasks/my-queue'),
        throwsA(isA<AppException>()),
      );
      expect(h.expired, 0);
    });

    test('does not loop when the retried request is still 401', () async {
      final h = Harness();
      await h.signIn();
      h.main.on(
        'GET',
        'auth/me',
        (_) => Reply.json({'message': 'Account not active'}, status: 401),
      );
      h.refresh.on(
        'POST',
        'auth/refresh',
        (_) => _tokens('new-access', 'new-refresh'),
      );

      await expectLater(
        h.api.get('auth/me'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.unauthorized,
          ),
        ),
      );
      expect(h.main.count('GET', 'auth/me'), 2);
      expect(h.refresh.count('POST', 'auth/refresh'), 1);
    });

    test(
      'a wrong password on login is a plain 401, no refresh attempted',
      () async {
        final h = Harness();
        h.main.on(
          'POST',
          'auth/login',
          (_) => Reply.json({'message': 'Invalid credentials'}, status: 401),
        );
        await expectLater(
          h.api.post(
            'auth/login',
            auth: false,
            body: {'email': 'a@b.c', 'password': 'wrongwrong'},
          ),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              'Invalid credentials',
            ),
          ),
        );
        expect(h.refresh.requests, isEmpty);
      },
    );
  });

  group('other errors', () {
    test('402 raises the subscription event with its code', () async {
      final h = Harness();
      await h.signIn();
      h.main.on(
        'GET',
        'auth/me',
        (_) => Reply.json({
          'statusCode': 402,
          'message': 'expired',
          'code': 'TRIAL_EXPIRED',
        }, status: 402),
      );

      await expectLater(
        h.api.get('auth/me'),
        throwsA(
          isA<AppException>().having((e) => e.code, 'code', 'TRIAL_EXPIRED'),
        ),
      );
      expect(h.blockedCodes, ['TRIAL_EXPIRED']);
    });

    test('403 and 500 are mapped, not swallowed', () async {
      final h = Harness();
      await h.signIn();
      h.main.on(
        'GET',
        'a',
        (_) => Reply.json({'message': 'Insufficient permissions'}, status: 403),
      );
      h.main.on('GET', 'b', (_) => Reply.json({}, status: 500));
      await expectLater(
        h.api.get('a'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      await expectLater(
        h.api.get('b'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.server,
          ),
        ),
      );
    });

    test('receive timeout on a write is reported as unknown outcome', () async {
      final h = Harness();
      await h.signIn();
      h.main.on(
        'POST',
        'time-tracking/clock-in',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      );
      await expectLater(
        h.api.post('time-tracking/clock-in', body: {'projectId': 'p'}),
        throwsA(
          isA<AppException>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            isTrue,
          ),
        ),
      );
    });

    test('blank query values are not sent', () async {
      final h = Harness();
      await h.signIn();
      h.main.on('GET', 'materials', (_) => Reply.json({'items': []}));
      await h.api.get(
        'materials',
        query: {'page': 1, 'limit': 20, 'search': '', 'x': null},
      );
      final q = h.main.last('GET', 'materials').query;
      expect(q.keys, unorderedEquals(['page', 'limit']));
    });
  });
}
