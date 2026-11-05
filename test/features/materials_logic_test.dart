import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/materials/application/materials_providers.dart';
import 'package:builder_pro_mobile/features/materials/data/material_models.dart';
import 'package:builder_pro_mobile/features/materials/presentation/log_usage_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';

final _cement = MaterialItem.tryParse(materialJson())!;

Map<String, dynamic> _log({
  String id = 'log1',
  double quantity = 12,
  DateTime? at,
}) => {
  'id': id,
  'projectId': 'p1',
  'materialId': 'm1',
  'quantity': quantity.toString(),
  'unitCost': '12.50',
  'totalCost': (quantity * 12.5).toString(),
  'usedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'notes': null,
};

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('quantity input', () {
    test('accepts plain numbers and a comma decimal mark', () {
      expect(parseQuantity('12'), 12);
      expect(parseQuantity(' 2,5 '), 2.5);
      expect(parseQuantity('0.125'), 0.125);
    });

    test('rejects empty, non-numeric, zero, negative and absurd values', () {
      expect(validateQuantity(''), isNotNull);
      expect(validateQuantity('abc'), isNotNull);
      expect(validateQuantity('0'), isNotNull);
      expect(validateQuantity('-3'), isNotNull);
      expect(validateQuantity('1000001'), isNotNull);
      expect(validateQuantity('1.2.3'), isNotNull);
    });

    test('allows at most 3 decimals, as the API stores', () {
      expect(validateQuantity('1.234'), isNull);
      expect(validateQuantity('1.2345'), isNotNull);
      expect(validateQuantity('12'), isNull);
    });
  });

  group('catalog', () {
    test('sends page and limit every time, parses string decimals', () async {
      env.adapter.on(
        'GET',
        'materials',
        (_) => Reply.json(paged([materialJson()], limit: 20, total: 1)),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      c.listen(materialCatalogProvider, (_, _) {});

      await pumpEventQueue(times: 20);

      final q = env.adapter.last('GET', 'materials').query;
      expect(q['page'], 1);
      expect(q['limit'], 20);
      final item = c.read(materialCatalogProvider).items.single;
      expect(item.unitCost, 12.5);
      expect(item.stockOnHand, 40);
      expect(item.category, 'Cement');
    });

    test('a newer search wins over a slow older one', () async {
      env.adapter
        ..on('GET', 'materials', (_) => Reply.json(paged([]))) // initial
        // The first search answers LATE, after the second one has finished.
        ..on(
          'GET',
          'materials',
          (_) => Reply.json(
            paged([materialJson(id: 'old', name: 'Old')]),
            delay: const Duration(milliseconds: 300),
          ),
        )
        ..on(
          'GET',
          'materials',
          (_) => Reply.json(paged([materialJson(id: 'new', name: 'New')])),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      c.listen(materialCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);

      final notifier = c.read(materialCatalogProvider.notifier);
      final first = notifier.search('ce');
      final second = notifier.search('cem');
      await Future.wait([first, second]);

      expect(c.read(materialCatalogProvider).items.map((i) => i.id), ['new']);
      expect(c.read(materialCatalogProvider).query, 'cem');
    });

    test('load more appends the next page without duplicates', () async {
      env.adapter
        ..on(
          'GET',
          'materials',
          (_) => Reply.json(paged([materialJson(id: 'a')], limit: 1, total: 2)),
        )
        ..on(
          'GET',
          'materials',
          (_) => Reply.json(
            paged(
              [materialJson(id: 'a'), materialJson(id: 'b')],
              page: 2,
              limit: 1,
              total: 2,
            ),
          ),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      c.listen(materialCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      expect(c.read(materialCatalogProvider).hasMore, isTrue);

      await c.read(materialCatalogProvider.notifier).loadMore();

      expect(c.read(materialCatalogProvider).items.map((i) => i.id), [
        'a',
        'b',
      ]);
      expect(c.read(materialCatalogProvider).hasMore, isFalse);
      expect(env.adapter.last('GET', 'materials').query['page'], 2);
    });

    test(
      'a failed first page is an error state, not an empty catalog',
      () async {
        env.adapter.on(
          'GET',
          'materials',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env);
        addTearDown(c.dispose);
        c.listen(materialCatalogProvider, (_, _) {});
        await pumpEventQueue(times: 20);

        final s = c.read(materialCatalogProvider);
        expect(s.error?.kind, AppErrorKind.offline);
        expect(s.loading, isFalse);
        expect(s.items, isEmpty);
      },
    );
  });

  group('logging usage', () {
    test(
      'posts the catalog unit cost (not typed by the worker) and trims notes',
      () async {
        env.adapter.on(
          'POST',
          'materials/usage',
          (_) => Reply.json(_log(), status: 201),
        );
        final c = makeContainer(env);
        addTearDown(c.dispose);

        final r = await c
            .read(materialUsageActionsProvider)
            .logUsage(
              material: _cement,
              projectId: 'p1',
              projectName: 'Harare Tower',
              quantity: 12,
              notes: '  slab A  ',
            );

        expect(env.adapter.last('POST', 'materials/usage').data, {
          'projectId': 'p1',
          'materialId': 'm1',
          'quantity': 12.0,
          'unitCost': 12.5,
          'notes': 'slab A',
        });
        expect(r.note, isNull);
        expect(r.log!.materialName, 'Cement 50kg');
        expect(c.read(loggedThisSessionProvider).single.id, 'log1');
      },
    );

    test('empty notes are not sent', () async {
      env.adapter.on(
        'POST',
        'materials/usage',
        (_) => Reply.json(_log(), status: 201),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c
          .read(materialUsageActionsProvider)
          .logUsage(
            material: _cement,
            projectId: 'p1',
            projectName: 'P',
            quantity: 1,
            notes: '   ',
          );
      expect(
        (env.adapter.last('POST', 'materials/usage').data as Map).containsKey(
          'notes',
        ),
        isFalse,
      );
    });

    test('a validation error from the server is shown and nothing is recorded locally', () async {
      env.adapter.on(
        'POST',
        'materials/usage',
        (_) => Reply.json({
          'statusCode': 400,
          'message': [
            'quantity must be a number conforming to the specified constraints',
          ],
        }, status: 400),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);

      await expectLater(
        c
            .read(materialUsageActionsProvider)
            .logUsage(
              material: _cement,
              projectId: 'p1',
              projectName: 'P',
              quantity: 1,
            ),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.validation,
          ),
        ),
      );
      expect(c.read(loggedThisSessionProvider), isEmpty);
    });

    test(
      'timed out but saved: found in the latest logs, not posted again',
      () async {
        env.adapter
          ..on(
            'POST',
            'materials/usage',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            'materials/logs',
            (_) => Reply.json(paged([_log(id: 'saved', quantity: 12)])),
          );
        final c = makeContainer(env);
        addTearDown(c.dispose);

        final r = await c
            .read(materialUsageActionsProvider)
            .logUsage(
              material: _cement,
              projectId: 'p1',
              projectName: 'P',
              quantity: 12,
            );

        expect(r.log!.id, 'saved');
        expect(r.note, contains('recorded'));
        expect(env.adapter.count('POST', 'materials/usage'), 1);
        final q = env.adapter.last('GET', 'materials/logs').query;
        expect(q['projectId'], 'p1');
        expect(q['materialId'], 'm1');
      },
    );

    test('timed out and not saved: a clear "nothing was recorded"', () async {
      env.adapter
        ..on(
          'POST',
          'materials/usage',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        // An older log with the same quantity must not be mistaken for ours.
        ..on(
          'GET',
          'materials/logs',
          (_) => Reply.json(
            paged([
              _log(
                id: 'old',
                quantity: 12,
                at: DateTime.now().subtract(const Duration(hours: 3)),
              ),
            ]),
          ),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);

      await expectLater(
        c
            .read(materialUsageActionsProvider)
            .logUsage(
              material: _cement,
              projectId: 'p1',
              projectName: 'P',
              quantity: 12,
            ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('nothing was recorded'),
          ),
        ),
      );
      expect(c.read(loggedThisSessionProvider), isEmpty);
    });

    test('timed out and the check also fails: outcome stays unknown', () async {
      env.adapter
        ..on(
          'POST',
          'materials/usage',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on(
          'GET',
          'materials/logs',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);

      await expectLater(
        c
            .read(materialUsageActionsProvider)
            .logUsage(
              material: _cement,
              projectId: 'p1',
              projectName: 'P',
              quantity: 12,
            ),
        throwsA(
          isA<AppException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            isTrue,
          ),
        ),
      );
    });

    test(
      'no connection at all is a plain offline error and no log appears',
      () async {
        env.adapter.on(
          'POST',
          'materials/usage',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env);
        addTearDown(c.dispose);
        await expectLater(
          c
              .read(materialUsageActionsProvider)
              .logUsage(
                material: _cement,
                projectId: 'p1',
                projectName: 'P',
                quantity: 1,
              ),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.offline,
            ),
          ),
        );
        expect(env.adapter.count('GET', 'materials/logs'), 0);
      },
    );
  });
}
