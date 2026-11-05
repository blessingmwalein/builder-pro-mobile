import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/features/messaging/data/messaging_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

/// A fixed time of day today, so a test run just after midnight does not split
/// two "recent" messages across a day boundary (the thread shows a date
/// separator there and repeats the sender's name).
DateTime _todayAt(int hour, int minute) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour, minute);
}

void _apis(TestEnv env, {List<Map<String, dynamic>>? conversations}) {
  env.adapter
    ..on('GET', 'time-tracking/active', (_) => Reply.empty())
    ..on(
      'GET',
      'time-tracking/weekly-summary',
      (_) => Reply.json({'entries': []}),
    )
    ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
    ..on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson(id: 'a')]))
    ..on(
      'GET',
      'messaging/conversations',
      (_) => Reply.json(
        conversations ??
            [
              conversationJson(lastBody: 'Slab is ready'),
              conversationJson(
                id: 'dm1',
                type: 'DIRECT',
                title: 'Rudo Banda',
                lastBody: 'See you at 7',
              ),
            ],
      ),
    )
    ..on(
      'GET',
      'messaging/conversations/conv1/messages',
      (_) => Reply.json(
        paged([
          messageJson(id: 'm1', body: 'Morning team', at: _todayAt(9, 0)),
          messageJson(id: 'm2', body: 'Slab is ready', at: _todayAt(9, 5)),
        ], limit: 30),
      ),
    )
    ..on(
      'PUT',
      'messaging/conversations/conv1/read',
      (_) => Reply.json({'success': true}),
    );
}

/// Leaves the thread so its polling timer is cancelled before the test ends
/// (the screen's provider is disposed when it leaves the tree).
Future<void> _leaveThread(WidgetTester tester) async {
  await tester.pageBack();
  await settle(tester);
}

Future<void> _openMessages(WidgetTester tester) async {
  await tester.tap(find.text('Messages').last);
  await settle(tester);
}

void main() {
  testWidgets('conversation list shows project channels and direct chats', (
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
    await _openMessages(tester);

    expect(find.text('Harare Tower'), findsOneWidget);
    expect(find.text('Rudo Banda: Slab is ready'), findsOneWidget);
    expect(find.text('Rudo Banda'), findsOneWidget);
    expect(find.text('Rudo Banda: See you at 7'), findsOneWidget);
  });

  testWidgets('empty list explains itself', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env, conversations: []);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMessages(tester);
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('opening a conversation shows messages with sender names', (
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
    await _openMessages(tester);
    await tester.tap(find.text('Harare Tower'));
    await settle(tester);

    expect(find.text('Morning team'), findsOneWidget);
    expect(find.text('Slab is ready'), findsWidgets);
    expect(
      find.text('Rudo Banda'),
      findsOneWidget,
    ); // sender, shown once in a row
    expect(find.text('Updates every few seconds'), findsOneWidget);
    expect(env.realtime.joined, ['conv1']);
    await _leaveThread(tester);
  });

  testWidgets('typing and sending adds the message and posts it', (
    tester,
  ) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    env.adapter.on(
      'POST',
      'messaging/messages',
      (_) => Reply.json(
        messageJson(
          id: 'srv1',
          senderId: 'u1',
          first: 'Tendai',
          last: 'Moyo',
          body: 'On my way',
        ),
        status: 201,
      ),
    );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMessages(tester);
    await tester.tap(find.text('Harare Tower'));
    await settle(tester);

    // Send is disabled until there is text.
    final send = find.bySemanticsLabel('Send message');
    expect(send, findsOneWidget);

    await tester.enterText(find.byType(TextField), 'On my way');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await settle(tester);

    expect(find.text('On my way'), findsOneWidget);
    expect(env.adapter.last('POST', 'messaging/messages').data, {
      'conversationId': 'conv1',
      'body': 'On my way',
    });
    // The composer cleared.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await _leaveThread(tester);
  });

  testWidgets('a pushed message appears live', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMessages(tester);
    await tester.tap(find.text('Harare Tower'));
    await settle(tester);

    env.realtime.setConnected(true);
    env.realtime.push(
      ChatMessage.tryParse(
        messageJson(id: 'm3', body: 'Concrete arrives at 9'),
      )!,
    );
    await settle(tester);

    expect(find.text('Concrete arrives at 9'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    await _leaveThread(tester);
  });

  testWidgets('a failed send shows why, with Retry and Delete', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    env.adapter.on(
      'POST',
      'messaging/messages',
      (_) => Reply.json({'statusCode': 403}, status: 403),
    );
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      env: env,
    );
    await settle(tester);
    await _openMessages(tester);
    await tester.tap(find.text('Harare Tower'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await settle(tester);

    expect(find.textContaining("don't have permission"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Hello'), findsNothing);
    await _leaveThread(tester);
  });

  testWidgets('without messaging.send the thread is read-only', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    _apis(env);
    await pumpApp(
      tester,
      session: SessionState.authenticated(
        testMe(permissions: ['messaging.view', 'tasks.view']),
      ),
      env: env,
    );
    await settle(tester);
    await tester.tap(find.text('Messages').last);
    await settle(tester);
    await tester.tap(find.text('Harare Tower'));
    await settle(tester);

    expect(find.text('Morning team'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text('You can read this conversation but not send messages.'),
      findsOneWidget,
    );
    await _leaveThread(tester);
  });

  group('notifications', () {
    Future<void> openNotifications(WidgetTester tester) async {
      await tester.tap(find.text('More').last);
      await settle(tester);
      await tester.tap(find.text('Notifications').last);
      await settle(tester);
    }

    testWidgets(
      'backend change not deployed (403): "Not available yet", not an error',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'GET',
          'notifications/me',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        await pumpApp(
          tester,
          session: SessionState.authenticated(testMe()),
          env: env,
        );
        await settle(tester);
        await openNotifications(tester);

        expect(find.text('Not available yet'), findsOneWidget);
        expect(find.text('Something went wrong'), findsNothing);
      },
    );

    testWidgets('empty list', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on('GET', 'notifications/me', (_) => Reply.json(paged([])));
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await openNotifications(tester);
      expect(find.text('No notifications yet'), findsOneWidget);
    });

    testWidgets('tapping an unread notification marks it read', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter
        ..on(
          'GET',
          'notifications/me',
          (_) => Reply.json(
            paged([
              {
                'id': 'n1',
                'title': 'New task assigned',
                'body': 'Pour slab',
                'isRead': false,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            ]),
          ),
        )
        ..on('PATCH', 'notifications/n1/read', (_) => Reply.json({'count': 1}));
      await pumpApp(
        tester,
        session: SessionState.authenticated(testMe()),
        env: env,
      );
      await settle(tester);
      await openNotifications(tester);

      await tester.tap(find.text('New task assigned'));
      await settle(tester);
      expect(env.adapter.last('PATCH', 'notifications/n1/read').data, {
        'isRead': true,
      });
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
      await _openMessages(tester);
      await tester.tap(find.text('Harare Tower'));
      await settle(tester);
      expect(find.text('Morning team'), findsOneWidget);
      await _leaveThread(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
