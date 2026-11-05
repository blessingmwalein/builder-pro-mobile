import 'package:builder_pro_mobile/shared/components/app_button.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

/// Can see projects and stages, but not change them.
const _viewer = ['projects.view', 'tasks.*', 'timesheets.*', 'messaging.*'];

/// Can start, complete and skip stages (`projects.update`), but not approve.
const _updater = [..._viewer, 'projects.update'];

/// Holds `projects.*`: everything above, and approving.
const _approver = ['projects.*', 'tasks.*', 'timesheets.*', 'messaging.*'];

List<Map<String, dynamic>> _stages() => [
  stageJson(
    status: 'COMPLETED',
    requiresApproval: true,
    actualStart: DateTime.utc(2026, 10, 2),
    actualEnd: DateTime.utc(2026, 10, 21),
    approvedBy: 'Chipo Dube',
    approvedAt: DateTime.utc(2026, 10, 21, 8),
  ),
  stageJson(
    id: 's2',
    name: 'Design sign-off',
    order: 2,
    status: 'IN_PROGRESS',
    requiresApproval: true,
    plannedStart: DateTime.utc(2026, 10, 22),
    plannedEnd: DateTime.utc(2026, 11, 5),
  ),
  stageJson(
    id: 's3',
    code: 'EXECUTION',
    name: 'Foundations',
    status: 'IN_PROGRESS',
    notes: 'Waiting on the concrete',
  ),
  stageJson(
    id: 's4',
    code: 'EXECUTION',
    name: 'Walls',
    order: 2,
    status: 'PENDING',
  ),
  stageJson(
    id: 's5',
    code: 'EXECUTION',
    name: 'Roof',
    order: 3,
    status: 'BLOCKED',
  ),
];

void _apis(
  TestEnv env, {
  List<Map<String, dynamic>>? stages,
  bool stagesFail = false,
}) {
  supervisorApis(env);
  env.adapter.on(
    'GET',
    'projects/p1/stages',
    (_) => stagesFail
        ? Reply.fail(DioExceptionType.connectionError)
        : Reply.json(stages ?? _stages()),
  );
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

Finder _button(String label) => find.widgetWithText(InkWell, label);

void main() {
  group('reading', () {
    testWidgets(
      'stages are grouped by workflow with status, dates and approval',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(
          tester,
          session: supervisorSession(perms: _viewer),
          env: env,
        );
        await settle(tester);
        await _openProject(tester);

        await _scrollTo(tester, find.text('STAGES 1 of 5 done'));
        expect(find.text('PLANNING · 1 of 2'), findsOneWidget);
        expect(find.text('Site survey'), findsOneWidget);
        expect(
          find.text('Started Fri 2 Oct · finished Wed 21 Oct'),
          findsOneWidget,
        );
        expect(
          find.text('Approved by Chipo Dube · Wed 21 Oct'),
          findsOneWidget,
        );
        expect(find.text('Design sign-off'), findsOneWidget);
        expect(find.text('Planned Thu 22 Oct → Thu 5 Nov'), findsOneWidget);
        expect(find.text('Needs approval to complete'), findsOneWidget);

        await _scrollTo(tester, find.text('Foundations'));
        expect(find.text('EXECUTION · 0 of 3'), findsOneWidget);
        expect(find.text('Waiting on the concrete'), findsOneWidget);
        await _scrollTo(tester, find.text('Roof'));
        // (a task on the page can also be blocked)
        expect(find.text('Blocked'), findsWidgets);
      },
    );

    testWidgets('a role that can only view sees no actions', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(perms: _viewer),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, find.text('Roof'));

      for (final label in ['Start', 'Skip', 'Complete', 'Approve stage']) {
        expect(_button(label), findsNothing, reason: label);
      }
    });

    testWidgets('a project without stages shows no stages section', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, stages: []);
      await pumpApp(
        tester,
        session: supervisorSession(perms: _viewer),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);

      expect(find.textContaining('STAGES'), findsNothing);
      expect(find.textContaining('TEAM'), findsOneWidget);
    });

    testWidgets(
      'stages that cannot be loaded give an error, and the page still works',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, stagesFail: true);
        await pumpApp(
          tester,
          session: supervisorSession(perms: _viewer),
          env: env,
        );
        await settle(tester);
        await _openProject(tester);

        expect(find.textContaining('TEAM'), findsOneWidget);
        await _scrollTo(tester, find.text('Retry'));
        expect(find.text('Retry'), findsOneWidget);
      },
    );
  });

  group('changing stages', () {
    testWidgets('each stage offers only the moves that fit its status', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(perms: _updater),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);

      await _scrollTo(tester, find.text('Roof'));
      // Walls is pending: Start and Skip. Foundations is in progress without
      // approval: Complete. Design sign-off needs approval: not completable
      // here, and approving needs projects.*.
      expect(_button('Start'), findsOneWidget);
      expect(_button('Skip'), findsOneWidget);
      expect(_button('Complete'), findsOneWidget);
      expect(_button('Approve stage'), findsNothing);
    });

    testWidgets('Start sends the new status at once', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s4',
        (_) => Reply.json(stageJson(id: 's4')),
      );
      await pumpApp(
        tester,
        session: supervisorSession(perms: _updater),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, _button('Start'));

      await tester.tap(_button('Start'));
      await settle(tester);

      expect(env.adapter.count('PATCH', 'projects/p1/stages/s4'), 1);
      expect(env.adapter.last('PATCH', 'projects/p1/stages/s4').data, {
        'status': 'IN_PROGRESS',
      });
      expect(find.text('Started “Walls”.'), findsOneWidget);
    });

    testWidgets('Complete confirms first; cancelling sends nothing', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s3',
        (_) => Reply.json(stageJson(id: 's3')),
      );
      await pumpApp(
        tester,
        session: supervisorSession(perms: _updater),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, _button('Complete'));

      await tester.tap(_button('Complete'));
      await settle(tester);
      expect(find.text('Complete “Foundations”?'), findsOneWidget);
      expect(
        find.textContaining('cannot reopen a completed stage'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(env.adapter.requests.where((r) => r.method == 'PATCH'), isEmpty);

      await tester.tap(_button('Complete'));
      await settle(tester);
      await tester.tap(_button('Complete').last);
      await settle(tester);
      expect(env.adapter.last('PATCH', 'projects/p1/stages/s3').data, {
        'status': 'COMPLETED',
      });
      expect(find.text('Completed “Foundations”.'), findsOneWidget);
    });

    testWidgets('Skip confirms first, then sends SKIPPED', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s4',
        (_) => Reply.json(stageJson(id: 's4')),
      );
      await pumpApp(
        tester,
        session: supervisorSession(perms: _updater),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, _button('Skip'));

      await tester.tap(_button('Skip'));
      await settle(tester);
      expect(find.text('Skip “Walls”?'), findsOneWidget);
      expect(env.adapter.requests.where((r) => r.method == 'PATCH'), isEmpty);
      await tester.tap(_button('Skip').last);
      await settle(tester);

      expect(env.adapter.last('PATCH', 'projects/p1/stages/s4').data, {
        'status': 'SKIPPED',
      });
    });

    testWidgets('a refusal says why and leaves the stage as it was', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s4',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(
        tester,
        session: supervisorSession(perms: _updater),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, _button('Start'));

      await tester.tap(_button('Start'));
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(env.adapter.count('PATCH', 'projects/p1/stages/s4'), 1);
      expect(_button('Start'), findsOneWidget);
    });

    testWidgets('two taps in one frame send once', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s4',
        (_) =>
            Reply.json(stageJson(id: 's4'), delay: const Duration(seconds: 2)),
      );
      await pumpApp(
        tester,
        session: supervisorSession(perms: _updater),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, _button('Start'));

      // Two activations before any frame is drawn (the second tap of a real
      // double tap would find the button already disabled).
      final press = tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Start'))
          .onPressed!;
      press();
      press();
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(env.adapter.count('PATCH', 'projects/p1/stages/s4'), 1);
    });

    testWidgets('only someone holding projects.* can approve a stage', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'projects/p1/stages/s2/approve',
        (_) =>
            Reply.json(stageJson(id: 's2', status: 'COMPLETED'), status: 201),
      );
      await pumpApp(
        tester,
        session: supervisorSession(perms: _approver),
        env: env,
      );
      await settle(tester);
      await _openProject(tester);
      await _scrollTo(tester, _button('Approve stage'));

      await tester.tap(_button('Approve stage'));
      await settle(tester);
      expect(find.text('Approve “Design sign-off”?'), findsOneWidget);
      expect(find.text('Approving completes this stage.'), findsOneWidget);
      expect(env.adapter.count('POST', 'projects/p1/stages/s2/approve'), 0);
      await tester.tap(_button('Approve').last);
      await settle(tester);

      expect(env.adapter.count('POST', 'projects/p1/stages/s2/approve'), 1);
      expect(find.text('Stage approved.'), findsOneWidget);
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
          session: supervisorSession(perms: _approver),
          env: env,
          size: const Size(320, 640),
          textScale: 2.0,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await settle(tester);
        await _openProject(tester);
        for (final name in [
          'Site survey',
          'Design sign-off',
          'Foundations',
          'Walls',
          'Roof',
        ]) {
          await _scrollTo(tester, find.text(name));
        }
        await unmount(tester);
      } finally {
        errors = capture.stop();
      }
      expect(errors, isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
