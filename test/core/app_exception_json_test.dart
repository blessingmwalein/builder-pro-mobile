import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/core/utils/json.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppException.fromResponse', () {
    test('400 with a validation array exposes every message', () {
      final e = AppException.fromResponse(400, {
        'message': ['email must be an email', 'password is too short'],
        'error': 'Bad Request',
        'statusCode': 400,
      });
      expect(e.kind, AppErrorKind.validation);
      expect(e.details, hasLength(2));
      expect(e.fullMessage, contains('password is too short'));
    });

    test('402 keeps the subscription code', () {
      final e = AppException.fromResponse(402, {
        'statusCode': 402,
        'message':
            'Your free trial has expired. Activate a subscription to continue.',
        'error': 'Payment Required',
        'code': 'TRIAL_EXPIRED',
      });
      expect(e.kind, AppErrorKind.subscription);
      expect(e.code, 'TRIAL_EXPIRED');
    });

    test('403 uses a safe generic message, not server text', () {
      final e = AppException.fromResponse(403, {
        'message': 'Insufficient permissions',
      });
      expect(e.kind, AppErrorKind.forbidden);
      expect(e.message, isNot(contains('Insufficient')));
    });

    test('5xx and 429 are retryable, 400 is not', () {
      expect(AppException.fromResponse(500, null).isRetryable, isTrue);
      expect(
        AppException.fromResponse(429, null).kind,
        AppErrorKind.rateLimited,
      );
      expect(AppException.fromResponse(400, null).isRetryable, isFalse);
    });

    test('tolerates non-JSON bodies', () {
      expect(
        AppException.fromResponse(404, '<html>').kind,
        AppErrorKind.notFound,
      );
      expect(AppException.fromResponse(null, null).kind, AppErrorKind.unknown);
    });
  });

  group('AppException.fromDio', () {
    DioException dio(DioExceptionType t) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: t,
    );

    test('connection errors mean not delivered; receive timeouts mean unknown outcome', () {
      expect(
        AppException.fromDio(dio(DioExceptionType.connectionError)).kind,
        AppErrorKind.offline,
      );
      expect(
        AppException.fromDio(dio(DioExceptionType.connectionTimeout)).kind,
        AppErrorKind.timeout,
      );
      final unknown = AppException.fromDio(
        dio(DioExceptionType.receiveTimeout),
      );
      expect(unknown.kind, AppErrorKind.uncertain);
      expect(unknown.outcomeUnknown, isTrue);
      expect(
        AppException.fromDio(dio(DioExceptionType.connectionError))
            .outcomeUnknown,
        isFalse,
      );
    });
  });

  group('J (tolerant JSON)', () {
    test('parses decimals sent as strings', () {
      expect(J.number('16.5'), 16.5);
      expect(J.number(12), 12.0);
      expect(J.number('abc'), isNull);
      expect(J.integer('42'), 42);
    });

    test('empty and wrong-typed values do not throw', () {
      expect(J.map(null), isEmpty);
      expect(J.list('x'), isEmpty);
      expect(J.str(''), isNull);
      expect(J.date('not a date'), isNull);
      expect(J.boolean('true'), isTrue);
    });

    test('paged envelope with string meta numbers', () {
      final p = J.paged({
        'items': [
          {'id': 'a'},
          {'id': 'b'},
        ],
        'meta': {'page': '1', 'limit': '2', 'total': '5'},
      });
      expect(p.items, hasLength(2));
      expect(p.total, 5);
      expect(p.hasMore, isTrue);
    });

    test('bare array is treated as a single page', () {
      final p = J.paged([
        {'id': 'a'},
      ]);
      expect(p.items, hasLength(1));
      expect(p.hasMore, isFalse);
    });
  });
}
