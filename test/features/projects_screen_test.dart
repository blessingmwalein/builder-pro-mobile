import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

Future<void> _openProjects(WidgetTester tester) async {
  await tester.tap(find.text('Projects').last);
  await settle(tester);
}

void main() {
  testWidgets('lists projects with status, client, progress and counts', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openProjects(tester);

    expect(find.text('Harare Tower'), findsOneWidget);
    expect(find.text('Borrowdale Villas'), findsOneWidget);
    expect(find.text('Active'), findsWidgets); // badge + filter chip
    expect(find.text('On Hold'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('12 tasks'), findsWidgets);
    expect(find.text('HT-01 · Zim Properties'), findsOneWidget);
  });

  testWidgets('no money appears anywhere on the list', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openProjects(tester);
    expect(find.textContaining('2500000'), findsNothing);
    expect(find.textContaining('2,500,000'), findsNothing);
    expect(find.textContaining('812000'), findsNothing);
  });

  testWidgets('status chip filters through the server', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openProjects(tester);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'On hold'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'On hold'));
    await settle(tester);

    expect(env.adapter.last('GET', 'projects').query['status'], 'ON_HOLD');
  });

  testWidgets('search waits for a pause, then queries by text', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openProjects(tester);
    final before = env.adapter.count('GET', 'projects');

    await tester.enterText(find.byType(TextField).first, 'bor');
    await tester.pump(const Duration(milliseconds: 100));
    expect(env.adapter.count('GET', 'projects'), before);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(env.adapter.last('GET', 'projects').query['search'], 'bor');
  });

  testWidgets('empty and error states', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env, projects: []);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openProjects(tester);
    expect(find.text('No projects yet'), findsOneWidget);
  });

  testWidgets('a failed load shows an error with Retry, not "no projects"', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    env.adapter
      ..on('GET', 'time-tracking/active', (_) => Reply.empty())
      ..on(
        'GET',
        'time-tracking/weekly-summary',
        (_) => Reply.json({'entries': []}),
      )
      ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
      ..on('GET', 'tasks', (_) => Reply.json(paged([])))
      ..on(
        'GET',
        'projects',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openProjects(tester);

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No projects yet'), findsNothing);
  });

  group('detail', () {
    Future<void> openDetail(WidgetTester tester) async {
      await tester.tap(find.text('Harare Tower'));
      await settle(tester);
    }

    testWidgets('shows progress, key facts, team and tasks by status', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openProjects(tester);
      await openDetail(tester);

      expect(find.text('Harare Tower'), findsWidgets);
      expect(find.text('12 Samora Machel Ave'), findsOneWidget);
      expect(find.text('Zim Properties'), findsOneWidget);
      expect(find.text('Chipo Dube'), findsOneWidget);
      expect(find.text('TEAM 2'), findsOneWidget);
      expect(find.text('Rudo Banda'), findsOneWidget);
      expect(find.text('Foreman'), findsOneWidget);
      expect(find.text('Ten storey office block'), findsOneWidget);
      // Money is never shown.
      expect(find.textContaining('2500000'), findsNothing);
      expect(find.textContaining('812000'), findsNothing);

      final tasks = find.text('Fix railing');
      await tester.scrollUntilVisible(
        tasks,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('BLOCKED 1'), findsOneWidget);
      expect(find.text('Fix railing'), findsOneWidget);
      // Done tasks stay out of the way until asked for.
      expect(find.text('Set out site'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Show 1 done'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Show 1 done'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Show 1 done'));
      await settle(tester);
      expect(find.text('Set out site'), findsOneWidget);
    });

    testWidgets('a project task opens the task detail', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      env.adapter
        ..on(
          'GET',
          'tasks/tb',
          (_) => Reply.json(
            taskJson(id: 'tb', title: 'Fix railing', status: 'BLOCKED'),
          ),
        )
        ..on('GET', 'tasks/tb/attachments', (_) => Reply.json([]));
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openProjects(tester);
      await openDetail(tester);

      final task = find.text('Fix railing');
      await tester.scrollUntilVisible(
        task,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(task);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(task);
      await settle(tester);
      expect(find.text('Resume work'), findsOneWidget);
    });

    testWidgets(
      'without task permissions the tasks section is absent and not requested',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        supervisorApis(env);
        await pumpApp(
          tester,
          // Can supervise via projects.* but holds no tasks permission.
          session: supervisorSession(perms: ['projects.*', 'messaging.*']),
          env: env,
        );
        await settle(tester);
        await _openProjects(tester);
        await openDetail(tester);

        expect(find.textContaining('TASKS'), findsNothing);
        expect(
          env.adapter.requests.where(
            (r) => r.path == 'tasks' && r.query['projectId'] != null,
          ),
          isEmpty,
        );
      },
    );

    testWidgets('a missing project shows a clear message', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      env.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'GET',
          'time-tracking/weekly-summary',
          (_) => Reply.json({'entries': []}),
        )
        ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
        ..on('GET', 'tasks', (_) => Reply.json(paged([])))
        ..on('GET', 'projects', (_) => Reply.json(paged([projectJson()])))
        ..on(
          'GET',
          'projects/p1',
          (_) => Reply.json({
            'statusCode': 404,
            'message': 'Project not found',
          }, status: 404),
        );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openProjects(tester);
      await openDetail(tester);
      expect(find.text('Project not found'), findsOneWidget);
    });

    testWidgets('large text on a small phone renders without overflow', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      final capture = ErrorCapture();
      await pumpApp(
        tester,
        session: supervisorSession(),
        env: env,
        size: const Size(320, 640),
        textScale: 2.0,
      );
      await settle(tester);
      await _openProjects(tester);
      await openDetail(tester);
      await tester.scrollUntilVisible(
        find.text('Fix railing'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(capture.stop(), isEmpty);
    });
  });
}
