import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

void main() {
  testWidgets(
    'a supervisor lands on Today with approvals, who is working and task counts',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);

      expect(find.text('Hello, Tendai'), findsOneWidget);
      // Time
      expect(find.text('TO APPROVE'), findsOneWidget);
      expect(find.text('3'), findsWidgets); // three finished shifts
      expect(find.text('WORKING NOW'), findsOneWidget);
      expect(find.text('Farai Ncube'), findsOneWidget);
      // Tasks: one overdue, one due today, one blocked
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('DUE TODAY'), findsOneWidget);
      expect(find.text('BLOCKED'), findsOneWidget);
      expect(find.text('Fix railing'), findsOneWidget);
      expect(find.text('Pour slab'), findsOneWidget);
      expect(find.text('Order rebar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the Today tab is first and the bar offers the manager screens', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);

    for (final label in [
      'Today',
      'Projects',
      'Approvals',
      'Messages',
      'More',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // Field tabs moved under More for supervisors.
    expect(find.text('Clock'), findsNothing);
    expect(find.text('Materials'), findsNothing);
  });

  testWidgets('tapping To approve opens Approvals', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);

    await tester.tap(find.text('TO APPROVE'));
    await settle(tester);
    expect(find.text('3 shifts to review'), findsOneWidget);
  });

  testWidgets('tapping a task opens its detail', (tester) async {
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

    await tester.tap(find.text('Fix railing'));
    await settle(tester);
    expect(
      find.text('Resume work'),
      findsOneWidget,
    ); // status actions for a blocked task
  });

  testWidgets('quiet day: says nothing needs attention', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(
      env,
      pending: [],
      tasksByStatus: {
        'BLOCKED': [],
        'IN_PROGRESS': [],
        'REVIEW': [],
        'TODO': [],
      },
    );
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    expect(
      find.text('Nothing is overdue, due today or blocked.'),
      findsOneWidget,
    );
    expect(find.text('Nobody clocked in'), findsOneWidget);
  });

  testWidgets('a failing section does not hide the others', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env, tasksFail: true);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);

    expect(find.text('TO APPROVE'), findsOneWidget); // time still shows
    expect(
      find.text('Something went wrong'),
      findsNothing,
    ); // compact error, not a full page
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tells the supervisor when counts are capped', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(
      env,
      tasks: (o) => Reply.json(
        paged(
          [taskJson(id: 'x${o.queryParameters['status']}')],
          limit: 100,
          total: 400,
        ),
      ),
    );
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    expect(
      find.textContaining('Showing the first 100 tasks per status'),
      findsOneWidget,
    );
  });

  testWidgets(
    'sections follow permissions: no timesheet rights, no Time section',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: ['tasks.*', 'projects.view', 'messaging.*'],
        ),
        env: env,
      );
      await settle(tester);

      expect(find.text('TIME'), findsNothing);
      expect(find.text('TO APPROVE'), findsNothing);
      expect(find.text('OVERDUE'), findsOneWidget);
      // And no request was made for other people's time.
      expect(
        env.adapter.requests.where((r) => r.path == 'time-tracking'),
        isEmpty,
      );
    },
  );

  testWidgets("shows the supervisor's own clock and links to it", (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env, ownClockActive: true);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);

    final card = find.textContaining('Clocked in on Harare Tower');
    // The card sits below the task lists; the page is a lazy list.
    await tester.scrollUntilVisible(
      card,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(card);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(card);
    await settle(tester);
    expect(find.text('Clock out'), findsOneWidget);
  });

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env, ownClockActive: true);
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
      expect(find.text('Hello, Tendai'), findsOneWidget);
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
