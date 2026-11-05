import 'package:builder_pro_mobile/app/shell/app_shell.dart';
import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:flutter/material.dart' show Scrollable;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

void main() {
  group('selectedBarIndex', () {
    // Bar: Today(4) Projects(5) Approvals(6) Messages(3) More(7)
    const bar = [4, 5, 6, 3, 7];

    test('lights the tab for the current branch', () {
      expect(selectedBarIndex(bar, 5), 1);
      expect(selectedBarIndex(bar, 3), 3);
    });

    test('lights More for a destination that is not in the bar', () {
      expect(selectedBarIndex(bar, 0), 4); // Clock, opened from More
      expect(selectedBarIndex(bar, 2), 4); // Materials
    });

    test('More itself is More', () {
      expect(selectedBarIndex(bar, 7), 4);
    });
  });

  testWidgets('a supervisor reaches Clock, My Tasks and Materials from More', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    env.adapter.on('GET', 'tasks/my-queue', (_) => Reply.json([]));
    env.adapter.on(
      'GET',
      'materials',
      (_) => Reply.json({
        'items': [],
        'meta': {'page': 1, 'limit': 20, 'total': 0},
      }),
    );
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);

    await tester.tap(find.text('More').last);
    await settle(tester);
    expect(find.text('Also in the app'), findsOneWidget);
    for (final label in ['My Tasks', 'Clock', 'Materials']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text('Materials'));
    await settle(tester);
    expect(find.text('Find an item to log what you used.'), findsOneWidget);
  });

  testWidgets('a supervisor does not see Projects listed as "on the web app"', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await tester.tap(find.text('More').last);
    await settle(tester);

    // The More list is lazy: scroll until the item is built.
    await tester.scrollUntilVisible(
      find.text('Documents'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Projects is in the app for them, so it is not in the web-only list...
    expect(
      find.text('Projects'),
      findsOneWidget,
    ); // ...only the bar item remains.
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets(
    'a worker (projects.view, no Projects tab) is pointed to the web app for it',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await tester.tap(find.text('More').last);
      await settle(tester);

      expect(find.text('On the web app for now'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget); // listed as web-only
    },
  );
}
