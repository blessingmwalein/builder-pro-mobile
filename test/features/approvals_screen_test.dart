import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

Future<void> _openApprovals(WidgetTester tester) async {
  await tester.tap(find.text('Approvals').last);
  await settle(tester);
}

void main() {
  testWidgets('groups finished shifts by worker and lists who is working now', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);

    expect(find.text('3 shifts to review'), findsOneWidget);
    expect(find.text('RUDO BANDA'), findsOneWidget);
    expect(find.text('TENDAI MOYO'), findsOneWidget);
    expect(find.text('Approve all 2'), findsOneWidget); // only Tendai has two
    expect(find.text('WORKING NOW'), findsOneWidget);
    expect(find.text('Farai Ncube'), findsOneWidget);
    // Hand-entered time is flagged, with the worker's note.
    expect(find.text('Entered by hand'), findsOneWidget);
    expect(find.text('Forgot to clock in'), findsOneWidget);
    // Pay is never shown to approvers.
    expect(find.textContaining('40.00'), findsNothing);
  });

  testWidgets('Approve asks first, then sends APPROVED and removes the shift', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    env.adapter.on('PUT', 'time-tracking/e3/approve', (_) => Reply.json({}));
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);

    // Rudo's only shift: the first Approve button on screen belongs to Rudo.
    await tester.tap(find.text('Approve').first);
    await settle(tester);
    expect(find.text('Approve this time?'), findsOneWidget);
    expect(find.textContaining('Rudo Banda'), findsWidgets);
    expect(env.adapter.count('PUT', 'time-tracking/e3/approve'), 0);

    await tester.tap(find.widgetWithText(InkWell, 'Approve').last);
    await settle(tester);

    expect(env.adapter.last('PUT', 'time-tracking/e3/approve').data, {
      'status': 'APPROVED',
    });
    expect(find.text('RUDO BANDA'), findsNothing);
    expect(find.text('2 shifts to review'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation sends nothing', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);

    await tester.tap(find.text('Approve').first);
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(
      env.adapter.requests.where((r) => r.path.endsWith('/approve')),
      isEmpty,
    );
    expect(find.text('3 shifts to review'), findsOneWidget);
  });

  testWidgets('Reject takes an optional reason and sends REJECTED', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    env.adapter.on('PUT', 'time-tracking/e3/approve', (_) => Reply.json({}));
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);

    await tester.tap(find.text('Reject').first);
    await settle(tester);
    expect(find.text('Reject this time?'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '  Wrong project  ');
    await tester.tap(find.widgetWithText(InkWell, 'Reject').last);
    await settle(tester);

    expect(env.adapter.last('PUT', 'time-tracking/e3/approve').data, {
      'status': 'REJECTED',
      'approvalComment': 'Wrong project',
    });
    expect(find.text('RUDO BANDA'), findsNothing);
  });

  testWidgets('Approve all for a worker confirms, then decides each shift', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    env.adapter
      ..on('PUT', 'time-tracking/e1/approve', (_) => Reply.json({}))
      ..on('PUT', 'time-tracking/e2/approve', (_) => Reply.json({}));
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);

    await tester.tap(find.text('Approve all 2'));
    await settle(tester);
    expect(find.text('Approve all for Tendai Moyo?'), findsOneWidget);
    await tester.tap(find.widgetWithText(InkWell, 'Approve 2').last);
    await settle(tester, frames: 20);

    expect(env.adapter.count('PUT', 'time-tracking/e1/approve'), 1);
    expect(env.adapter.count('PUT', 'time-tracking/e2/approve'), 1);
    expect(find.text('TENDAI MOYO'), findsNothing);
    expect(find.text('1 shift to review'), findsOneWidget);
  });

  testWidgets(
    'Approve all stops at the first problem and says how far it got',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      env.adapter
        ..on('PUT', 'time-tracking/e1/approve', (_) => Reply.json({}))
        ..on(
          'PUT',
          'time-tracking/e2/approve',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openApprovals(tester);

      await tester.tap(find.text('Approve all 2'));
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Approve 2').last);
      await settle(tester, frames: 20);

      expect(find.textContaining('Approved 1 of 2'), findsOneWidget);
      expect(find.text('TENDAI MOYO'), findsOneWidget); // one shift remains
    },
  );

  testWidgets('a failed approval leaves the shift and shows the reason', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env);
    env.adapter.on(
      'PUT',
      'time-tracking/e3/approve',
      (_) => Reply.fail(DioExceptionType.connectionError),
    );
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);

    await tester.tap(find.text('Approve').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Approve').last);
    await settle(tester);

    expect(find.textContaining("offline or the server can't"), findsOneWidget);
    expect(find.text('RUDO BANDA'), findsOneWidget);
  });

  testWidgets('nothing pending: "All caught up"', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env, pending: []);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);
    expect(find.text('All caught up'), findsWidgets);
  });

  testWidgets('a failed load is an error with Retry, not "all caught up"', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    supervisorApis(env, approvalsOffline: true);
    await pumpApp(tester, session: supervisorSession(), env: env);
    await settle(tester);
    await _openApprovals(tester);
    expect(find.textContaining('No connection'), findsWidgets);
    expect(find.text('Try again'), findsWidgets);
    expect(find.text('All caught up'), findsNothing);
  });

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
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
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await settle(tester);
      await _openApprovals(tester);
      expect(find.text('Approvals'), findsWidgets);
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
