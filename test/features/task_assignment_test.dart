import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/core/permissions/feature_permissions.dart';
import 'package:builder_pro_mobile/core/permissions/permission_evaluator.dart';
import 'package:builder_pro_mobile/features/tasks/application/tasks_providers.dart';
import 'package:builder_pro_mobile/features/tasks/data/task_models.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

const _rudo = TaskAssignee(id: 'u2', name: 'Rudo Banda');

void _taskApis(TestEnv env) {
  env.adapter
    ..on(
      'GET',
      'tasks/a',
      (_) => Reply.json(taskJson(id: 'a', title: 'Pour slab', status: 'TODO')),
    )
    ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]));
}

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('logic', () {
    bool canAssign(List<String> p) =>
        PermissionEvaluator(p).satisfies(Feature.assignTasks);

    test('assigning needs the assign right AND access to the project team', () {
      expect(canAssign(['tasks.assign']), isFalse); // no team to choose from
      expect(canAssign(['projects.view']), isFalse); // cannot assign
      expect(canAssign(['tasks.assign', 'projects.view']), isTrue);
      expect(canAssign(['tasks.*', 'projects.view']), isTrue);
      expect(canAssign(['tasks.*', 'projects.*']), isTrue);
      expect(canAssign(workerPerms), isFalse);
    });

    test('assignees keep their ids when parsed', () {
      final t = TaskItem.tryParse(taskJson())!;
      expect(t.assignees.single.id, 'u1');
      expect(t.assigneeNames, ['Tendai Moyo']);
    });

    test(
      'adding calls POST /tasks/:id/assignees/:userId and shows at once',
      () async {
        _taskApis(env);
        env.adapter.on(
          'POST',
          'tasks/a/assignees/u2',
          (_) => Reply.json({}, status: 201),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(taskDetailProvider('a'), (_, _) {});
        await c.read(taskDetailProvider('a').future);

        final pending = c
            .read(taskDetailProvider('a').notifier)
            .setAssigned(_rudo, assigned: true);
        expect(
          c
              .read(taskDetailProvider('a'))
              .value!
              .task
              .assignees
              .map((a) => a.id),
          ['u1', 'u2'],
        );
        await pending;

        expect(env.adapter.count('POST', 'tasks/a/assignees/u2'), 1);
      },
    );

    test('removing calls DELETE', () async {
      _taskApis(env);
      env.adapter.on(
        'DELETE',
        'tasks/a/assignees/u1',
        (_) => Reply.json({'success': true}),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(taskDetailProvider('a'), (_, _) {});
      await c.read(taskDetailProvider('a').future);

      await c
          .read(taskDetailProvider('a').notifier)
          .setAssigned(
            const TaskAssignee(id: 'u1', name: 'Tendai Moyo'),
            assigned: false,
          );

      expect(env.adapter.count('DELETE', 'tasks/a/assignees/u1'), 1);
      expect(c.read(taskDetailProvider('a')).value!.task.assignees, isEmpty);
    });

    test('a refusal undoes the change and surfaces the error', () async {
      _taskApis(env);
      env.adapter.on(
        'POST',
        'tasks/a/assignees/u2',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(taskDetailProvider('a'), (_, _) {});
      await c.read(taskDetailProvider('a').future);

      await expectLater(
        c
            .read(taskDetailProvider('a').notifier)
            .setAssigned(_rudo, assigned: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(
        c.read(taskDetailProvider('a')).value!.task.assignees.map((a) => a.id),
        ['u1'],
      );
    });

    test(
      'no connection undoes the change (assignment is never queued)',
      () async {
        _taskApis(env);
        env.adapter.on(
          'POST',
          'tasks/a/assignees/u2',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(taskDetailProvider('a'), (_, _) {});
        await c.read(taskDetailProvider('a').future);

        await expectLater(
          c
              .read(taskDetailProvider('a').notifier)
              .setAssigned(_rudo, assigned: true),
          throwsA(isA<AppException>()),
        );
        expect(
          c.read(taskDetailProvider('a')).value!.task.assignees,
          hasLength(1),
        );
        expect(await env.db.outboxFor('u1'), isEmpty);
      },
    );

    test(
      'a timed-out assignment is sent once more (it only sets membership)',
      () async {
        _taskApis(env);
        env.adapter
          ..on(
            'POST',
            'tasks/a/assignees/u2',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'POST',
            'tasks/a/assignees/u2',
            (_) => Reply.json({}, status: 201),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(taskDetailProvider('a'), (_, _) {});
        await c.read(taskDetailProvider('a').future);

        await c
            .read(taskDetailProvider('a').notifier)
            .setAssigned(_rudo, assigned: true);

        expect(env.adapter.count('POST', 'tasks/a/assignees/u2'), 2);
        expect(
          c.read(taskDetailProvider('a')).value!.task.assignees,
          hasLength(2),
        );
      },
    );

    test(
      'if the retry also times out it is undone, with no third attempt',
      () async {
        _taskApis(env);
        env.adapter.on(
          'POST',
          'tasks/a/assignees/u2',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(taskDetailProvider('a'), (_, _) {});
        await c.read(taskDetailProvider('a').future);

        await expectLater(
          c
              .read(taskDetailProvider('a').notifier)
              .setAssigned(_rudo, assigned: true),
          throwsA(isA<AppException>()),
        );
        expect(env.adapter.count('POST', 'tasks/a/assignees/u2'), 2);
        expect(
          c.read(taskDetailProvider('a')).value!.task.assignees,
          hasLength(1),
        );
      },
    );

    test('asking for what is already true sends nothing', () async {
      _taskApis(env);
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(taskDetailProvider('a'), (_, _) {});
      await c.read(taskDetailProvider('a').future);

      await c
          .read(taskDetailProvider('a').notifier)
          .setAssigned(
            const TaskAssignee(id: 'u1', name: 'Tendai Moyo'),
            assigned: true,
          );
      expect(
        env.adapter.requests.where((r) => r.path.contains('assignees')),
        isEmpty,
      );
    });

    test('add then an immediate remove of the same person is ignored while the first is in flight', () async {
      _taskApis(env);
      env.adapter
        ..on(
          'POST',
          'tasks/a/assignees/u2',
          (_) => Reply.json(
            {},
            status: 201,
            delay: const Duration(milliseconds: 100),
          ),
        )
        ..on(
          'DELETE',
          'tasks/a/assignees/u2',
          (_) => Reply.json({'success': true}),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(taskDetailProvider('a'), (_, _) {});
      await c.read(taskDetailProvider('a').future);
      final n = c.read(taskDetailProvider('a').notifier);

      await Future.wait([
        n.setAssigned(_rudo, assigned: true),
        n.setAssigned(_rudo, assigned: false),
      ]);

      // No racing DELETE: the second tap waits for the first to finish.
      expect(env.adapter.count('POST', 'tasks/a/assignees/u2'), 1);
      expect(env.adapter.count('DELETE', 'tasks/a/assignees/u2'), 0);
      expect(
        c.read(taskDetailProvider('a')).value!.task.assignees.map((a) => a.id),
        ['u1', 'u2'],
      );
    });

    test('two quick taps on the same person send one request', () async {
      _taskApis(env);
      env.adapter.on(
        'POST',
        'tasks/a/assignees/u2',
        (_) => Reply.json(
          {},
          status: 201,
          delay: const Duration(milliseconds: 100),
        ),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(taskDetailProvider('a'), (_, _) {});
      await c.read(taskDetailProvider('a').future);
      final n = c.read(taskDetailProvider('a').notifier);

      await Future.wait([
        n.setAssigned(_rudo, assigned: true),
        n.setAssigned(_rudo, assigned: true),
      ]);

      expect(env.adapter.count('POST', 'tasks/a/assignees/u2'), 1);
    });
  });

  group('screen', () {
    void apis(TestEnv e) {
      supervisorApis(e);
      e.adapter
        ..on(
          'GET',
          'tasks/tb',
          (_) => Reply.json(
            taskJson(id: 'tb', title: 'Fix railing', status: 'BLOCKED'),
          ),
        )
        ..on('GET', 'tasks/tb/attachments', (_) => Reply.json([]));
    }

    Future<void> openTask(WidgetTester tester) async {
      await tester.tap(find.text('Fix railing'));
      await settle(tester);
    }

    testWidgets(
      'a supervisor can change who is assigned, from the project team',
      (tester) async {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(e);
        e.adapter.on(
          'POST',
          'tasks/tb/assignees/u2',
          (_) => Reply.json({}, status: 201),
        );
        await pumpApp(tester, session: supervisorSession(), env: e);
        await settle(tester);
        await openTask(tester);

        expect(find.text('Assigned to'), findsOneWidget);
        await tester.tap(find.text('Change who is assigned'));
        await settle(tester);
        expect(find.text('Who is working on this?'), findsOneWidget);
        expect(find.text('Rudo Banda'), findsOneWidget);
        expect(find.text('Farai Ncube'), findsOneWidget);
        // Tendai is on the task but not on the project team: still listed so he can be removed.
        expect(find.text('Tendai Moyo'), findsWidgets);

        await tester.tap(find.text('Rudo Banda'));
        await settle(tester);
        expect(e.adapter.count('POST', 'tasks/tb/assignees/u2'), 1);

        await tester.tap(find.text('Done'));
        await settle(tester);
        expect(find.textContaining('Tendai Moyo, Rudo Banda'), findsOneWidget);
      },
    );

    testWidgets('a refused change is undone in the sheet and explained', (
      tester,
    ) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e);
      e.adapter.on(
        'POST',
        'tasks/tb/assignees/u2',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: supervisorSession(), env: e);
      await settle(tester);
      await openTask(tester);
      await tester.tap(find.text('Change who is assigned'));
      await settle(tester);

      await tester.tap(find.text('Rudo Banda'));
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(
        find.byIcon(Icons.check_box_rounded),
        findsOneWidget,
      ); // only the original assignee
    });

    testWidgets('a worker (no assign right) does not see the button', (
      tester,
    ) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      e.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'GET',
          'time-tracking/weekly-summary',
          (_) => Reply.json({'entries': []}),
        )
        ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
        ..on(
          'GET',
          'tasks/my-queue',
          (_) => Reply.json([taskJson(id: 'a', title: 'Pour slab')]),
        )
        ..on(
          'GET',
          'tasks/a',
          (_) => Reply.json(taskJson(id: 'a', title: 'Pour slab')),
        )
        ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]));
      await pumpApp(
        tester,
        session: supervisorSession(perms: workerPerms),
        env: e,
      );
      await settle(tester);
      await tester.tap(find.text('My Tasks').last);
      await settle(tester);
      await tester.tap(find.text('Pour slab'));
      await settle(tester);

      expect(find.text('Change who is assigned'), findsNothing);
      expect(
        find.text('Assigned to'),
        findsOneWidget,
      ); // still visible, read-only
    });
  });
}
