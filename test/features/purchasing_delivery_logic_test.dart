import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/materials/application/materials_providers.dart';
import 'package:builder_pro_mobile/features/purchasing/application/purchasing_providers.dart';
import 'package:builder_pro_mobile/features/purchasing/data/purchasing_models.dart';
import 'package:builder_pro_mobile/features/purchasing/presentation/receive_delivery_screen.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

const _cement = 'm:m1';
const _sand = 'm:m2';

/// An order for 40 bags of cement (material m1) and 5 m3 of sand (m2).
Map<String, dynamic> _order({
  String status = 'SENT',
  List<Map<String, dynamic>> notes = const [],
}) => poJson(detail: true, status: status, deliveryNotes: notes);

PurchaseOrderDetail _parse(Map<String, dynamic> json) =>
    PurchaseOrderDetail.tryParse(json)!;

Matcher _fails(AppErrorKind kind, {String? containing}) => isA<AppException>()
    .having((e) => e.kind, 'kind', kind)
    .having((e) => e.message, 'message', contains(containing ?? ''));

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('what is still outstanding', () {
    test('with no deliveries, everything ordered is outstanding', () {
      final o = _parse(_order()).outstanding;
      expect(o.map((l) => l.key), [_cement, _sand]);
      expect(o.map((l) => l.outstanding), [40, 5]);
      expect(o.map((l) => l.unit), ['bag', 'm3']);
      expect(_parse(_order()).hasOutstanding, isTrue);
    });

    test('earlier deliveries are taken off, and add up', () {
      final o = _parse(
        _order(
          status: 'PARTIAL',
          notes: [
            dnJson(lines: [dnLine(received: 10)]),
            dnJson(id: 'dn2', lines: [dnLine(received: 15)]),
          ],
        ),
      ).outstanding;
      expect(o[0].received, 25);
      expect(o[0].outstanding, 15);
      expect(o[1].outstanding, 5);
    });

    test(
      'a line received in full is complete; all complete means nothing left',
      () {
        final d = _parse(
          _order(
            status: 'PARTIAL',
            notes: [
              dnJson(
                lines: [
                  dnLine(received: 40),
                  dnLine(
                    description: 'River sand',
                    materialId: 'm2',
                    ordered: 5,
                    received: 5,
                  ),
                ],
              ),
            ],
          ),
        );
        expect(d.outstanding.every((l) => l.isComplete), isTrue);
        expect(d.hasOutstanding, isFalse);
      },
    );

    test(
      'more received than ordered (recorded on the web) is not negative',
      () {
        final o = _parse(
          _order(
            notes: [
              dnJson(lines: [dnLine(received: 45)]),
            ],
          ),
        ).outstanding;
        expect(o[0].outstanding, 0);
        expect(o[0].isComplete, isTrue);
      },
    );

    test('three-decimal quantities do not leave float noise', () {
      final json = _order(
        notes: [
          dnJson(lines: [dnLine(received: 0.1)]),
          dnJson(id: 'dn2', lines: [dnLine(received: 0.2)]),
        ],
      );
      (json['items'] as List)[0]['quantity'] = '0.300';
      final line = _parse(json).outstanding.first;
      expect(line.outstanding, 0);
      expect(line.received, 0.3);
    });

    test('lines with no material are matched to deliveries by wording', () {
      final json = _order(
        notes: [
          dnJson(
            lines: [
              dnLine(
                description: '  SITE hire ',
                materialId: null,
                received: 2,
              ),
            ],
          ),
        ],
      );
      json['items'] = [
        {
          'id': 'x',
          'description': 'Site hire',
          'quantity': '5.000',
          'unitCost': '10.00',
          'totalCost': '50.00',
        },
      ];
      final line = _parse(json).outstanding.single;
      expect(line.key, 't:site hire');
      expect(line.materialId, isNull);
      expect(line.outstanding, 3);
    });

    test('two lines for the same material are one item', () {
      final json = _order();
      (json['items'] as List).add({
        'id': 'pi9',
        'materialId': 'm1',
        'description': 'Portland cement 50kg',
        'quantity': '20.000',
        'unitCost': '12.50',
        'totalCost': '250.00',
        'material': {'id': 'm1', 'name': 'Cement 50kg', 'unit': 'bag'},
      });
      final o = _parse(json).outstanding;
      expect(o, hasLength(2));
      expect(o.first.ordered, 60);
    });

    test('only a sent or part-received order can take a delivery', () {
      for (final entry in {
        'SENT': true,
        'PARTIAL': true,
        'DRAFT': false,
        'RECEIVED': false,
        'CANCELLED': false,
      }.entries) {
        expect(
          _parse(_order(status: entry.key)).isReceivable,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('a delivery note keeps its calendar day, receiver and lines', () {
      final n = _parse(
        _order(
          notes: [
            dnJson(
              date: DateTime.utc(2026, 10, 20),
              by: 'u9',
              notes: 'Two bags torn',
            ),
          ],
        ),
      ).deliveries.single;
      expect(n.deliveryDate, DateTime.utc(2026, 10, 20));
      expect(n.receivedById, 'u9');
      expect(n.notes, 'Two bags torn');
      expect(n.lines.single.received, 10);
      expect(n.lines.single.materialId, 'm1');
    });
  });

  group('form validation', () {
    test('blank means nothing arrived; over the outstanding is refused', () {
      expect(validateReceived('', 30), isNull);
      expect(validateReceived('  ', 30), isNull);
      expect(validateReceived('0', 30), isNull);
      expect(validateReceived('30', 30), isNull);
      expect(validateReceived('12,5', 30), isNull);
      expect(
        validateReceived('30.5', 30, unit: 'bag'),
        contains('Only 30 bag'),
      );
      expect(validateReceived('abc', 30), 'Enter a number');
      expect(validateReceived('-1', 30), 'Cannot be negative');
      expect(validateReceived('1.2345', 30), 'Use at most 3 decimals');
    });

    test('the note is capped', () {
      expect(validateDeliveryNotes(null), isNull);
      expect(validateDeliveryNotes('x' * 501), isNotNull);
    });
  });

  group('recording a delivery', () {
    final day = DateTime(2026, 10, 27);

    Future<String?> receive(
      dynamic c,
      Map<String, double> received, {
      String? notes,
    }) => c
        .read(purchasingActionsProvider)
        .receiveDelivery('po1', date: day, received: received, notes: notes);

    void order(Map<String, dynamic> json) => env.adapter.on(
      'GET',
      'procurement/purchase-orders/po1',
      (_) => Reply.json(json),
    );

    void deliverOk() => env.adapter.on(
      'POST',
      'procurement/purchase-orders/po1/deliver',
      (_) => Reply.json(dnJson(), status: 201),
    );

    List<Recorded> posts() =>
        env.adapter.requests.where((r) => r.method == 'POST').toList();

    test(
      'sends EVERY outstanding line: received now, or 0, against what is left',
      () async {
        order(_order());
        deliverOk();
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);

        final note = await receive(c, {_cement: 30}, notes: '  2 bags torn  ');

        expect(note, isNull);
        expect(
          env.adapter
              .last('POST', 'procurement/purchase-orders/po1/deliver')
              .data,
          {
            'deliveryDate': '2026-10-27',
            'notes': '2 bags torn',
            'items': [
              {
                'description': 'Portland cement 50kg',
                'materialId': 'm1',
                'quantityOrdered': 40.0,
                'quantityReceived': 30.0,
              },
              // not received yet, but still in the request: the server decides
              // "received in full" from the totals it is sent
              {
                'description': 'River sand',
                'materialId': 'm2',
                'quantityOrdered': 5.0,
                'quantityReceived': 0.0,
              },
            ],
          },
        );
      },
    );

    test(
      'after an earlier delivery the ordered quantity is what is left',
      () async {
        order(
          _order(
            status: 'PARTIAL',
            notes: [
              dnJson(lines: [dnLine(received: 10)]),
            ],
          ),
        );
        deliverOk();
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);

        await receive(c, {_cement: 30, _sand: 5});

        final items =
            (env.adapter
                        .last('POST', 'procurement/purchase-orders/po1/deliver')
                        .data
                    as Map)['items']
                as List;
        expect(items[0]['quantityOrdered'], 30.0);
        expect(items[0]['quantityReceived'], 30.0);
        expect(items[1]['quantityOrdered'], 5.0);
      },
    );

    test('an item already received in full is left out', () async {
      order(
        _order(
          status: 'PARTIAL',
          notes: [
            dnJson(
              lines: [
                dnLine(
                  description: 'River sand',
                  materialId: 'm2',
                  ordered: 5,
                  received: 5,
                ),
              ],
            ),
          ],
        ),
      );
      deliverOk();
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      await receive(c, {_cement: 40});

      final items =
          (env.adapter
                      .last('POST', 'procurement/purchase-orders/po1/deliver')
                      .data
                  as Map)['items']
              as List;
      expect(items, hasLength(1));
      expect(items.single['materialId'], 'm1');
    });

    test('the order is re-read first, and a note is optional', () async {
      order(_order());
      deliverOk();
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await receive(c, {_sand: 5}, notes: '   ');
      expect(env.adapter.count('GET', 'procurement/purchase-orders/po1'), 1);
      expect(
        (env.adapter
                    .last('POST', 'procurement/purchase-orders/po1/deliver')
                    .data
                as Map)
            .containsKey('notes'),
        isFalse,
      );
    });

    test('an order that is not waiting for a delivery sends nothing', () async {
      for (final status in ['RECEIVED', 'DRAFT', 'CANCELLED']) {
        final e = TestEnv();
        addTearDown(e.dispose);
        e.adapter.on(
          'GET',
          'procurement/purchase-orders/po1',
          (_) => Reply.json(_order(status: status)),
        );
        final c = makeContainer(e, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c
              .read(purchasingActionsProvider)
              .receiveDelivery('po1', date: day, received: {_cement: 1}),
          throwsA(
            _fails(AppErrorKind.validation, containing: 'no longer waiting'),
          ),
          reason: status,
        );
        expect(
          e.adapter.requests.where((r) => r.method == 'POST'),
          isEmpty,
          reason: status,
        );
      }
    });

    test('more than is outstanding NOW (a delivery was recorded meanwhile) sends nothing', () async {
      // the form was opened when 40 were outstanding; now only 20 are
      order(
        _order(
          status: 'PARTIAL',
          notes: [
            dnJson(lines: [dnLine(received: 20)]),
          ],
        ),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        receive(c, {_cement: 40}),
        throwsA(
          _fails(AppErrorKind.validation, containing: 'More was entered'),
        ),
      );
      expect(posts(), isEmpty);
    });

    test(
      'quantities for an item that is no longer outstanding send nothing',
      () async {
        order(
          _order(
            status: 'PARTIAL',
            notes: [
              dnJson(
                lines: [
                  dnLine(
                    description: 'River sand',
                    materialId: 'm2',
                    ordered: 5,
                    received: 5,
                  ),
                ],
              ),
            ],
          ),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          receive(c, {_cement: 10, _sand: 1}),
          throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
        );
        expect(posts(), isEmpty);
      },
    );

    test('nothing entered sends nothing', () async {
      order(_order());
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        receive(c, {_cement: 0}),
        throwsA(
          _fails(AppErrorKind.validation, containing: 'at least one item'),
        ),
      );
      expect(posts(), isEmpty);
    });

    test(
      'offline when re-reading: a plain error and nothing is sent',
      () async {
        env.adapter.on(
          'GET',
          'procurement/purchase-orders/po1',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          receive(c, {_cement: 1}),
          throwsA(_fails(AppErrorKind.offline)),
        );
        expect(posts(), isEmpty);
      },
    );

    test(
      'a refusal (403) is shown, never retried, and not "recovered"',
      () async {
        order(_order());
        env.adapter.on(
          'POST',
          'procurement/purchase-orders/po1/deliver',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          receive(c, {_cement: 1}),
          throwsA(_fails(AppErrorKind.forbidden)),
        );
        expect(posts(), hasLength(1));
        expect(env.adapter.count('GET', 'procurement/purchase-orders/po1'), 1);
      },
    );

    test('a 400 on an order that has since moved on says so', () async {
      env.adapter
        ..on(
          'GET',
          'procurement/purchase-orders/po1',
          (_) => Reply.json(_order()),
        )
        ..on(
          'GET',
          'procurement/purchase-orders/po1',
          (_) => Reply.json(_order(status: 'RECEIVED')),
        )
        ..on(
          'POST',
          'procurement/purchase-orders/po1/deliver',
          (_) => Reply.json({
            'statusCode': 400,
            'message': 'PO must be SENT or PARTIAL to record a delivery',
          }, status: 400),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        receive(c, {_cement: 1}),
        throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
      );
      expect(posts(), hasLength(1));
    });

    test(
      'any other 400 keeps the server words (the order is still open)',
      () async {
        order(_order());
        env.adapter.on(
          'POST',
          'procurement/purchase-orders/po1/deliver',
          (_) => Reply.json({
            'statusCode': 400,
            'message': ['deliveryDate must be a valid ISO 8601 date string'],
          }, status: 400),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          receive(c, {_cement: 1}),
          throwsA(_fails(AppErrorKind.validation, containing: 'deliveryDate')),
        );
      },
    );

    group('after a timeout the order is read back, never resent', () {
      void timeoutThen(Map<String, dynamic> after) {
        env.adapter
          ..on(
            'GET',
            'procurement/purchase-orders/po1',
            (_) => Reply.json(_order()),
          )
          ..on(
            'GET',
            'procurement/purchase-orders/po1',
            (_) => Reply.json(after),
          )
          ..on(
            'POST',
            'procurement/purchase-orders/po1/deliver',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
      }

      Map<String, dynamic> afterWith(Map<String, dynamic> note) =>
          _order(status: 'PARTIAL', notes: [note]);

      test(
        'my delivery with these quantities, just now: reported as done',
        () async {
          timeoutThen(
            afterWith(
              dnJson(
                id: 'new',
                createdAt: DateTime.now().toUtc(),
                lines: [
                  dnLine(received: 30),
                  dnLine(
                    description: 'River sand',
                    materialId: 'm2',
                    ordered: 5,
                    received: 0,
                  ),
                ],
              ),
            ),
          );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);

          expect(await receive(c, {_cement: 30}), contains('we checked'));
          expect(posts(), hasLength(1));
        },
      );

      test(
        'no new delivery: nothing was recorded and a retry is safe',
        () async {
          timeoutThen(_order());
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            receive(c, {_cement: 30}),
            throwsA(
              _fails(AppErrorKind.timeout, containing: 'nothing was recorded'),
            ),
          );
          expect(posts(), hasLength(1));
        },
      );

      // One disqualifier per case: each would be accepted if its own check
      // were dropped. Every one of them must be reported as a conflict and
      // never as "done" (that would stop the user retrying a delivery that is
      // not recorded) and never as "nothing recorded" (that would invite a
      // second delivery on top of someone else's).
      final notMine = <String, Map<String, dynamic>>{
        "someone else's delivery with the same quantities, just now": dnJson(
          id: 'new',
          by: 'u9',
          createdAt: DateTime.now().toUtc(),
          lines: [dnLine(received: 30)],
        ),
        'my delivery with the same quantities, but from two days ago': dnJson(
          id: 'new',
          createdAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
          lines: [dnLine(received: 30)],
        ),
        'my recent delivery, but with different quantities': dnJson(
          id: 'new',
          createdAt: DateTime.now().toUtc(),
          lines: [dnLine(received: 12)],
        ),
        'my recent delivery with an extra item received': dnJson(
          id: 'new',
          createdAt: DateTime.now().toUtc(),
          lines: [
            dnLine(received: 30),
            dnLine(
              description: 'River sand',
              materialId: 'm2',
              ordered: 5,
              received: 2,
            ),
          ],
        ),
      };
      for (final entry in notMine.entries) {
        test('is not mistaken for mine: ${entry.key}', () async {
          timeoutThen(afterWith(entry.value));
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            receive(c, {_cement: 30}),
            throwsA(
              _fails(
                AppErrorKind.validation,
                containing: 'Another delivery was recorded',
              ),
            ),
          );
          expect(posts(), hasLength(1));
        });
      }

      test(
        'a delivery that was already there is not mistaken for mine',
        () async {
          // dn1 existed before; the timed-out request added nothing
          final existing = dnJson(
            createdAt: DateTime.now().toUtc(),
            lines: [dnLine(received: 30)],
          );
          env.adapter
            ..on(
              'GET',
              'procurement/purchase-orders/po1',
              (_) => Reply.json(_order(status: 'PARTIAL', notes: [existing])),
            )
            ..on(
              'POST',
              'procurement/purchase-orders/po1/deliver',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            receive(c, {_cement: 10}),
            throwsA(
              _fails(AppErrorKind.timeout, containing: 'nothing was recorded'),
            ),
          );
        },
      );

      test('the check also fails: the outcome stays unknown', () async {
        env.adapter
          ..on(
            'GET',
            'procurement/purchase-orders/po1',
            (_) => Reply.json(_order()),
          )
          ..on(
            'GET',
            'procurement/purchase-orders/po1',
            (_) => Reply.fail(DioExceptionType.connectionError),
          )
          ..on(
            'POST',
            'procurement/purchase-orders/po1/deliver',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          receive(c, {_cement: 30}),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        expect(posts(), hasLength(1));
      });
    });

    test(
      'a recorded delivery refreshes the stock the Materials screen shows',
      () async {
        order(_order());
        deliverOk();
        env.adapter.on(
          'GET',
          'materials',
          (_) => Reply.json(paged([], limit: 20)),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(materialCatalogProvider, (_, _) {});
        await pumpEventQueue(times: 20);
        expect(env.adapter.count('GET', 'materials'), 1);

        await receive(c, {_cement: 10});
        await pumpEventQueue(times: 20);

        expect(env.adapter.count('GET', 'materials'), 2);
      },
    );
  });
}
