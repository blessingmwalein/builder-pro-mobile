import 'dart:io';

import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/shared/services/photo_picker.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

Map<String, dynamic> _detail({String status = 'IN_PROGRESS'}) => taskJson(
  id: 'a',
  title: 'Pour slab',
  status: status,
  description: 'Block A, ground floor',
  checklists: [checklistJson()],
  comments: [
    {
      'id': 'cm1',
      'content': 'Rebar delivered',
      'createdAt': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
      'user': {'id': 'u2', 'firstName': 'Rudo', 'lastName': 'Banda'},
    },
  ],
);

void _apis(TestEnv env, {String status = 'IN_PROGRESS'}) {
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
      (_) =>
          Reply.json([taskJson(id: 'a', title: 'Pour slab', status: status)]),
    )
    ..on('GET', 'tasks/a', (_) => Reply.json(_detail(status: status)))
    ..on(
      'GET',
      'tasks/a/attachments',
      (_) => Reply.json([
        {
          'id': 'at1',
          'fileName': 'rebar.jpg',
          'contentType': 'image/jpeg',
          'sizeBytes': 250000,
        },
      ]),
    );
}

/// Scrolls the detail page until [finder] is built (the page is a lazy list).
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(finder); // built is not the same as on screen
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openTask(WidgetTester tester) async {
  // Supervisors and managers get the overview screens in the bar; for them
  // "My Tasks" is reached from More.
  if (find.text('My Tasks').evaluate().isEmpty) {
    await tester.tap(find.text('More').last);
    await settle(tester);
    // On a small phone with large text the card is below the fold.
    await tester.ensureVisible(find.text('My Tasks').last);
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(find.text('My Tasks').last);
  await settle(tester);
  await tester.tap(find.text('Pour slab'));
  await settle(tester);
}

void main() {
  testWidgets('shows the task, its checklist, comments and attachments', (
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
    await _openTask(tester);

    expect(find.text('Pour slab'), findsWidgets);
    expect(find.text('Block A, ground floor'), findsOneWidget);
    await _scrollTo(tester, find.text('Wear hard hat'));
    expect(find.text('CHECKLIST 1/2'), findsOneWidget);
    await _scrollTo(tester, find.text('rebar.jpg'));
    await _scrollTo(tester, find.text('Rebar delivered'));
    expect(find.text('Rudo Banda'), findsOneWidget);
  });

  testWidgets(
    'Worker role: can update status, but comment/photo/checklist actions are hidden until the backend allows them',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: SessionState.authenticated(
          testMe(),
        ), // tasks.view + tasks.complete
        env: env,
      );
      await settle(tester);
      await _openTask(tester);
      await tester.scrollUntilVisible(
        find.text('Wear hard hat'),
        200,
        scrollable: find.byType(Scrollable).last,
      );

      expect(find.text('Mark done'), findsOneWidget);
      expect(find.text('Post comment'), findsNothing);
      expect(find.text('Add photo'), findsNothing);

      // Tapping a checklist row must not send anything.
      await tester.tap(find.text('Wear hard hat'));
      await settle(tester);
      expect(
        env.adapter.requests.where((r) => r.path.contains('toggle')),
        isEmpty,
      );
    },
  );

  testWidgets(
    'Supervisor role (tasks.*): can toggle the checklist and comment',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter
        ..on(
          'PUT',
          'tasks/a/checklists/cl1/items/i1/toggle',
          (_) => Reply.json({}),
        )
        ..on(
          'POST',
          'tasks/a/comments',
          (_) => Reply.json({
            'id': 'cm2',
            'content': 'Starting now',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
            'user': {'id': 'u1', 'firstName': 'Tendai', 'lastName': 'Moyo'},
          }, status: 201),
        );
      await pumpApp(
        tester,
        session: SessionState.authenticated(
          testMe(permissions: supervisorPerms, role: 'Supervisor'),
        ),
        env: env,
      );
      await settle(tester);
      await _openTask(tester);

      await tester.scrollUntilVisible(
        find.text('Wear hard hat'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Wear hard hat'));
      await settle(tester);
      expect(find.text('CHECKLIST 2/2'), findsOneWidget);
      expect(
        env.adapter.count('PUT', 'tasks/a/checklists/cl1/items/i1/toggle'),
        1,
      );

      await tester.scrollUntilVisible(
        find.text('Post comment'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.enterText(find.byType(TextField).last, 'Starting now');
      await tester.tap(find.text('Post comment'));
      await settle(tester);
      expect(find.text('Starting now'), findsOneWidget);
      expect(env.adapter.last('POST', 'tasks/a/comments').data, {
        'content': 'Starting now',
      });
    },
  );

  testWidgets('Mark done asks first, then sends the status', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    env.adapter.on('PUT', 'tasks/a/status', (_) => Reply.json({}));
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openTask(tester);

    await tester.tap(find.text('Mark done'));
    await settle(tester);
    expect(find.text('Mark this task done?'), findsOneWidget);
    expect(env.adapter.count('PUT', 'tasks/a/status'), 0);

    // Cancelling changes nothing.
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(env.adapter.count('PUT', 'tasks/a/status'), 0);

    await tester.tap(find.text('Mark done'));
    await settle(tester);
    await tester.tap(find.widgetWithText(InkWell, 'Mark done').last);
    await settle(tester);

    expect(env.adapter.last('PUT', 'tasks/a/status').data, {'status': 'DONE'});
    expect(find.text('Task marked done.'), findsOneWidget);
  });

  testWidgets('a non-destructive status change needs no confirmation', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env, status: 'TODO');
    env.adapter.on('PUT', 'tasks/a/status', (_) => Reply.json({}));
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openTask(tester);

    await tester.tap(find.text('Start work'));
    await settle(tester);
    expect(env.adapter.last('PUT', 'tasks/a/status').data, {
      'status': 'IN_PROGRESS',
    });
    expect(find.text('In Progress'), findsWidgets);
  });

  testWidgets('offline status change is saved on the phone and says so', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env, status: 'TODO');
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
    await _openTask(tester);

    await tester.tap(find.text('Start work'));
    await settle(tester);

    expect(find.textContaining('Saved on your phone'), findsOneWidget);
    expect(
      find.text('Status saved on your phone, waiting to be sent.'),
      findsOneWidget,
    );
    final ops = await env.db.outboxFor('u1');
    expect(ops.single.payload, contains('IN_PROGRESS'));
  });

  testWidgets('a refused status change shows the reason and queues nothing', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env, status: 'TODO');
    env.adapter.on(
      'PUT',
      'tasks/a/status',
      (_) => Reply.json({'statusCode': 403}, status: 403),
    );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openTask(tester);

    await tester.tap(find.text('Start work'));
    await settle(tester);

    expect(find.textContaining("don't have permission"), findsOneWidget);
    expect(await env.db.outboxFor('u1'), isEmpty);
  });

  group('photos', () {
    late File jpg;
    setUp(() {
      final dir = Directory.systemTemp.createTempSync('bp_photo');
      jpg = File('${dir.path}/site.jpg')..writeAsBytesSync([1, 2, 3]);
      addTearDown(() {
        // The fake HTTP adapter never reads the upload stream, so the file may
        // still be open; a leftover temp file is harmless.
        try {
          dir.deleteSync(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });
    });

    testWidgets('a picked JPG is uploaded and listed', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'tasks/a/attachments',
        (_) => Reply.json({
          'id': 'at2',
          'fileName': 'site.jpg',
          'contentType': 'image/jpeg',
          'sizeBytes': 3,
          'url': 'https://x/uploads/tasks/site.jpg',
        }, status: 201),
      );
      final picker = FakePhotoPicker(
        PickedPhoto(path: jpg.path, name: 'site.jpg'),
      );
      await pumpApp(
        tester,
        session: SessionState.authenticated(
          testMe(permissions: supervisorPerms),
        ),
        env: env,
        overrides: [photoPickerProvider.overrideWithValue(picker)],
      );
      await settle(tester);
      await _openTask(tester);

      await _scrollTo(tester, find.text('Add photo'));
      await tester.tap(find.text('Add photo'));
      await settle(tester);
      await tester.tap(find.text('Choose from gallery'));
      await settle(tester);

      expect(picker.requested, [PhotoSource.gallery]);
      expect(env.adapter.count('POST', 'tasks/a/attachments'), 1);
      expect(find.text('site.jpg'), findsOneWidget);
    });

    testWidgets('an unsupported file type (HEIC) is refused before upload', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      final picker = FakePhotoPicker(
        PickedPhoto(path: jpg.path, name: 'IMG_0001.HEIC'),
      );
      await pumpApp(
        tester,
        session: SessionState.authenticated(
          testMe(permissions: supervisorPerms),
        ),
        env: env,
        overrides: [photoPickerProvider.overrideWithValue(picker)],
      );
      await settle(tester);
      await _openTask(tester);
      await _scrollTo(tester, find.text('Add photo'));
      await tester.tap(find.text('Add photo'));
      await settle(tester);
      await tester.tap(find.text('Take a photo'));
      await settle(tester);

      expect(find.textContaining('not supported'), findsOneWidget);
      expect(env.adapter.count('POST', 'tasks/a/attachments'), 0);
    });
  });

  testWidgets('large text on a small phone renders without overflow', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    final capture = ErrorCapture();
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe(permissions: supervisorPerms)),
      env: env,
      size: const Size(320, 640),
      textScale: 2.0,
    );
    await settle(tester);
    await _openTask(tester);
    expect(find.text('Pour slab'), findsWidgets);
    expect(capture.stop(), isEmpty);
  });
}
