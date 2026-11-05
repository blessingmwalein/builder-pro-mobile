import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/time/application/time_providers.dart';
import 'package:builder_pro_mobile/features/time/data/time_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';

const _project = ProjectRef(id: 'p1', name: 'Harare Tower', code: 'HT-01');

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  test('GET active with an empty 200 body means not clocked in', () async {
    env.adapter.on('GET', 'time-tracking/active', (_) => Reply.empty());
    final c = makeContainer(env);
    addTearDown(c.dispose);

    final state = await c.read(clockProvider.future);
    expect(state.active, isNull);
    expect(state.lastKnown, isFalse);
  });

  test('an open entry is parsed, with string decimals', () async {
    env.adapter.on(
      'GET',
      'time-tracking/active',
      (_) => Reply.json(timeEntryJson(regularHours: '7.50')),
    );
    final c = makeContainer(env);
    addTearDown(c.dispose);

    final active = (await c.read(clockProvider.future)).active!;
    expect(active.isOpen, isTrue);
    expect(active.regularHours, 7.5);
    expect(active.project.label, 'HT-01 · Harare Tower');
  });

  test('clock in posts the project and keeps the project name', () async {
    env.adapter
      ..on('GET', 'time-tracking/active', (_) => Reply.empty())
      ..on(
        'POST',
        'time-tracking/clock-in',
        // The create reply has no project object.
        (_) => Reply.json(timeEntryJson(withProject: false), status: 201),
      );
    final c = makeContainer(env);
    addTearDown(c.dispose);
    await c.read(clockProvider.future);

    final note = await c
        .read(clockProvider.notifier)
        .clockIn(_project, taskId: 't9', taskTitle: 'Pour slab');

    expect(note, isNull);
    final sent = env.adapter.last('POST', 'time-tracking/clock-in').data;
    expect(sent, {'projectId': 'p1', 'taskId': 't9'});
    final active = c.read(clockProvider).value!.active!;
    expect(active.projectName, 'Harare Tower');
    expect(active.taskTitle, 'Pour slab');
  });

  test(
    'clock in while already clocked in elsewhere reloads, no duplicate',
    () async {
      env.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'GET',
          'time-tracking/active',
          (_) => Reply.json(timeEntryJson(id: 'web-entry')),
        )
        ..on(
          'POST',
          'time-tracking/clock-in',
          (_) => Reply.json({
            'statusCode': 400,
            'message': 'Open time entry already exists. Clock out first.',
          }, status: 400),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(clockProvider.future);

      final note = await c.read(clockProvider.notifier).clockIn(_project);

      expect(note, contains('already clocked in'));
      expect(c.read(clockProvider).value!.active!.id, 'web-entry');
      expect(env.adapter.count('POST', 'time-tracking/clock-in'), 1);
    },
  );

  test(
    'a timed-out clock in that actually saved is detected, not repeated',
    () async {
      env.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'POST',
          'time-tracking/clock-in',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on(
          'GET',
          'time-tracking/active',
          (_) => Reply.json(timeEntryJson(id: 'saved')),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(clockProvider.future);

      final note = await c.read(clockProvider.notifier).clockIn(_project);

      expect(note, contains('clocked in'));
      expect(c.read(clockProvider).value!.active!.id, 'saved');
      expect(env.adapter.count('POST', 'time-tracking/clock-in'), 1);
    },
  );

  test(
    'a timed-out clock in that did NOT save says so and allows a retry',
    () async {
      env.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'POST',
          'time-tracking/clock-in',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on('GET', 'time-tracking/active', (_) => Reply.empty());
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(clockProvider.future);

      await expectLater(
        c.read(clockProvider.notifier).clockIn(_project),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('not clocked in'),
          ),
        ),
      );
      expect(c.read(clockProvider).value!.active, isNull);
    },
  );

  test(
    'when even the check fails, the outcome stays unknown (error rethrown)',
    () async {
      env.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'POST',
          'time-tracking/clock-in',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on(
          'GET',
          'time-tracking/active',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(clockProvider.future);

      await expectLater(
        c.read(clockProvider.notifier).clockIn(_project),
        throwsA(
          isA<AppException>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            isTrue,
          ),
        ),
      );
    },
  );

  test('clock out sends the break and clears the active entry', () async {
    env.adapter
      ..on(
        'GET',
        'time-tracking/active',
        (_) => Reply.json(timeEntryJson(id: 'te1')),
      )
      ..on(
        'PUT',
        'time-tracking/te1/clock-out',
        (_) => Reply.json(
          timeEntryJson(
            id: 'te1',
            clockOutAt: DateTime.now().toUtc().toIso8601String(),
            regularHours: '8.00',
          ),
        ),
      );
    final c = makeContainer(env);
    addTearDown(c.dispose);
    await c.read(clockProvider.future);

    final note = await c
        .read(clockProvider.notifier)
        .clockOut(breakMinutes: 30);

    expect(note, isNull);
    expect(env.adapter.last('PUT', 'time-tracking/te1/clock-out').data, {
      'breakMinutes': 30,
    });
    expect(c.read(clockProvider).value!.active, isNull);
  });

  test(
    'clock out of an entry already closed on the web reloads quietly',
    () async {
      env.adapter
        ..on(
          'GET',
          'time-tracking/active',
          (_) => Reply.json(timeEntryJson(id: 'te1')),
        )
        ..on(
          'PUT',
          'time-tracking/te1/clock-out',
          (_) => Reply.json({
            'statusCode': 400,
            'message': 'Time entry already closed',
          }, status: 400),
        )
        ..on('GET', 'time-tracking/active', (_) => Reply.empty());
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(clockProvider.future);

      final note = await c.read(clockProvider.notifier).clockOut();

      expect(note, contains('already closed'));
      expect(c.read(clockProvider).value!.active, isNull);
    },
  );

  test('a timed-out clock out that saved is detected', () async {
    env.adapter
      ..on(
        'GET',
        'time-tracking/active',
        (_) => Reply.json(timeEntryJson(id: 'te1')),
      )
      ..on(
        'PUT',
        'time-tracking/te1/clock-out',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      )
      ..on('GET', 'time-tracking/active', (_) => Reply.empty());
    final c = makeContainer(env);
    addTearDown(c.dispose);
    await c.read(clockProvider.future);

    final note = await c.read(clockProvider.notifier).clockOut();

    expect(note, contains('clocked out'));
    expect(c.read(clockProvider).value!.active, isNull);
    expect(env.adapter.count('PUT', 'time-tracking/te1/clock-out'), 1);
  });

  test(
    'a timed-out clock out that did not save keeps the worker clocked in',
    () async {
      env.adapter
        ..on(
          'GET',
          'time-tracking/active',
          (_) => Reply.json(timeEntryJson(id: 'te1')),
        )
        ..on(
          'PUT',
          'time-tracking/te1/clock-out',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on(
          'GET',
          'time-tracking/active',
          (_) => Reply.json(timeEntryJson(id: 'te1')),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(clockProvider.future);

      await expectLater(
        c.read(clockProvider.notifier).clockOut(),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('still clocked in'),
          ),
        ),
      );
      expect(c.read(clockProvider).value!.active!.id, 'te1');
    },
  );

  test('offline at start shows the last known state, flagged', () async {
    // First run online while clocked in, which caches the entry.
    env.adapter.on(
      'GET',
      'time-tracking/active',
      (_) => Reply.json(timeEntryJson(id: 'te1')),
    );
    final first = makeContainer(env);
    await first.read(clockProvider.future);
    first.dispose();

    // Second run with no connection.
    final env2 = TestEnv(database: env.db);
    env2.adapter.on(
      'GET',
      'time-tracking/active',
      (_) => Reply.fail(DioExceptionType.connectionError),
    );
    final c = makeContainer(env2);
    addTearDown(c.dispose);

    final state = await c.read(clockProvider.future);
    expect(state.lastKnown, isTrue);
    expect(state.active!.id, 'te1');
  });

  test(
    'offline with nothing cached is an error, not a fake "not clocked in"',
    () async {
      env.adapter.on(
        'GET',
        'time-tracking/active',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);

      await expectLater(
        c.read(clockProvider.future),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('weekly summary sends the local Monday as an instant; entries are filtered to the user', () async {
    env.adapter
      ..on(
        'GET',
        'time-tracking/weekly-summary',
        (_) => Reply.json({
          'weekStart': '2026-10-25T22:00:00.000Z',
          'totalRegularHours': 16,
          'totalOvertimeHours': 2.5,
          'totalHours': 18.5,
          'estimatedGrossPay': 100,
          'entries': [
            timeEntryJson(
              regularHours: '8.00',
              clockOutAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        }),
      )
      ..on('GET', 'time-tracking', (_) => Reply.json(paged([timeEntryJson()])));
    final c = makeContainer(env);
    addTearDown(c.dispose);

    final week = await c.read(weekSummaryProvider.future);
    expect(week.totalHours, 18.5);
    final q = env.adapter.last('GET', 'time-tracking/weekly-summary').query;
    final start = DateTime.parse(q['weekStart'] as String).toLocal();
    expect(start.weekday, DateTime.monday);
    expect(start.hour, 0);

    await c.read(recentEntriesProvider.future);
    expect(env.adapter.last('GET', 'time-tracking').query['workerId'], 'u1');
  });
}
