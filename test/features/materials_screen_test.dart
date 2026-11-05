import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

void _apis(
  TestEnv env, {
  List<Map<String, dynamic>>? tasks,
  bool catalogOffline = false,
}) {
  env.adapter
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
      (_) => Reply.json(tasks ?? [taskJson(id: 'a')]),
    )
    ..on(
      'GET',
      'materials',
      (o) => catalogOffline
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              paged([
                materialJson(),
                materialJson(
                  id: 'm2',
                  name: 'River sand',
                  unit: 'm3',
                  stock: '8',
                ),
              ]),
            ),
    );
}

Future<void> _openMaterials(WidgetTester tester) async {
  await tester.tap(find.text('Materials').last);
  await settle(tester);
}

void main() {
  testWidgets('catalog lists materials with unit and stock (no costs shown)', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMaterials(tester);

    expect(find.text('Cement 50kg'), findsOneWidget);
    expect(find.text('40 bag in stock'), findsOneWidget);
    expect(find.text('River sand'), findsOneWidget);
    expect(find.textContaining('12.5'), findsNothing); // unit cost stays hidden
  });

  testWidgets('typing in search queries the server after a short pause', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMaterials(tester);
    final before = env.adapter.count('GET', 'materials');

    await tester.enterText(find.byType(TextField).first, 'sand');
    await tester.pump(const Duration(milliseconds: 100));
    // Not yet: the worker may still be typing.
    expect(env.adapter.count('GET', 'materials'), before);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    expect(env.adapter.count('GET', 'materials'), before + 1);
    expect(env.adapter.last('GET', 'materials').query['search'], 'sand');
  });

  testWidgets('a failed load shows an error with Retry, not an empty list', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env, catalogOffline: true);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMaterials(tester);

    expect(find.textContaining("offline or the server can't"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No materials yet'), findsNothing);
  });

  group('logging usage', () {
    Future<void> openLogForm(WidgetTester tester) async {
      await tester.tap(find.text('Cement 50kg'));
      await settle(tester);
      expect(find.text('Log material'), findsOneWidget);
    }

    testWidgets(
      'validates, confirms with a summary, then posts the catalog cost',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'materials/usage',
          (_) => Reply.json({
            'id': 'log1',
            'projectId': 'p1',
            'materialId': 'm1',
            'quantity': '12.000',
            'unitCost': '12.50',
            'usedAt': DateTime.now().toUtc().toIso8601String(),
          }, status: 201),
        );
        await pumpApp(
          tester,
          session: SessionState.authenticated(testMe()),
          env: env,
        );
        await settle(tester);
        await _openMaterials(tester);
        await openLogForm(tester);

        // One assigned project: it is preselected.
        expect(find.text('HT-01 · Harare Tower'), findsOneWidget);

        // Nothing typed yet.
        await tester.tap(find.text('Log usage').last);
        await settle(tester);
        expect(find.text('Enter how much you used'), findsOneWidget);
        expect(env.adapter.count('POST', 'materials/usage'), 0);

        // Letters are not even accepted.
        await tester.enterText(find.byType(TextFormField).first, 'abc');
        expect(find.text('abc'), findsNothing);

        await tester.enterText(find.byType(TextFormField).first, '12,5');
        await tester.tap(find.text('Log usage').last);
        await settle(tester);
        expect(find.text('Log this usage?'), findsOneWidget);
        expect(
          find.textContaining('12.5 bag of Cement 50kg on Harare Tower'),
          findsOneWidget,
        );
        expect(env.adapter.count('POST', 'materials/usage'), 0);

        await tester.tap(find.widgetWithText(InkWell, 'Log usage').last);
        await settle(tester);

        final sent = env.adapter.last('POST', 'materials/usage').data as Map;
        expect(sent['quantity'], 12.5);
        expect(sent['unitCost'], 12.5);
        expect(sent['projectId'], 'p1');
        expect(sent['materialId'], 'm1');
        // Back on the catalog with the confirmation and the session log.
        expect(find.text('Log material'), findsNothing);
        expect(find.text('LOGGED ON THIS PHONE'), findsOneWidget);
      },
    );

    testWidgets('warns (but allows) quantities above the stock on record', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openMaterials(tester);
      await openLogForm(tester);

      await tester.enterText(find.byType(TextFormField).first, '100');
      await tester.pump();
      expect(
        find.textContaining('more than the 40 bag on record'),
        findsOneWidget,
      );
    });

    testWidgets('a server refusal stays on the form with the message', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'materials/usage',
        (_) => Reply.json({
          'statusCode': 404,
          'message': 'Material not found',
        }, status: 404),
      );
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openMaterials(tester);
      await openLogForm(tester);

      await tester.enterText(find.byType(TextFormField).first, '2');
      await tester.tap(find.text('Log usage').last);
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Log usage').last);
      await settle(tester);

      expect(find.text('Log material'), findsOneWidget);
      expect(find.text('Material not found'), findsOneWidget);
      expect(find.text('LOGGED ON THIS PHONE'), findsNothing);
    });

    testWidgets('with several projects the worker must choose one', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(
        env,
        tasks: [
          taskJson(id: 'a'),
          taskJson(id: 'b', projectId: 'p2', projectName: 'Borrowdale'),
        ],
      );
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openMaterials(tester);
      await openLogForm(tester);

      expect(find.text('Choose a project'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '3');
      await tester.tap(find.text('Log usage').last);
      await settle(tester);
      expect(find.text('Choose the project first.'), findsOneWidget);
      expect(find.text('Log this usage?'), findsNothing);
    });

    testWidgets('no assigned project: explains how to get one', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, tasks: []);
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await _openMaterials(tester);
      await openLogForm(tester);

      expect(find.textContaining('Ask your supervisor'), findsOneWidget);
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
        session: SessionState.authenticated(testMe()),
        env: env,
        size: const Size(320, 640),
        textScale: 2.0,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await settle(tester);
      await _openMaterials(tester);
      await tester.tap(find.text('Cement 50kg'));
      await settle(tester);
      expect(find.text('Log material'), findsOneWidget);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
