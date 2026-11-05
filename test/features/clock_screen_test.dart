import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

void _clockApis(
  TestEnv env, {
  Map<String, dynamic>? active,
  bool tasks = true,
  bool history = true,
}) {
  env.adapter
    ..on(
      'GET',
      'time-tracking/active',
      (_) => active == null ? Reply.empty() : Reply.json(active),
    )
    ..on('GET', 'tasks/my-queue', (_) => Reply.json(tasks ? [taskJson()] : []))
    ..on(
      'GET',
      'time-tracking/weekly-summary',
      (_) => Reply.json({
        'weekStart': DateTime.now().toUtc().toIso8601String(),
        'totalRegularHours': 12,
        'totalOvertimeHours': 1.5,
        'totalHours': 13.5,
        'entries': [],
      }),
    )
    ..on(
      'GET',
      'time-tracking',
      (_) => Reply.json(
        paged(
          !history
              ? []
              : [
                  timeEntryJson(
                    id: 'old',
                    clockInAt: DateTime.now()
                        .subtract(const Duration(days: 1, hours: 9))
                        .toUtc()
                        .toIso8601String(),
                    clockOutAt: DateTime.now()
                        .subtract(const Duration(days: 1))
                        .toUtc()
                        .toIso8601String(),
                    regularHours: '8.00',
                    status: 'APPROVED',
                  ),
                ],
        ),
      ),
    );
}

void main() {
  testWidgets('not clocked in: shows the project and a Clock in button', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _clockApis(env);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);

    expect(find.text('Not clocked in'), findsOneWidget);
    expect(find.text('HT-01 · Harare Tower'), findsWidgets);
    expect(find.text('Clock in'), findsOneWidget);
    // Totals and history load too.
    expect(find.text('THIS WEEK'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Clock in clocks in once and shows the running timer', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _clockApis(env);
    env.adapter.on(
      'POST',
      'time-tracking/clock-in',
      (_) => Reply.json(timeEntryJson(withProject: false), status: 201),
    );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);

    await tester.tap(find.text('Clock in'));
    await settle(tester);

    expect(find.text('Clocked in'), findsOneWidget);
    expect(find.text('Clock out'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d\d:\d\d:\d\d$')), findsOneWidget);
    expect(env.adapter.count('POST', 'time-tracking/clock-in'), 1);
  });

  testWidgets(
    'a double tap while the request is slow sends only one clock-in',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _clockApis(env);
      env.adapter.on(
        'POST',
        'time-tracking/clock-in',
        (_) => Reply.json(
          timeEntryJson(withProject: false),
          status: 201,
          delay: const Duration(seconds: 2),
        ),
      );
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);

      await tester.tap(find.text('Clock in'));
      await tester.pump(const Duration(milliseconds: 100));
      // The button is now busy; a second tap lands on the spinner.
      await tester.tap(
        find.byType(CircularProgressIndicator).first,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(env.adapter.count('POST', 'time-tracking/clock-in'), 1);
    },
  );

  testWidgets('clocked in: Clock out asks for the break, then sends it', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _clockApis(
      env,
      active: timeEntryJson(
        clockInAt: DateTime.now()
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
      ),
    );
    env.adapter.on(
      'PUT',
      'time-tracking/te1/clock-out',
      (_) => Reply.json(
        timeEntryJson(
          clockOutAt: DateTime.now().toUtc().toIso8601String(),
          regularHours: '3.00',
        ),
      ),
    );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);

    expect(find.text('Clocked in'), findsOneWidget);
    await tester.tap(find.text('Clock out'));
    await settle(tester);
    expect(find.text('Unpaid break'), findsOneWidget);
    expect(find.textContaining('You worked 3h'), findsOneWidget);

    await tester.tap(find.text('30 min'));
    await settle(tester);
    expect(find.textContaining('You worked 2h 30m'), findsOneWidget);

    await tester.tap(find.widgetWithText(InkWell, 'Clock out').last);
    await settle(tester);

    expect(env.adapter.last('PUT', 'time-tracking/te1/clock-out').data, {
      'breakMinutes': 30,
    });
    expect(find.text('Not clocked in'), findsOneWidget);
  });

  testWidgets(
    'no assigned tasks and no history: explains why there is no project',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _clockApis(env, tasks: false, history: false);
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);

      expect(find.text('No project to clock in on'), findsOneWidget);
      expect(find.text('Clock in'), findsNothing);
    },
  );

  testWidgets('offline start: last known clocked-in state, clock out disabled', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    await env.db.putCache(
      'u1',
      'time_active',
      'current',
      '{"id":"te1","projectId":"p1","project":{"id":"p1","name":"Harare Tower","code":"HT-01"},'
          '"clockInAt":"${DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String()}"}',
    );
    env.adapter
      ..on(
        'GET',
        'time-tracking/active',
        (_) => Reply.fail(DioExceptionType.connectionError),
      )
      ..on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.fail(DioExceptionType.connectionError),
      )
      ..on(
        'GET',
        'time-tracking/weekly-summary',
        (_) => Reply.fail(DioExceptionType.connectionError),
      )
      ..on(
        'GET',
        'time-tracking',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);

    expect(find.textContaining('last known clock status'), findsOneWidget);
    expect(find.text('Clocked in'), findsOneWidget);
    expect(find.text('Reconnect to clock out.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'large text and ${dark ? 'dark' : 'light'} theme render without overflow',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _clockApis(
          env,
          active: timeEntryJson(
            clockInAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
          ),
        );
        final capture = ErrorCapture();
        await pumpApp(
          tester,
          session: SessionState.authenticated(testMe()),
          env: env,
          size: const Size(320, 640),
          textScale: 2.0,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await settle(tester);
        expect(find.text('Clock out'), findsWidgets);
        expect(capture.stop(), isEmpty);
      },
    );
  }
}
