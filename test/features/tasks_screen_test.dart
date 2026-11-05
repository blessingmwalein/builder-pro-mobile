import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

String _due(int days) =>
    DateTime.now().add(Duration(days: days)).toUtc().toIso8601String();

void _tasksApis(TestEnv env, List<Map<String, dynamic>> tasks) {
  env.adapter
    // The Clock tab is the landing page for a worker.
    ..on('GET', 'time-tracking/active', (_) => Reply.empty())
    ..on(
      'GET',
      'time-tracking/weekly-summary',
      (_) => Reply.json({'entries': []}),
    )
    ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
    ..on('GET', 'tasks/my-queue', (_) => Reply.json(tasks));
}

Future<void> _openTasks(WidgetTester tester) async {
  await tester.tap(find.text('My Tasks').last);
  await settle(tester);
}

void main() {
  testWidgets(
    'groups tasks by due date and shows status, project and checklist progress',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _tasksApis(env, [
        taskJson(
          id: 'late',
          title: 'Fix railing',
          dueDate: _due(-3),
          status: 'IN_PROGRESS',
        ),
        taskJson(
          id: 'soon',
          title: 'Pour slab',
          dueDate: _due(5),
          checklists: [checklistJson()],
        ),
        taskJson(id: 'none', title: 'Tidy site'),
      ]);
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openTasks(tester);

      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('UPCOMING'), findsOneWidget);
      expect(find.text('NO DUE DATE'), findsOneWidget);
      expect(find.text('Fix railing'), findsOneWidget);
      expect(find.textContaining('Overdue by'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget); // checklist progress
      expect(find.text('In Progress'), findsWidgets);
      expect(find.text('3 open'), findsOneWidget);
    },
  );

  testWidgets('status filter chips narrow the list and "All" restores it', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _tasksApis(env, [
      taskJson(id: 'a', title: 'Fix railing', status: 'IN_PROGRESS'),
      taskJson(id: 'b', title: 'Pour slab', status: 'BLOCKED'),
    ]);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openTasks(tester);

    // The chips scroll sideways on a phone; scroll to the one we want.
    await tester.ensureVisible(find.text('Blocked 1'));
    await tester.tap(find.text('Blocked 1'));
    await settle(tester);
    expect(find.text('Pour slab'), findsOneWidget);
    expect(find.text('Fix railing'), findsNothing);

    await tester.ensureVisible(find.text('All 2'));
    await tester.tap(find.text('All 2'));
    await settle(tester);
    expect(find.text('Fix railing'), findsOneWidget);
  });

  testWidgets('no tasks: a clear empty state', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _tasksApis(env, []);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openTasks(tester);
    expect(find.text('No open tasks'), findsOneWidget);
  });

  testWidgets(
    'offline: saved tasks with a banner saying when they were saved',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      await env.db.replaceCache('u1', 'task', [
        (
          key: 'a',
          json: '{"id":"a","title":"Saved task","status":"TODO","priority":"LOW","project":{"id":"p1","name":"Harare Tower"}}',
        ),
      ]);
      env.adapter
        ..on(
          'GET',
          'time-tracking/active',
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
        )
        ..on(
          'GET',
          'tasks/my-queue',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openTasks(tester);

      expect(
        find.textContaining('Offline. Showing tasks saved at'),
        findsOneWidget,
      );
      expect(find.text('Saved task'), findsOneWidget);
    },
  );

  testWidgets('a task changed offline shows "Waiting to send"', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _tasksApis(env, [taskJson(id: 'a', title: 'Pour slab')]);
    await env.db.enqueue(
      id: 'op1',
      userId: 'u1',
      kind: 'task_status',
      targetId: 'a',
      payload: '{"status":"BLOCKED"}',
    );
    // Sending fails, so it stays queued.
    env.adapter.on(
      'PUT',
      'tasks/a/status',
      (_) => Reply.fail(DioExceptionType.connectionError),
    );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openTasks(tester);

    expect(find.text('Waiting to send'), findsOneWidget);
    expect(find.text('Blocked'), findsWidgets);
    expect(
      find.textContaining('1 change is waiting to be sent'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a change the server refused is explained with Try again / Discard',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _tasksApis(env, [taskJson(id: 'a', title: 'Pour slab')]);
      await env.db.enqueue(
        id: 'op1',
        userId: 'u1',
        kind: 'task_status',
        targetId: 'a',
        payload: '{"status":"DONE"}',
      );
      await env.db.markFailed('op1', 'Task not found');
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openTasks(tester);

      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(find.textContaining('could not be saved'), findsNothing);
    },
  );

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final env = TestEnv();
      addTearDown(env.dispose);
      _tasksApis(env, [
        taskJson(
          id: 'a',
          title: 'A very long task title that needs to wrap over several lines on a small screen',
          dueDate: _due(-1),
          checklists: [checklistJson()],
          commentCount: 4,
        ),
      ]);
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
      await _openTasks(tester);
      expect(find.textContaining('A very long task title'), findsOneWidget);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
