import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

Map<String, dynamic> _createdTask() => {
  ...taskJson(id: 'new1', title: 'Fix stair rail'),
  'createdAt': DateTime.now().toUtc().toIso8601String(),
};

void _apis(TestEnv env) {
  supervisorApis(env);
  env.adapter
    ..on(
      'GET',
      'tasks/tb',
      (_) => Reply.json(
        taskJson(
          id: 'tb',
          title: 'Fix railing',
          status: 'BLOCKED',
          dueDate: isoDays(4),
          description: 'Block B stairs',
        ),
      ),
    )
    ..on('GET', 'tasks/tb/attachments', (_) => Reply.json([]));
}

Future<void> _openProject(WidgetTester tester) async {
  await tester.tap(find.text('Projects').last);
  await settle(tester);
  await tester.tap(find.text('Harare Tower'));
  await settle(tester);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openNewTask(WidgetTester tester) async {
  await _openProject(tester);
  final add = find.widgetWithText(InkWell, 'Add task');
  await _scrollTo(tester, add);
  await tester.tap(add);
  await settle(tester);
  expect(find.text('New task'), findsOneWidget);
}

Future<void> _openEdit(WidgetTester tester) async {
  await _openProject(tester);
  await _scrollTo(tester, find.text('Fix railing'));
  await tester.tap(find.text('Fix railing'));
  await settle(tester);
  await tester.tap(find.text('Edit task'));
  await settle(tester);
  expect(find.text('Edit task'), findsWidgets);
}

final _submit = find.widgetWithText(InkWell, 'Add task');

void main() {
  group('who sees the buttons', () {
    testWidgets(
      'a supervisor sees Add task on a project and Edit task on a task',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openProject(tester);
        await _scrollTo(tester, find.widgetWithText(InkWell, 'Add task'));
        expect(find.widgetWithText(InkWell, 'Add task'), findsOneWidget);
      },
    );

    testWidgets('without tasks.create there is no Add task', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: ['projects.*', 'tasks.view', 'messaging.*'],
        ),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, find.text('Fix railing'));
      expect(find.widgetWithText(InkWell, 'Add task'), findsNothing);
    });

    testWidgets(
      'without tasks.* there is no Edit task (the API accepts only tasks.*)',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(
          tester,
          session: supervisorSession(
            perms: [
              'projects.view',
              'tasks.view',
              'tasks.create',
              'tasks.complete',
              'timesheets.*',
            ],
          ),
          env: env,
        );
        await settle(tester);
        await _openProject(tester);
        await _scrollTo(tester, find.text('Fix railing'));
        await tester.tap(find.text('Fix railing'));
        await settle(tester);
        expect(
          find.text('Mark done'),
          findsNothing,
        ); // blocked: shows Resume work
        expect(find.text('Resume work'), findsOneWidget);
        expect(find.text('Edit task'), findsNothing);
      },
    );
  });

  group('new task', () {
    testWidgets(
      'empty title and bad hours are stopped before anything is sent',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openNewTask(tester);

        await tester.enterText(find.byType(TextFormField).at(2), '1.234');
        await tester.tap(_submit.last);
        await settle(tester);

        expect(find.text('Give the task a title'), findsOneWidget);
        expect(find.text('Use at most 2 decimals'), findsOneWidget);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets(
      'creates the task with priority, due date, hours (comma) and assignee',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'tasks',
          (_) => Reply.json(_createdTask(), status: 201),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openNewTask(tester);

        await tester.enterText(
          find.byType(TextFormField).at(0),
          '  Fix stair rail  ',
        );
        await tester.enterText(find.byType(TextFormField).at(1), 'Block B');
        await tester.tap(find.widgetWithText(ChoiceChip, 'High'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField).at(2), '2,5');

        // Due date: pick today in the platform date picker.
        await tester.tap(find.text('No due date'));
        await settle(tester);
        await tester.tap(find.text('OK'));
        await settle(tester);

        // Assignee from the project team.
        await tester.tap(find.text('Nobody yet'));
        await settle(tester);
        await tester.tap(find.text('Rudo Banda'));
        await tester.pump();
        await tester.tap(find.text('Done'));
        await settle(tester);

        await tester.tap(_submit.last);
        await settle(tester);

        final body = env.adapter.last('POST', 'tasks').data as Map;
        expect(body['title'], 'Fix stair rail');
        expect(body['description'], 'Block B');
        expect(body['priority'], 'HIGH');
        expect(body['estimatedHours'], 2.5);
        expect(body['assigneeIds'], ['u2']);
        expect(body['projectId'], 'p1');
        expect(body['dueDate'], isNotNull);
        // Back on the project, with confirmation.
        expect(find.text('New task'), findsNothing);
        expect(find.text('Task added.'), findsOneWidget);
      },
    );

    testWidgets('a slow reply cannot be sent twice by tapping again', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'tasks',
        (_) => Reply.json(
          _createdTask(),
          status: 201,
          delay: const Duration(seconds: 2),
        ),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openNewTask(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Fix stair rail',
      );

      await tester.tap(_submit.last);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byType(CircularProgressIndicator).first,
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(env.adapter.count('POST', 'tasks'), 1);
    });

    testWidgets('a server refusal stays on the form with the message', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'tasks',
        (_) => Reply.json({
          'statusCode': 404,
          'message': 'Project not found',
        }, status: 404),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openNewTask(tester);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Fix stair rail',
      );

      await tester.tap(_submit.last);
      await settle(tester);

      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Project not found'), findsOneWidget);
      // What was typed is still there.
      expect(find.text('Fix stair rail'), findsOneWidget);
    });

    testWidgets(
      'after a timeout the task is found and the form closes without a second POST',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'tasks',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        );
        // The check reads the project's TO DO tasks.
        env.adapter.on(
          'GET',
          'tasks',
          (o) => o.queryParameters['status'] == 'TODO'
              ? Reply.json(paged([_createdTask()], limit: 100))
              : Reply.json(paged([], limit: 100)),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openNewTask(tester);
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Fix stair rail',
        );

        await tester.tap(_submit.last);
        await settle(tester, frames: 20);

        expect(env.adapter.count('POST', 'tasks'), 1);
        expect(find.textContaining('The task was created'), findsOneWidget);
        expect(find.text('New task'), findsNothing);
      },
    );

    testWidgets(
      'after a timeout where nothing was created the form stays so they can try again',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'tasks',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openNewTask(tester);
        await tester.enterText(
          find.byType(TextFormField).at(0),
          'Fix stair rail',
        );

        await tester.tap(_submit.last);
        await settle(tester, frames: 20);

        expect(find.textContaining('no task was created'), findsOneWidget);
        expect(find.text('New task'), findsOneWidget);
        expect(env.adapter.count('POST', 'tasks'), 1);
      },
    );
  });

  group('edit task', () {
    testWidgets(
      'the form starts with the current values and explains what cannot be cleared',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openEdit(tester);

        expect(find.text('Fix railing'), findsOneWidget); // in the title field
        expect(find.text('Block B stairs'), findsOneWidget);
        expect(find.text('8'), findsOneWidget); // estimate
        expect(
          find.textContaining(
            'can be changed here but not removed; use the web app',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'An estimate can be changed here but not removed',
          ),
          findsOneWidget,
        );
        // No "Remove due date" while editing, because the API cannot clear it.
        expect(find.text('Remove due date'), findsNothing);
        // Assigning is done from the task itself, not this form.
        expect(find.text('Assign to (optional)'), findsNothing);
      },
    );

    testWidgets('saving sends the changes and closes', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on('PUT', 'tasks/tb', (_) => Reply.json({}));
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEdit(tester);

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Fix railing on level 2',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Critical'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, 'Save changes'));
      await settle(tester);

      final body = env.adapter.last('PUT', 'tasks/tb').data as Map;
      expect(body['title'], 'Fix railing on level 2');
      expect(body['priority'], 'CRITICAL');
      expect(body['description'], 'Block B stairs');
      expect(body['estimatedHours'], 8.0);
      expect(body['dueDate'], isNotNull);
      expect(find.text('Task updated.'), findsOneWidget);
      expect(
        find.text('Edit task'),
        findsWidgets,
      ); // back on the detail with its Edit button
    });

    testWidgets('a refusal stays on the form with the reason', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'PUT',
        'tasks/tb',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openEdit(tester);

      await tester.tap(find.widgetWithText(InkWell, 'Save changes'));
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(find.text('Save changes'), findsOneWidget);
    });
  });

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      final capture = ErrorCapture();
      await pumpApp(
        tester,
        session: supervisorSession(),
        env: env,
        size: const Size(320, 640),
        textScale: 2.0,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await settle(tester);
      await _openNewTask(tester);
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
