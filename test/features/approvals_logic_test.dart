import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/approvals/application/approvals_providers.dart';
import 'package:builder_pro_mobile/features/approvals/data/approval_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  /// GET replies after the first load, consumed in order (then the default page).
  final nextGets = <Reply Function(RequestOptions)>[];

  Future<ProviderContainer> open(
    List<Map<String, dynamic>> rows, {
    int total = 0,
  }) async {
    nextGets.clear();
    final defaultPage = paged(
      rows,
      limit: 50,
      total: total == 0 ? rows.length : total,
    );
    env.adapter.on(
      'GET',
      'time-tracking',
      (o) =>
          nextGets.isEmpty ? Reply.json(defaultPage) : nextGets.removeAt(0)(o),
    );
    final c = makeContainer(env, perms: supervisorPerms);
    addTearDown(c.dispose);
    c.listen(approvalsProvider, (_, _) {});
    await c.read(approvalsProvider.future);
    return c;
  }

  group('reading', () {
    test(
      'asks for PENDING entries of everyone: no workerId, page and limit sent',
      () async {
        await open([approvalEntryJson()]);
        final q = env.adapter.last('GET', 'time-tracking').query;
        expect(q['status'], 'PENDING');
        expect(q['page'], 1);
        expect(q['limit'], 50);
        expect(q.containsKey('workerId'), isFalse);
      },
    );

    test(
      'parses worker, project, task and sums regular + overtime hours',
      () async {
        final c = await open([
          approvalEntryJson(
            regular: '8.00',
            overtime: '1.50',
            manual: true,
            notes: 'Forgot to clock in',
          ),
        ]);
        final e = c.read(approvalsProvider).value!.entries.single;
        expect(e.workerName, 'Tendai Moyo');
        expect(e.projectLabel, 'HT-01 · Harare Tower');
        expect(e.taskTitle, 'Pour slab');
        expect(e.totalHours, 9.5);
        expect(e.isManual, isTrue);
        expect(e.notes, 'Forgot to clock in');
      },
    );

    test('pay information is never read into the model', () {
      final e = ApprovalEntry.tryParse(approvalEntryJson())!;
      // No field exposes the rate or cost: only hours.
      expect(e.toString(), isNot(contains('40.00')));
    });

    test(
      'still-clocked-in entries are "working", not ready to approve',
      () async {
        final c = await open([
          approvalEntryJson(id: 'done'),
          approvalEntryJson(
            id: 'live',
            workerId: 'w2',
            first: 'Rudo',
            last: 'Banda',
            open: true,
            clockIn: DateTime.now().subtract(const Duration(hours: 2)),
          ),
        ]);
        final s = c.read(approvalsProvider).value!;
        expect(s.ready.map((e) => e.id), ['done']);
        expect(s.working.map((e) => e.id), ['live']);
        expect(s.working.single.isOpen, isTrue);
      },
    );

    test('groups by worker A-Z with newest shift first and a total', () {
      final day = DateTime(2026, 10, 20, 7);
      final groups = groupByWorker([
        for (final (id, w, first, d) in [
          ('a', 'w2', 'Rudo', 1),
          ('b', 'w1', 'Tendai', 1),
          ('c', 'w1', 'Tendai', 3),
        ])
          ApprovalEntry.tryParse(
            approvalEntryJson(
              id: id,
              workerId: w,
              first: first,
              last: 'X',
              clockIn: day.add(Duration(days: d)),
            ),
          )!,
      ]);
      expect(groups.map((g) => g.workerName), ['Rudo X', 'Tendai X']);
      expect(groups.last.entries.map((e) => e.id), ['c', 'b']);
      expect(groups.last.totalHours, 16);
    });

    test('load more appends older entries without duplicates', () async {
      env.adapter
        ..on(
          'GET',
          'time-tracking',
          (_) => Reply.json(
            paged([approvalEntryJson(id: 'a')], limit: 1, total: 2),
          ),
        )
        ..on(
          'GET',
          'time-tracking',
          (_) => Reply.json(
            paged(
              [approvalEntryJson(id: 'a'), approvalEntryJson(id: 'b')],
              page: 2,
              limit: 1,
              total: 2,
            ),
          ),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(approvalsProvider, (_, _) {});
      await c.read(approvalsProvider.future);
      expect(c.read(approvalsProvider).value!.hasMore, isTrue);

      await c.read(approvalsProvider.notifier).loadMore();

      expect(c.read(approvalsProvider).value!.entries.map((e) => e.id), [
        'a',
        'b',
      ]);
      expect(env.adapter.last('GET', 'time-tracking').query['page'], 2);
    });

    test('a failed load is an error, not an empty "all caught up"', () async {
      env.adapter.on(
        'GET',
        'time-tracking',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(approvalsProvider, (_, _) {});
      await expectLater(
        c.read(approvalsProvider.future),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('deciding', () {
    ApprovalEntry entryOf(ProviderContainer c, String id) =>
        c.read(approvalsProvider).value!.entries.firstWhere((e) => e.id == id);

    test('approve sends APPROVED and removes the entry', () async {
      final c = await open([
        approvalEntryJson(id: 'a'),
        approvalEntryJson(id: 'b'),
      ]);
      env.adapter.on('PUT', 'time-tracking/a/approve', (_) => Reply.json({}));

      await c
          .read(approvalsProvider.notifier)
          .decide(entryOf(c, 'a'), approve: true);

      expect(env.adapter.last('PUT', 'time-tracking/a/approve').data, {
        'status': 'APPROVED',
      });
      expect(c.read(approvalsProvider).value!.entries.map((e) => e.id), ['b']);
      expect(c.read(approvalsProvider).value!.total, 1);
    });

    test('reject sends REJECTED with the trimmed reason; a blank reason is omitted', () async {
      final c = await open([
        approvalEntryJson(id: 'a'),
        approvalEntryJson(id: 'b'),
      ]);
      env.adapter
        ..on('PUT', 'time-tracking/a/approve', (_) => Reply.json({}))
        ..on('PUT', 'time-tracking/b/approve', (_) => Reply.json({}));
      final n = c.read(approvalsProvider.notifier);

      await n.decide(
        entryOf(c, 'a'),
        approve: false,
        comment: '  Wrong project  ',
      );
      expect(env.adapter.last('PUT', 'time-tracking/a/approve').data, {
        'status': 'REJECTED',
        'approvalComment': 'Wrong project',
      });

      await n.decide(entryOf(c, 'b'), approve: false, comment: '   ');
      expect(env.adapter.last('PUT', 'time-tracking/b/approve').data, {
        'status': 'REJECTED',
      });
    });

    test('a refusal (403) keeps the entry and surfaces the error', () async {
      final c = await open([approvalEntryJson(id: 'a')]);
      env.adapter.on(
        'PUT',
        'time-tracking/a/approve',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );

      await expectLater(
        c
            .read(approvalsProvider.notifier)
            .decide(entryOf(c, 'a'), approve: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(c.read(approvalsProvider).value!.entries, hasLength(1));
    });

    test(
      'no connection keeps the entry (decisions are never queued offline)',
      () async {
        final c = await open([approvalEntryJson(id: 'a')]);
        env.adapter.on(
          'PUT',
          'time-tracking/a/approve',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );

        await expectLater(
          c
              .read(approvalsProvider.notifier)
              .decide(entryOf(c, 'a'), approve: true),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.offline,
            ),
          ),
        );
        expect(c.read(approvalsProvider).value!.entries, hasLength(1));
        expect(await env.db.outboxFor('u1'), isEmpty);
      },
    );

    test('a timed-out decision is sent once more (it only sets a status) and then succeeds', () async {
      final c = await open([approvalEntryJson(id: 'a')]);
      env.adapter
        ..on(
          'PUT',
          'time-tracking/a/approve',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on('PUT', 'time-tracking/a/approve', (_) => Reply.json({}));

      await c
          .read(approvalsProvider.notifier)
          .decide(entryOf(c, 'a'), approve: true);

      expect(env.adapter.count('PUT', 'time-tracking/a/approve'), 2);
      expect(c.read(approvalsProvider).value!.entries, isEmpty);
    });

    test(
      'if the retry also times out the entry stays and the outcome is unknown',
      () async {
        final c = await open([approvalEntryJson(id: 'a')]);
        env.adapter.on(
          'PUT',
          'time-tracking/a/approve',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        );

        await expectLater(
          c
              .read(approvalsProvider.notifier)
              .decide(entryOf(c, 'a'), approve: true),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        expect(
          env.adapter.count('PUT', 'time-tracking/a/approve'),
          2,
        ); // never more than one retry
        expect(c.read(approvalsProvider).value!.entries, hasLength(1));
      },
    );

    test('an entry that turned out to be clocked in gives a plain message and refreshes the list', () async {
      final c = await open([approvalEntryJson(id: 'a')]);
      env.adapter.on(
        'PUT',
        'time-tracking/a/approve',
        (_) => Reply.json({
          'statusCode': 400,
          'message': 'Cannot approve active clock-in',
        }, status: 400),
      );
      nextGets.add(
        (_) => Reply.json(
          paged([approvalEntryJson(id: 'a', open: true)], limit: 50),
        ),
      );

      await expectLater(
        c
            .read(approvalsProvider.notifier)
            .decide(entryOf(c, 'a'), approve: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('still clocked in'),
          ),
        ),
      );
      expect(c.read(approvalsProvider).value!.working.single.id, 'a');
    });
  });
}
