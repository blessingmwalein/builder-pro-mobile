import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/equipment/application/equipment_providers.dart';
import 'package:builder_pro_mobile/features/equipment/data/equipment_models.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

/// A message the user would see, for `throwsA`.
Matcher _fails(AppErrorKind kind, {String? containing}) => isA<AppException>()
    .having((e) => e.kind, 'kind', kind)
    .having((e) => e.message, 'message', contains(containing ?? ''));

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  /// Items as the API sends them for one piece of equipment.
  Map<String, dynamic> inUse(List<Map<String, dynamic>> allocations) =>
      equipJson(detail: true, status: 'IN_USE', allocations: allocations);

  Map<String, dynamic> available([
    List<Map<String, dynamic>> allocations = const [],
  ]) => equipJson(detail: true, allocations: allocations);

  group('models', () {
    test('a summary reads name, status, category, serial and history size', () {
      final s = EquipmentSummary.tryParse(
        equipJson(
          allocations: [
            allocJson(),
            allocJson(id: 'a2'),
          ],
        ),
      )!;
      expect(s.name, 'Excavator CAT 320');
      expect(s.status, 'AVAILABLE');
      expect(s.categoryName, 'Heavy plant');
      expect(s.serialNumber, 'CAT-0042');
      expect(s.assignmentCount, 2);
      expect(s.isAvailable, isTrue);
    });

    test('rows without an id or a name are skipped', () {
      expect(EquipmentSummary.tryParse({'name': 'x'}), isNull);
      expect(EquipmentSummary.tryParse({'id': 'e1'}), isNull);
      expect(EquipmentSummary.tryParse('nope'), isNull);
    });

    test('an assignment keeps calendar days and who assigned it', () {
      final a = EquipmentAssignment.tryParse(
        allocJson(
          start: DateTime.utc(2026, 10, 26),
          end: DateTime.utc(2026, 11, 9),
          notes: 'Slab pour',
        ),
      )!;
      expect(a.startDate, DateTime.utc(2026, 10, 26));
      expect(a.endDate, DateTime.utc(2026, 11, 9));
      expect(a.assignedBy, 'Tendai Moyo');
      expect(a.assignedById, 'u1');
      expect(a.projectName, 'Harare Tower');
      expect(a.isOpen, isTrue);
      expect(a.notes, 'Slab pour');
    });

    test('an assignment with a return time is closed', () {
      final a = EquipmentAssignment.tryParse(
        allocJson(returnedAt: DateTime.utc(2026, 10, 30, 9)),
      )!;
      expect(a.isOpen, isFalse);
    });

    test('only one open assignment on an item in use can be returned', () {
      EquipmentDetail parse(Map<String, dynamic> json) =>
          EquipmentDetail.tryParse(json)!;

      expect(parse(inUse([allocJson()])).returnable?.id, 'a1');
      // closed history does not count
      expect(
        parse(
          inUse([
            allocJson(),
            allocJson(id: 'old', returnedAt: DateTime.utc(2026, 9, 1)),
          ]),
        ).returnable?.id,
        'a1',
      );
      // two open: which one is meant is unclear
      expect(
        parse(inUse([allocJson(), allocJson(id: 'a2')])).returnable,
        isNull,
      );
      // in use but nothing open in the recent list
      expect(parse(inUse([])).returnable, isNull);
      // not in use: nothing to return
      expect(parse(available([allocJson()])).returnable, isNull);
    });

    test('a detail without a usable item is null', () {
      expect(EquipmentDetail.tryParse({'unexpected': true}), isNull);
    });
  });

  group('lists', () {
    test('asked for with page, limit and the status filter', () async {
      env.adapter.on(
        'GET',
        'equipment',
        (_) => Reply.json(paged([equipJson()], limit: 20)),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(equipmentCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);

      var q = env.adapter.last('GET', 'equipment').query;
      expect(q['page'], 1);
      expect(q['limit'], 20);
      expect(q.containsKey('status'), isFalse);

      await c.read(equipmentCatalogProvider.notifier).setFilter('IN_USE');
      q = env.adapter.last('GET', 'equipment').query;
      expect(q['status'], 'IN_USE');
      expect(
        c.read(equipmentCatalogProvider).items.single.name,
        contains('CAT'),
      );
    });

    test(
      'a 403 (no materials.view) is an error state, not an empty list',
      () async {
        env.adapter.on(
          'GET',
          'equipment',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(equipmentCatalogProvider, (_, _) {});
        await pumpEventQueue(times: 20);
        expect(
          c.read(equipmentCatalogProvider).error?.kind,
          AppErrorKind.forbidden,
        );
      },
    );

    test('a malformed detail is an error', () async {
      env.adapter.on(
        'GET',
        'equipment/bad',
        (_) => Reply.json({'unexpected': true}),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(equipmentDetailProvider('bad'), (_, _) {});
      await expectLater(
        c.read(equipmentDetailProvider('bad').future),
        throwsA(_fails(AppErrorKind.malformed)),
      );
    });
  });

  group('assign', () {
    final start = DateTime(2026, 10, 27);

    Future<String?> assign(
      dynamic c, {
      DateTime? end,
      String? notes,
      String project = 'p1',
    }) => c
        .read(equipmentActionsProvider)
        .assign('e1', projectId: project, start: start, end: end, notes: notes);

    test('sends the project, calendar days and a trimmed note', () async {
      env.adapter.on(
        'POST',
        'equipment/e1/allocate',
        (_) => Reply.json(allocJson(), status: 201),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      final note = await assign(
        c,
        end: DateTime(2026, 11, 9),
        notes: '  Slab pour  ',
      );

      expect(note, isNull);
      expect(env.adapter.last('POST', 'equipment/e1/allocate').data, {
        'projectId': 'p1',
        'startDate': '2026-10-27',
        'endDate': '2026-11-09',
        'notes': 'Slab pour',
      });
    });

    test('no return date and a blank note are left out', () async {
      env.adapter.on(
        'POST',
        'equipment/e1/allocate',
        (_) => Reply.json(allocJson(), status: 201),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await assign(c, notes: '   ');
      expect(env.adapter.last('POST', 'equipment/e1/allocate').data, {
        'projectId': 'p1',
        'startDate': '2026-10-27',
      });
    });

    test(
      'a refusal (403) is shown, not retried and nothing is looked up',
      () async {
        env.adapter.on(
          'POST',
          'equipment/e1/allocate',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(assign(c), throwsA(_fails(AppErrorKind.forbidden)));
        expect(env.adapter.count('POST', 'equipment/e1/allocate'), 1);
        expect(env.adapter.count('GET', 'equipment/e1'), 0);
      },
    );

    test(
      'a 400 on an item that has since been taken says it is unavailable',
      () async {
        env.adapter
          ..on(
            'POST',
            'equipment/e1/allocate',
            (_) => Reply.json({
              'statusCode': 400,
              'message':
                  'Equipment is currently IN_USE and cannot be allocated',
            }, status: 400),
          )
          ..on(
            'GET',
            'equipment/e1',
            (_) => Reply.json(inUse([allocJson(by: 'u9')])),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          assign(c),
          throwsA(
            _fails(AppErrorKind.validation, containing: 'no longer available'),
          ),
        );
        expect(env.adapter.count('POST', 'equipment/e1/allocate'), 1);
      },
    );

    test(
      'any other 400 keeps the server words (the item is still available)',
      () async {
        env.adapter
          ..on(
            'POST',
            'equipment/e1/allocate',
            (_) => Reply.json({
              'statusCode': 400,
              'message': ['startDate must be a valid ISO 8601 date string'],
            }, status: 400),
          )
          ..on('GET', 'equipment/e1', (_) => Reply.json(available()));
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          assign(c),
          throwsA(_fails(AppErrorKind.validation, containing: 'startDate')),
        );
      },
    );

    group('after a timeout the item is read back, never resent', () {
      void timeoutPost() => env.adapter.on(
        'POST',
        'equipment/e1/allocate',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      );

      test('assigned to my project just now: reported as done', () async {
        timeoutPost();
        env.adapter.on(
          'GET',
          'equipment/e1',
          (_) =>
              Reply.json(inUse([allocJson(createdAt: DateTime.now().toUtc())])),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);

        final note = await assign(c);

        expect(note, contains('we checked'));
        expect(env.adapter.count('POST', 'equipment/e1/allocate'), 1);
      });

      test(
        'still available: nothing was recorded and a retry is safe',
        () async {
          timeoutPost();
          env.adapter.on('GET', 'equipment/e1', (_) => Reply.json(available()));
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            assign(c),
            throwsA(
              _fails(AppErrorKind.timeout, containing: 'nothing was recorded'),
            ),
          );
          expect(env.adapter.count('POST', 'equipment/e1/allocate'), 1);
        },
      );

      // One disqualifier per case: each would be accepted if its own check
      // were dropped.
      final notMine = <String, Map<String, dynamic>>{
        "someone else's assignment, made just now": allocJson(
          by: 'u9',
          createdAt: DateTime.now().toUtc(),
        ),
        'my assignment to a different project': allocJson(
          projectId: 'p2',
          createdAt: DateTime.now().toUtc(),
        ),
        'my assignment to this project, but from two days ago': allocJson(
          createdAt: DateTime.now().toUtc().subtract(const Duration(days: 2)),
        ),
      };
      for (final entry in notMine.entries) {
        test('is not mistaken for mine: ${entry.key}', () async {
          timeoutPost();
          env.adapter.on(
            'GET',
            'equipment/e1',
            (_) => Reply.json(inUse([entry.value])),
          );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            assign(c),
            throwsA(
              _fails(
                AppErrorKind.validation,
                containing: 'no longer available',
              ),
            ),
          );
        });
      }

      test('the check also fails: the outcome stays unknown', () async {
        timeoutPost();
        env.adapter.on(
          'GET',
          'equipment/e1',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          assign(c),
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

  group('return', () {
    Future<String?> giveBack(dynamic c) =>
        c.read(equipmentActionsProvider).returnItem('e1', 'a1');

    test('re-reads first, then closes the one open assignment', () async {
      env.adapter
        ..on('GET', 'equipment/e1', (_) => Reply.json(inUse([allocJson()])))
        ..on(
          'POST',
          'equipment/e1/return/a1',
          (_) => Reply.json({'success': true}, status: 201),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      expect(await giveBack(c), isNull);

      expect(env.adapter.count('GET', 'equipment/e1'), 1);
      expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 1);
    });

    test(
      'an assignment already closed by someone else is not closed again',
      () async {
        env.adapter.on(
          'GET',
          'equipment/e1',
          (_) => Reply.json(
            available([allocJson(returnedAt: DateTime.utc(2026, 10, 27, 8))]),
          ),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
          throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
        );
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    test(
      'an item sent on to another site is not freed by a stale return',
      () async {
        env.adapter.on(
          'GET',
          'equipment/e1',
          // a1 was closed and the item has a NEW open assignment a9
          (_) => Reply.json(
            inUse([
              allocJson(id: 'a9', project: 'Other site', projectId: 'p2'),
              allocJson(returnedAt: DateTime.utc(2026, 10, 27, 8)),
            ]),
          ),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
          throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
        );
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    test(
      'two open assignments: which to close is unclear, so nothing is sent',
      () async {
        env.adapter.on(
          'GET',
          'equipment/e1',
          (_) => Reply.json(inUse([allocJson(), allocJson(id: 'a2')])),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
          throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
        );
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    test(
      'offline when re-reading: a plain error and nothing is sent',
      () async {
        env.adapter.on(
          'GET',
          'equipment/e1',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.offline,
            ),
          ),
        );
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    test('a refusal (403) is shown and never retried', () async {
      env.adapter
        ..on('GET', 'equipment/e1', (_) => Reply.json(inUse([allocJson()])))
        ..on(
          'POST',
          'equipment/e1/return/a1',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(giveBack(c), throwsA(_fails(AppErrorKind.forbidden)));
      expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 1);
    });

    test('a 400 means it changed in the meantime', () async {
      env.adapter
        ..on('GET', 'equipment/e1', (_) => Reply.json(inUse([allocJson()])))
        ..on(
          'POST',
          'equipment/e1/return/a1',
          (_) => Reply.json({
            'statusCode': 400,
            'message': 'Equipment is not currently in use',
          }, status: 400),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        giveBack(c),
        throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
      );
    });

    group('after a timeout the assignment is read back, never resent', () {
      void timeoutThen(Map<String, dynamic> after) {
        env.adapter
          ..on('GET', 'equipment/e1', (_) => Reply.json(inUse([allocJson()])))
          ..on('GET', 'equipment/e1', (_) => Reply.json(after))
          ..on(
            'POST',
            'equipment/e1/return/a1',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
      }

      test('closed on the server: reported as done', () async {
        timeoutThen(
          available([allocJson(returnedAt: DateTime.utc(2026, 10, 27, 9))]),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        expect(await giveBack(c), contains('we checked'));
        expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 1);
      });

      test('still open: nothing was recorded and a retry is safe', () async {
        timeoutThen(inUse([allocJson()]));
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
          throwsA(
            _fails(AppErrorKind.timeout, containing: 'nothing was recorded'),
          ),
        );
        expect(env.adapter.count('POST', 'equipment/e1/return/a1'), 1);
      });

      test('the assignment is gone from the list: it moved on', () async {
        timeoutThen(inUse([allocJson(id: 'a9', projectId: 'p2')]));
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
          throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
        );
      });

      test('the check also fails: the outcome stays unknown', () async {
        env.adapter
          ..on('GET', 'equipment/e1', (_) => Reply.json(inUse([allocJson()])))
          ..on(
            'GET',
            'equipment/e1',
            (_) => Reply.fail(DioExceptionType.connectionError),
          )
          ..on(
            'POST',
            'equipment/e1/return/a1',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          giveBack(c),
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
