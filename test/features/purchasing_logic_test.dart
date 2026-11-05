import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/purchasing/application/purchasing_providers.dart';
import 'package:builder_pro_mobile/features/purchasing/data/purchasing_models.dart';
import 'package:builder_pro_mobile/features/purchasing/presentation/new_purchase_request_screen.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

const _items = [
  NewPrItem(
    description: 'Cement',
    quantity: 10,
    unit: 'bag',
    estimatedUnitCost: 12.5,
  ),
];

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('models', () {
    test('a request reads status, people, project and item counts', () {
      final r = PurchaseRequestSummary.tryParse(prJson())!;
      expect(r.number, 'PR-2026-0001');
      expect(r.status, 'SUBMITTED');
      expect(r.isSubmitted, isTrue);
      expect(r.requestedBy, 'Farai Ncube');
      expect(r.projectName, 'Harare Tower');
      expect(r.itemCount, 2);
    });

    test(
      'estimated total sums quantity x cost and says when it is incomplete',
      () {
        final d = PurchaseRequestDetail.tryParse(prJson(detail: true))!;
        expect(d.items.first.estimatedTotal, 500);
        expect(d.estimatedTotal, 650);
        expect(d.estimateComplete, isTrue);

        final partial = PurchaseRequestDetail.tryParse(
          prJson(detail: true, withCosts: false),
        )!;
        expect(partial.estimatedTotal, 0);
        expect(partial.estimateComplete, isFalse);
      },
    );

    test('a request with only some costs is a minimum, not a total', () {
      final json = prJson(detail: true);
      (json['items'] as List)[1]['estimatedUnitCost'] = null;
      final d = PurchaseRequestDetail.tryParse(json)!;
      expect(d.estimatedTotal, 500);
      expect(d.estimateComplete, isFalse);
    });

    test(
      'an order reads supplier, total, expected delivery and its request',
      () {
        final o = PurchaseOrderDetail.tryParse(poJson(detail: true))!;
        expect(o.summary.supplierName, 'Zim Cement');
        expect(o.summary.total, 650);
        expect(o.items.map((i) => i.totalCost), [500, 150]);
        expect(o.requestNumber, 'PR-2026-0001');
        expect(o.deliveryCount, 1);
      },
    );

    test('rows without an id are skipped', () {
      expect(PurchaseRequestSummary.tryParse({'prNumber': 'x'}), isNull);
      expect(PurchaseOrderSummary.tryParse(null), isNull);
    });
  });

  group('form validation', () {
    test('description, unit and cost rules', () {
      expect(validateDescription(''), isNotNull);
      expect(validateDescription('Cement'), isNull);
      expect(validateDescription('x' * 201), isNotNull);
      expect(validateUnit(''), isNotNull);
      expect(validateUnit('bags'), isNull);
      expect(validateUnit('x' * 21), isNotNull);
      expect(validateUnitCost(''), isNull);
      expect(validateUnitCost('12,5'), isNull);
      expect(validateUnitCost('-1'), isNotNull);
      expect(validateUnitCost('abc'), isNotNull);
      expect(validateUnitCost('1.234'), isNotNull);
    });
  });

  group('lists', () {
    test(
      'requests are asked for with page, limit and the status filter',
      () async {
        env.adapter.on(
          'GET',
          'procurement/purchase-requests',
          (_) => Reply.json(paged([prJson()], limit: 20)),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(purchaseRequestsProvider, (_, _) {});
        await pumpEventQueue(times: 20);

        var q = env.adapter.last('GET', 'procurement/purchase-requests').query;
        expect(q['page'], 1);
        expect(q['limit'], 20);
        expect(q.containsKey('status'), isFalse);

        await c.read(purchaseRequestsProvider.notifier).setFilter('SUBMITTED');
        q = env.adapter.last('GET', 'procurement/purchase-requests').query;
        expect(q['status'], 'SUBMITTED');
        expect(
          c.read(purchaseRequestsProvider).items.single.number,
          'PR-2026-0001',
        );
      },
    );

    test('orders are asked for with page, limit and status', () async {
      env.adapter.on(
        'GET',
        'procurement/purchase-orders',
        (_) => Reply.json(paged([poJson()], limit: 20)),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(purchaseOrdersProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      await c.read(purchaseOrdersProvider.notifier).setFilter('RECEIVED');
      final q = env.adapter.last('GET', 'procurement/purchase-orders').query;
      expect(q['limit'], 20);
      expect(q['status'], 'RECEIVED');
    });

    test(
      'a 403 (no materials.view) is an error state, not an empty list',
      () async {
        env.adapter.on(
          'GET',
          'procurement/purchase-requests',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(purchaseRequestsProvider, (_, _) {});
        await pumpEventQueue(times: 20);
        expect(
          c.read(purchaseRequestsProvider).error?.kind,
          AppErrorKind.forbidden,
        );
      },
    );

    test('details load, and a malformed reply is an error', () async {
      env.adapter
        ..on(
          'GET',
          'procurement/purchase-requests/pr1',
          (_) => Reply.json(prJson(detail: true)),
        )
        ..on(
          'GET',
          'procurement/purchase-orders/bad',
          (_) => Reply.json({'unexpected': true}),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(purchaseRequestDetailProvider('pr1'), (_, _) {});
      c.listen(purchaseOrderDetailProvider('bad'), (_, _) {});
      expect(
        (await c.read(purchaseRequestDetailProvider('pr1').future)).items,
        hasLength(2),
      );
      await expectLater(
        c.read(purchaseOrderDetailProvider('bad').future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.malformed,
          ),
        ),
      );
    });
  });

  group('create', () {
    test(
      'sends items with numbers, an optional project and trimmed notes',
      () async {
        env.adapter.on(
          'POST',
          'procurement/purchase-requests',
          (_) => Reply.json(
            prJson(status: 'DRAFT', requestedById: 'u1', items: 1),
            status: 201,
          ),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);

        final r = await c
            .read(purchasingActionsProvider)
            .create(items: _items, projectId: 'p1', notes: '  slab pour  ');

        expect(env.adapter.last('POST', 'procurement/purchase-requests').data, {
          'projectId': 'p1',
          'notes': 'slab pour',
          'items': [
            {
              'description': 'Cement',
              'quantity': 10.0,
              'unit': 'bag',
              'estimatedUnitCost': 12.5,
            },
          ],
        });
        expect(r.submitted, isFalse);
        expect(r.request.status, 'DRAFT');
      },
    );

    test('blank notes, no project and no cost are left out', () async {
      env.adapter.on(
        'POST',
        'procurement/purchase-requests',
        (_) => Reply.json(
          prJson(status: 'DRAFT', requestedById: 'u1', items: 1),
          status: 201,
        ),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await c
          .read(purchasingActionsProvider)
          .create(
            items: const [
              NewPrItem(description: 'Sand', quantity: 2, unit: 'm3'),
            ],
            notes: '  ',
          );
      expect(env.adapter.last('POST', 'procurement/purchase-requests').data, {
        'items': [
          {'description': 'Sand', 'quantity': 2.0, 'unit': 'm3'},
        ],
      });
    });

    test('with submit: created, then submitted', () async {
      env.adapter
        ..on(
          'POST',
          'procurement/purchase-requests',
          (_) => Reply.json(
            prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 1),
            status: 201,
          ),
        )
        ..on(
          'POST',
          'procurement/purchase-requests/new/submit',
          (_) => Reply.json({}, status: 201),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      final r = await c
          .read(purchasingActionsProvider)
          .create(items: _items, submit: true);

      expect(r.submitted, isTrue);
      expect(r.submitError, isNull);
      expect(
        env.adapter.count('POST', 'procurement/purchase-requests/new/submit'),
        1,
      );
    });

    test(
      'if submitting fails the draft is NOT lost and the problem is reported',
      () async {
        env.adapter
          ..on(
            'POST',
            'procurement/purchase-requests',
            (_) => Reply.json(
              prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 1),
              status: 201,
            ),
          )
          ..on(
            'POST',
            'procurement/purchase-requests/new/submit',
            (_) => Reply.json({'statusCode': 403}, status: 403),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);

        final r = await c
            .read(purchasingActionsProvider)
            .create(items: _items, submit: true);

        expect(r.submitted, isFalse);
        expect(r.request.id, 'new');
        expect(r.submitError?.kind, AppErrorKind.forbidden);
      },
    );

    test('a refusal while creating is shown and not retried', () async {
      env.adapter.on(
        'POST',
        'procurement/purchase-requests',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        c.read(purchasingActionsProvider).create(items: _items),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(env.adapter.count('POST', 'procurement/purchase-requests'), 1);
      // A refusal is an answer: nothing is looked up to "recover" anything.
      expect(env.adapter.count('GET', 'procurement/purchase-requests'), 0);
    });

    group('after a timeout the newest drafts are checked first', () {
      test(
        'created: found by me + time + item count; exactly one POST',
        () async {
          env.adapter
            ..on(
              'POST',
              'procurement/purchase-requests',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              'procurement/purchase-requests',
              (_) => Reply.json(
                paged([
                  prJson(
                    id: 'found',
                    status: 'DRAFT',
                    requestedById: 'u1',
                    items: 1,
                    createdAt: DateTime.now(), // created just now
                  ),
                ], limit: 20),
              ),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);

          final r = await c
              .read(purchasingActionsProvider)
              .create(items: _items, projectId: 'p1');

          expect(r.request.id, 'found');
          expect(r.note, contains('saved'));
          expect(env.adapter.count('POST', 'procurement/purchase-requests'), 1);
          final q = env.adapter
              .last('GET', 'procurement/purchase-requests')
              .query;
          expect(q['status'], 'DRAFT');
          expect(q['projectId'], 'p1');
        },
      );

      // One disqualifier at a time: each of these would be accepted if its own
      // check were dropped, so they must not share a fixture.
      final notMine = <String, Map<String, dynamic>>{
        "someone else's draft, created just now": prJson(
          id: 'theirs',
          status: 'DRAFT',
          requestedById: 'u9',
          items: 1,
          createdAt: DateTime.now(),
        ),
        'my own draft, but from two days ago': prJson(
          id: 'old',
          status: 'DRAFT',
          requestedById: 'u1',
          items: 1,
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        'my own recent draft, but with a different number of items': prJson(
          id: 'other-size',
          status: 'DRAFT',
          requestedById: 'u1',
          items: 3,
          createdAt: DateTime.now(),
        ),
      };
      for (final entry in notMine.entries) {
        test('is not mistaken for the new request: ${entry.key}', () async {
          env.adapter
            ..on(
              'POST',
              'procurement/purchase-requests',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              'procurement/purchase-requests',
              (_) => Reply.json(paged([entry.value], limit: 20)),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);

          await expectLater(
            c.read(purchasingActionsProvider).create(items: _items),
            throwsA(
              isA<AppException>().having(
                (e) => e.message,
                'message',
                contains('no request was created'),
              ),
            ),
          );
          expect(env.adapter.count('POST', 'procurement/purchase-requests'), 1);
        });
      }

      test('the check also fails: the outcome stays unknown', () async {
        env.adapter
          ..on(
            'POST',
            'procurement/purchase-requests',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            'procurement/purchase-requests',
            (_) => Reply.fail(DioExceptionType.connectionError),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(purchasingActionsProvider).create(items: _items),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
      });
    });
  });

  group('submit / approve / reject', () {
    const base = 'procurement/purchase-requests/pr1';

    test(
      'approve posts to the approve route and refreshes the lists',
      () async {
        env.adapter.on(
          'POST',
          '$base/approve',
          (_) => Reply.json({}, status: 201),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        expect(await c.read(purchasingActionsProvider).approve('pr1'), isNull);
        expect(env.adapter.count('POST', '$base/approve'), 1);
      },
    );

    test('reject sends the trimmed reason; none is sent when blank', () async {
      env.adapter
        ..on('POST', '$base/reject', (_) => Reply.json({}, status: 201))
        ..on(
          'POST',
          'procurement/purchase-requests/pr2/reject',
          (_) => Reply.json({}, status: 201),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      final a = c.read(purchasingActionsProvider);
      await a.reject('pr1', notes: '  Too much  ');
      expect(env.adapter.last('POST', '$base/reject').data, {
        'notes': 'Too much',
      });
      await a.reject('pr2', notes: '   ');
      expect(
        env.adapter
            .last('POST', 'procurement/purchase-requests/pr2/reject')
            .data,
        {},
      );
    });

    test('a refusal (403) is shown, never retried', () async {
      env.adapter.on(
        'POST',
        '$base/approve',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        c.read(purchasingActionsProvider).approve('pr1'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(env.adapter.count('POST', '$base/approve'), 1);
    });

    test('no connection: plain offline error and nothing queued', () async {
      env.adapter.on(
        'POST',
        '$base/submit',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        c.read(purchasingActionsProvider).submit('pr1'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.offline,
          ),
        ),
      );
      expect(await env.db.outboxFor('u1'), isEmpty);
    });

    test('the server refusing a change from the wrong status becomes a plain "it moved on"', () async {
      env.adapter.on(
        'POST',
        '$base/approve',
        (_) => Reply.json({
          'statusCode': 400,
          'message': 'Only SUBMITTED requests can be approved',
        }, status: 400),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        c.read(purchasingActionsProvider).approve('pr1'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('changed since you opened it'),
          ),
        ),
      );
    });

    group('after a timeout the request is read back, never resent', () {
      test('approve recorded: reported as done', () async {
        env.adapter
          ..on(
            'POST',
            '$base/approve',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            base,
            (_) => Reply.json(prJson(detail: true, status: 'APPROVED')),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        final note = await c.read(purchasingActionsProvider).approve('pr1');
        expect(note, contains('Done'));
        expect(env.adapter.count('POST', '$base/approve'), 1);
      });

      test('approve not recorded: a clear message and a safe retry', () async {
        env.adapter
          ..on(
            'POST',
            '$base/approve',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            base,
            (_) => Reply.json(prJson(detail: true, status: 'SUBMITTED')),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(purchasingActionsProvider).approve('pr1'),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              contains('nothing was recorded'),
            ),
          ),
        );
        expect(env.adapter.count('POST', '$base/approve'), 1);
      });

      test(
        'someone rejected it meanwhile: reported, not overwritten',
        () async {
          env.adapter
            ..on(
              'POST',
              '$base/approve',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              base,
              (_) => Reply.json(prJson(detail: true, status: 'REJECTED')),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          expect(
            await c.read(purchasingActionsProvider).approve('pr1'),
            contains('already moved on'),
          );
        },
      );

      test(
        'reject recorded: done; submit recorded (now approved or later): done',
        () async {
          env.adapter
            ..on(
              'POST',
              '$base/reject',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              base,
              (_) => Reply.json(prJson(detail: true, status: 'REJECTED')),
            )
            ..on(
              'POST',
              'procurement/purchase-requests/pr2/submit',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              'procurement/purchase-requests/pr2',
              (_) => Reply.json(
                prJson(id: 'pr2', detail: true, status: 'SUBMITTED'),
              ),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          final a = c.read(purchasingActionsProvider);
          expect(await a.reject('pr1', notes: 'no'), contains('Done'));
          expect(await a.submit('pr2'), contains('Done'));
        },
      );

      test('the check also fails: the outcome stays unknown', () async {
        env.adapter
          ..on(
            'POST',
            '$base/approve',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            base,
            (_) => Reply.fail(DioExceptionType.connectionError),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(purchasingActionsProvider).approve('pr1'),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
      });
    });
  });
}
