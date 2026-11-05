import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/features/finance/data/finance_models.dart';
import 'package:builder_pro_mobile/shared/components/layout.dart' show AppCard;
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

SessionState _as(List<String> perms) =>
    SessionState.authenticated(testMe(permissions: perms, role: 'Owner'));

/// A supervisor who can also see finance, one key at a time.
const _supervisorPlusInvoices = [...supervisorPerms, 'invoices.view'];
const _supervisorPlusFinancials = [...supervisorPerms, 'financials.view'];

void _apis(
  TestEnv env, {
  bool dashboardFails = false,
  bool agingFails = false,
  bool nothingOverdue = false,
  List<Map<String, dynamic>>? alerts,
}) {
  supervisorApis(env);
  env.adapter
    ..on(
      'GET',
      'financials/dashboard',
      (_) => dashboardFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(dashboardJson(alerts: alerts)),
    )
    ..on(
      'GET',
      'invoices/aging-report',
      (_) => agingFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              nothingOverdue ? agingJson(d30: 0, over: 0) : agingJson(),
            ),
    )
    ..on('GET', 'financials/summary', (_) => Reply.json(financeSummaryJson()));
}

Map<String, dynamic> _alert(String id, String name, int percent) => {
  'project': {'id': id, 'name': name},
  'percentUsed': percent,
};

void main() {
  group('the dashboard model', () {
    test(
      'reads the active projects and one alert per project, worst first',
      () {
        final d = CompanyDashboard.parse(dashboardJson());
        expect(d.activeProjects, 7);
        expect(d.alerts.map((a) => a.projectName), [
          'Borrowdale Villas',
          'Harare Tower',
        ]);
        // Harare Tower has two budget lines (92 and 81): its highest counts.
        expect(d.alerts.last.percentUsed, 92);
      },
    );

    test('over budget means above 100, not at 100', () {
      final d = CompanyDashboard.parse(
        dashboardJson(
          alerts: [
            _alert('a', 'Exactly', 100),
            _alert('b', 'Over', 101),
            _alert('c', 'Under', 99),
          ],
        ),
      );
      final byName = {for (final a in d.alerts) a.projectName: a};
      expect(byName['Exactly']!.isOver, isFalse);
      expect(byName['Over']!.isOver, isTrue);
      expect(byName['Under']!.isOver, isFalse);
    });

    test('rows without a project or a percentage are skipped', () {
      final d = CompanyDashboard.parse({
        'activeProjects': '3',
        'budgetAlerts': [
          {'percentUsed': 90},
          {
            'project': {'id': 'p1'},
          },
          {
            'project': {'id': 'p2', 'name': 'Ok'},
            'percentUsed': 95,
          },
        ],
      });
      expect(d.activeProjects, 3);
      expect(d.alerts.map((a) => a.projectName), ['Ok']);
    });

    test('a malformed reply is an empty dashboard, not a crash', () {
      for (final raw in [null, 'nope', <String, dynamic>{}, []]) {
        final d = CompanyDashboard.parse(raw);
        expect(d.activeProjects, 0);
        expect(d.alerts, isEmpty);
      }
    });
  });

  group('on Today', () {
    testWidgets('shows active projects, what is owed and the budget alerts', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(ownerPerms), env: env);
      await settle(tester);

      expect(find.text('COMPANY'), findsOneWidget);
      expect(find.text('ACTIVE PROJECTS'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('OWED TO YOU'), findsOneWidget);
      expect(find.text(r'$2,000.00'), findsOneWidget);
      expect(find.text(r'$1,500.00 overdue'), findsOneWidget);
      expect(find.text('BUDGET ALERTS 2'), findsOneWidget);
      expect(find.text('Borrowdale Villas'), findsOneWidget);
      expect(find.text('Over budget · 112%'), findsOneWidget);
      // (a task on the page can name the same project)
      expect(find.text('Harare Tower'), findsWidgets);
      expect(find.text('92% used'), findsOneWidget);
      expect(find.text('81% used'), findsNothing);
    });

    testWidgets('never shows the revenue figures the API adds up wrongly', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(ownerPerms), env: env);
      await settle(tester);

      for (final wrong in [
        '987,654',
        '555,555',
        '424,242',
        '313,131',
        '212,121',
      ]) {
        expect(find.textContaining(wrong), findsNothing, reason: wrong);
      }
    });

    testWidgets('nothing overdue says so', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, nothingOverdue: true);
      await pumpApp(tester, session: _as(ownerPerms), env: env);
      await settle(tester);
      expect(find.text(r'$500.00'), findsOneWidget);
      expect(find.text('Nothing overdue'), findsOneWidget);
      expect(
        find.textContaining('overdue', findRichText: false),
        findsOneWidget,
      );
    });

    testWidgets(
      'a role with no Projects screen sees the figure but cannot open it',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(
          tester,
          session: supervisorSession(
            perms: [
              'tasks.*',
              'timesheets.*',
              'financials.view',
              'invoices.view',
            ],
          ),
          env: env,
        );
        await settle(tester);

        expect(find.text('ACTIVE PROJECTS'), findsOneWidget);
        expect(find.text('Tap to see them'), findsNothing);
        await tester.tap(find.text('ACTIVE PROJECTS'));
        await settle(tester);
        // still on Today: this role has no Projects screen to go to
        expect(find.text('COMPANY'), findsOneWidget);
      },
    );

    testWidgets('nothing at an alert level says so', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, alerts: const []);
      await pumpApp(tester, session: _as(ownerPerms), env: env);
      await settle(tester);
      expect(
        find.text('No project budget is at its alert level.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'only the three worst alerts are listed, with a count of the rest',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(
          env,
          alerts: [
            _alert('a', 'Alpha', 95),
            _alert('b', 'Bravo', 96),
            _alert('c', 'Charlie', 97),
            _alert('d', 'Delta', 98),
            _alert('e', 'Echo', 99),
          ],
        );
        await pumpApp(tester, session: _as(ownerPerms), env: env);
        await settle(tester);

        expect(find.text('BUDGET ALERTS 5'), findsOneWidget);
        expect(find.text('Echo'), findsOneWidget);
        expect(find.text('Delta'), findsOneWidget);
        expect(find.text('Charlie'), findsOneWidget);
        expect(find.text('Bravo'), findsNothing);
        expect(find.text('+ 2 more'), findsOneWidget);
      },
    );

    testWidgets('a supervisor without finance keys sees no company section', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);

      expect(find.text('COMPANY'), findsNothing);
      expect(env.adapter.count('GET', 'financials/dashboard'), 0);
      expect(env.adapter.count('GET', 'invoices/aging-report'), 0);
    });

    testWidgets(
      'with only invoices.view: what is owed, and nothing from the dashboard',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(
          tester,
          session: supervisorSession(perms: _supervisorPlusInvoices),
          env: env,
        );
        await settle(tester);

        expect(find.text('OWED TO YOU'), findsOneWidget);
        expect(find.text('ACTIVE PROJECTS'), findsNothing);
        expect(find.textContaining('BUDGET ALERTS'), findsNothing);
        expect(env.adapter.count('GET', 'financials/dashboard'), 0);
      },
    );

    testWidgets(
      'with only financials.view: projects and alerts, and nothing owed',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(
          tester,
          session: supervisorSession(perms: _supervisorPlusFinancials),
          env: env,
        );
        await settle(tester);

        expect(find.text('ACTIVE PROJECTS'), findsOneWidget);
        expect(find.text('BUDGET ALERTS 2'), findsOneWidget);
        expect(find.text('OWED TO YOU'), findsNothing);
        expect(env.adapter.count('GET', 'invoices/aging-report'), 0);
      },
    );

    testWidgets(
      'a dashboard that cannot load says so, offers a retry, and leaves what is owed alone',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, dashboardFails: true);
        await pumpApp(tester, session: _as(ownerPerms), env: env);
        await settle(tester);

        expect(find.text('Could not load. Tap to retry'), findsOneWidget);
        expect(find.text(r'$2,000.00'), findsOneWidget);
        final before = env.adapter.count('GET', 'financials/dashboard');

        await tester.tap(find.text('Could not load. Tap to retry'));
        await settle(tester);

        expect(env.adapter.count('GET', 'financials/dashboard'), before + 1);
      },
    );

    testWidgets(
      'an aging report that cannot load does not hide the dashboard',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, agingFails: true);
        await pumpApp(tester, session: _as(ownerPerms), env: env);
        await settle(tester);

        expect(find.text('Could not load. Tap to retry'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
        expect(find.text('BUDGET ALERTS 2'), findsOneWidget);
      },
    );

    testWidgets(
      'the projects tile opens Projects and the owed tile opens Finance',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: _as(ownerPerms), env: env);
        await settle(tester);

        await tester.tap(find.text('ACTIVE PROJECTS'));
        await settle(tester);
        expect(find.text('HT-01 · Zim Properties'), findsOneWidget);
      },
    );

    testWidgets('the owed tile opens Finance', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(ownerPerms), env: env);
      await settle(tester);

      await tester.tap(find.text('OWED TO YOU'));
      await settle(tester);
      expect(find.text('MOST OVERDUE'), findsOneWidget);
    });

    testWidgets('a project in the alerts opens its page', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(ownerPerms), env: env);
      await settle(tester);

      final card = find.ancestor(
        of: find.text('BUDGET ALERTS 2'),
        matching: find.byType(AppCard),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.text('Harare Tower')),
      );
      await settle(tester);
      expect(find.textContaining('TEAM'), findsOneWidget);
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
      List<String> errors;
      try {
        await pumpApp(
          tester,
          session: _as(ownerPerms),
          env: env,
          size: const Size(320, 640),
          textScale: 2.0,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await settle(tester);
        expect(find.text('COMPANY'), findsOneWidget);
        await unmount(tester);
      } finally {
        errors = capture.stop();
      }
      expect(errors, isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
