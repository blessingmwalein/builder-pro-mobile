import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/messaging/application/messaging_providers.dart';
import 'package:builder_pro_mobile/features/messaging/data/messaging_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';

const _path = 'messaging/conversations/conv1/messages';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('conversations', () {
    test('parse titles, last message and sender; project channels fall back to the project name', () async {
      env.adapter.on(
        'GET',
        'messaging/conversations',
        (_) => Reply.json([
          conversationJson(lastBody: 'Slab poured'),
          conversationJson(id: 'dm', type: 'DIRECT', title: null),
          conversationJson(id: 'dm2', type: 'DIRECT', title: 'Rudo'),
        ]),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);

      final list = await c.read(conversationsProvider.future);
      expect(list[0].displayTitle, 'Harare Tower');
      expect(list[0].lastBody, 'Slab poured');
      expect(list[0].lastSender, 'Rudo Banda');
      expect(
        list[1].displayTitle,
        'Harare Tower',
      ); // has a project in the fixture
      expect(list[2].displayTitle, 'Rudo');
    });

    test('an empty list is fine', () async {
      env.adapter.on('GET', 'messaging/conversations', (_) => Reply.json([]));
      final c = makeContainer(env);
      addTearDown(c.dispose);
      expect(await c.read(conversationsProvider.future), isEmpty);
    });
  });

  group('thread', () {
    final t0 = DateTime(2026, 10, 26, 9);
    Map<String, dynamic> page(
      List<Map<String, dynamic>> msgs, {
      int pageNo = 1,
      int total = 0,
    }) => paged(
      msgs,
      page: pageNo,
      limit: 30,
      total: total == 0 ? msgs.length : total,
    );

    /// GET replies for the thread after the first load, consumed in order;
    /// once empty the default page is returned.
    late List<Reply Function(RequestOptions)> nextGets;

    Future<({ProviderContainer c, ThreadController Function() n})> open({
      List<Map<String, dynamic>>? initial,
      int total = 0,
    }) async {
      nextGets = [];
      final defaultPage = page(
        initial ??
            [
              messageJson(id: 'm1', body: 'Morning', at: t0),
              messageJson(
                id: 'm2',
                body: 'Slab is ready',
                at: t0.add(const Duration(minutes: 5)),
              ),
            ],
        total: total,
      );
      env.adapter
        ..on(
          'GET',
          _path,
          (o) => nextGets.isEmpty
              ? Reply.json(defaultPage)
              : nextGets.removeAt(0)(o),
        )
        ..on(
          'PUT',
          'messaging/conversations/conv1/read',
          (_) => Reply.json({'success': true}),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      c.listen(threadProvider('conv1'), (_, _) {});
      await c.read(threadProvider('conv1').future);
      return (c: c, n: () => c.read(threadProvider('conv1').notifier));
    }

    test('loads page 1 (newest, already oldest-first), joins the room and marks read', () async {
      final t = await open();
      final s = t.c.read(threadProvider('conv1')).value!;
      expect(s.messages.map((m) => m.id), ['m1', 'm2']);
      expect(s.hasOlder, isFalse);
      expect(env.realtime.started, isTrue);
      expect(env.realtime.joined, ['conv1']);
      await pumpEventQueue();
      expect(env.adapter.count('PUT', 'messaging/conversations/conv1/read'), 1);
      expect(env.adapter.last('GET', _path).query, {'page': 1, 'limit': 30});
    });

    test('a pushed message is added once, even if it arrives twice', () async {
      final t = await open();
      final pushed = ChatMessage.tryParse(
        messageJson(
          id: 'm3',
          body: 'On my way',
          at: t0.add(const Duration(minutes: 9)),
        ),
      )!;
      env.realtime.push(pushed);
      env.realtime.push(pushed);
      await pumpEventQueue();
      expect(
        t.c.read(threadProvider('conv1')).value!.messages.map((m) => m.id),
        ['m1', 'm2', 'm3'],
      );
    });

    test('a push for another conversation is ignored', () async {
      final t = await open();
      env.realtime.push(
        ChatMessage.tryParse(messageJson(id: 'x', conversationId: 'other'))!,
      );
      await pumpEventQueue();
      expect(t.c.read(threadProvider('conv1')).value!.messages, hasLength(2));
    });

    test(
      'messages are kept in time order when they arrive out of order',
      () async {
        final t = await open();
        env.realtime.push(
          ChatMessage.tryParse(
            messageJson(
              id: 'm0',
              body: 'Earlier',
              at: t0.subtract(const Duration(hours: 1)),
            ),
          )!,
        );
        await pumpEventQueue();
        expect(
          t.c.read(threadProvider('conv1')).value!.messages.first.id,
          'm0',
        );
      },
    );

    test('sending shows the message at once, then replaces it with the server copy', () async {
      final t = await open();
      env.adapter.on(
        'POST',
        'messaging/messages',
        (_) => Reply.json(
          messageJson(
            id: 'srv1',
            senderId: 'u1',
            first: 'Tendai',
            last: 'Moyo',
            body: 'Done here',
          ),
          status: 201,
        ),
      );

      final sending = t.n().send('  Done here  ');
      final during = t.c.read(threadProvider('conv1')).value!.messages.last;
      expect(during.state, SendState.sending);
      expect(during.body, 'Done here');
      await sending;

      final msgs = t.c.read(threadProvider('conv1')).value!.messages;
      expect(msgs.map((m) => m.id), ['m1', 'm2', 'srv1']);
      expect(msgs.every((m) => !m.isLocal), isTrue);
      expect(env.adapter.last('POST', 'messaging/messages').data, {
        'conversationId': 'conv1',
        'body': 'Done here',
      });
    });

    test('if the live push of my own message beats the reply, it is not duplicated', () async {
      final t = await open();
      env.adapter.on('POST', 'messaging/messages', (_) {
        // The socket echo arrives while the HTTP reply is still in flight.
        env.realtime.push(
          ChatMessage.tryParse(
            messageJson(id: 'srv1', senderId: 'u1', body: 'Hi'),
          )!,
        );
        return Reply.json(
          messageJson(id: 'srv1', senderId: 'u1', body: 'Hi'),
          status: 201,
        );
      });
      await t.n().send('Hi');
      await pumpEventQueue();
      expect(
        t.c
            .read(threadProvider('conv1'))
            .value!
            .messages
            .where((m) => m.body == 'Hi'),
        hasLength(1),
      );
    });

    test('my own message echoed before the reply is never shown twice, even briefly', () async {
      final t = await open();
      env.adapter.on('POST', 'messaging/messages', (_) {
        env.realtime.push(
          ChatMessage.tryParse(
            messageJson(
              id: 'srv1',
              senderId: 'u1',
              first: 'Tendai',
              last: 'Moyo',
              body: 'Hi',
            ),
          )!,
        );
        return Reply.json(
          messageJson(id: 'srv1', senderId: 'u1', body: 'Hi'),
          status: 201,
          delay: const Duration(milliseconds: 250),
        );
      });

      final sending = t.n().send('Hi');
      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      ); // echo arrived, reply still pending
      final mid = t.c
          .read(threadProvider('conv1'))
          .value!
          .messages
          .where((m) => m.body == 'Hi')
          .toList();
      expect(mid, hasLength(1));
      expect(mid.single.isLocal, isFalse);
      await sending;
      expect(
        t.c
            .read(threadProvider('conv1'))
            .value!
            .messages
            .where((m) => m.body == 'Hi'),
        hasLength(1),
      );
    });

    test('an older identical message does not swallow a new one being sent', () async {
      final t = await open(
        initial: [messageJson(id: 'old', senderId: 'u1', body: 'ok', at: t0)],
      );
      env.adapter.on(
        'POST',
        'messaging/messages',
        (_) => Reply.json(
          messageJson(id: 'srv2', senderId: 'u1', body: 'ok'),
          status: 201,
          delay: const Duration(milliseconds: 150),
        ),
      );

      final sending = t.n().send('ok');
      // A poll brings back only the OLD message while the new one is in flight.
      await t.n().refreshLatest();
      final mid = t.c
          .read(threadProvider('conv1'))
          .value!
          .messages
          .where((m) => m.body == 'ok')
          .toList();
      expect(mid.map((m) => m.isLocal), [
        false,
        true,
      ]); // old + the one still sending
      await sending;
      expect(
        t.c
            .read(threadProvider('conv1'))
            .value!
            .messages
            .where((m) => m.body == 'ok'),
        hasLength(2),
      );
    });

    test('the live connection is closed when the last thread closes', () async {
      var disposed = false;
      final env2 = TestEnv(
        realtimeOverride: realtimeMessagesProvider.overrideWith((ref) {
          ref.onDispose(() => disposed = true);
          return env.realtime;
        }),
      );
      addTearDown(env2.dispose);
      env2.adapter
        ..on(
          'GET',
          _path,
          (_) => Reply.json(page([messageJson(id: 'm1', at: t0)])),
        )
        ..on(
          'PUT',
          'messaging/conversations/conv1/read',
          (_) => Reply.json({'success': true}),
        );
      final c = makeContainer(env2);
      addTearDown(c.dispose);
      final sub = c.listen(threadProvider('conv1'), (_, _) {});
      await c.read(threadProvider('conv1').future);
      expect(disposed, isFalse);

      sub.close();
      await pumpEventQueue(times: 30);

      expect(disposed, isTrue);
    });

    test('empty or blank text is never sent', () async {
      final t = await open();
      await t.n().send('   ');
      expect(env.adapter.count('POST', 'messaging/messages'), 0);
    });

    test('a refused send stays in the list as failed with the reason, and can be deleted', () async {
      final t = await open();
      env.adapter.on(
        'POST',
        'messaging/messages',
        (_) => Reply.json({'statusCode': 403, 'message': 'x'}, status: 403),
      );
      await t.n().send('Hello');
      final m = t.c.read(threadProvider('conv1')).value!.messages.last;
      expect(m.state, SendState.failed);
      expect(m.error, isNotNull);

      t.n().discard(m.id);
      expect(
        t.c.read(threadProvider('conv1')).value!.messages.any((x) => x.isLocal),
        isFalse,
      );
    });

    test('no connection: failed, then retry sends it', () async {
      final t = await open();
      env.adapter
        ..on(
          'POST',
          'messaging/messages',
          (_) => Reply.fail(DioExceptionType.connectionError),
        )
        ..on(
          'POST',
          'messaging/messages',
          (_) => Reply.json(
            messageJson(id: 'srv1', senderId: 'u1', body: 'Hello'),
            status: 201,
          ),
        );
      await t.n().send('Hello');
      final failed = t.c.read(threadProvider('conv1')).value!.messages.last;
      expect(failed.state, SendState.failed);

      await t.n().retry(failed.id);
      final msgs = t.c.read(threadProvider('conv1')).value!.messages;
      expect(msgs.last.id, 'srv1');
      expect(msgs.where((m) => m.isLocal), isEmpty);
    });

    test('timed out but the message is already on the server: not shown as failed, not resent', () async {
      final t = await open();
      env.adapter.on(
        'POST',
        'messaging/messages',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      );
      // The re-check finds my message.
      nextGets.add(
        (_) => Reply.json(
          page([
            messageJson(id: 'm1', body: 'Morning', at: t0),
            messageJson(
              id: 'm2',
              body: 'Slab is ready',
              at: t0.add(const Duration(minutes: 5)),
            ),
            messageJson(id: 'srv1', senderId: 'u1', body: 'Hello'),
          ]),
        ),
      );
      await t.n().send('Hello');

      final msgs = t.c.read(threadProvider('conv1')).value!.messages;
      expect(msgs.where((m) => m.isLocal), isEmpty);
      expect(msgs.where((m) => m.body == 'Hello'), hasLength(1));
      expect(env.adapter.count('POST', 'messaging/messages'), 1);
    });

    test(
      'timed out and not found on the server: failed with a safe retry',
      () async {
        final t = await open();
        env.adapter.on(
          'POST',
          'messaging/messages',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        );
        await t.n().send('Hello');
        final m = t.c.read(threadProvider('conv1')).value!.messages.last;
        expect(m.state, SendState.failed);
        expect(m.maybeSent, isFalse);
        expect(m.error, contains('Not sent'));
      },
    );

    test('timed out and the check also fails: marked "may not have sent"; retry checks first', () async {
      final t = await open();
      env.adapter.on(
        'POST',
        'messaging/messages',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      );
      nextGets.add(
        (_) => Reply.fail(DioExceptionType.connectionError),
      ); // the check after the timeout
      await t.n().send('Hello');
      final m = t.c.read(threadProvider('conv1')).value!.messages.last;
      expect(m.maybeSent, isTrue);
      expect(m.error, contains('May not have sent'));

      // By the time they retry, the server shows the message.
      nextGets.add(
        (_) => Reply.json(
          page([
            messageJson(id: 'm1', body: 'Morning', at: t0),
            messageJson(id: 'srv1', senderId: 'u1', body: 'Hello'),
          ]),
        ),
      );
      await t.n().retry(
        m.id,
      ); // finds it on the server instead of sending again
      expect(env.adapter.count('POST', 'messaging/messages'), 1);
      expect(
        t.c
            .read(threadProvider('conv1'))
            .value!
            .messages
            .where((x) => x.isLocal),
        isEmpty,
      );
    });

    test('loading earlier messages prepends the next page', () async {
      final t = await open(total: 40);
      expect(t.c.read(threadProvider('conv1')).value!.hasOlder, isTrue);
      nextGets.add(
        (_) => Reply.json(
          page(
            [
              messageJson(
                id: 'old1',
                body: 'Yesterday',
                at: t0.subtract(const Duration(days: 1)),
              ),
            ],
            pageNo: 2,
            total: 31,
          ),
        ),
      );

      await t.n().loadOlder();

      final s = t.c.read(threadProvider('conv1')).value!;
      expect(s.messages.first.id, 'old1');
      expect(s.page, 2);
      expect(env.adapter.last('GET', _path).query['page'], 2);
    });

    test('a failed first load is an error the screen can retry', () async {
      env.adapter.on(
        'GET',
        _path,
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      c.listen(threadProvider('conv1'), (_, _) {});
      await expectLater(
        c.read(threadProvider('conv1').future),
        throwsA(isA<AppException>()),
      );
    });

    test('live indicator follows the socket connection', () async {
      final t = await open();
      expect(t.c.read(threadProvider('conv1')).value!.live, isFalse);
      env.realtime.setConnected(true);
      await pumpEventQueue();
      expect(t.c.read(threadProvider('conv1')).value!.live, isTrue);
    });
  });

  group('notifications', () {
    test('lists the user\'s notifications and marks one read', () async {
      env.adapter
        ..on(
          'GET',
          'notifications/me',
          (_) => Reply.json(
            paged([
              {
                'id': 'n1',
                'title': 'New task',
                'body': 'Pour slab',
                'isRead': false,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              },
            ]),
          ),
        )
        ..on('PATCH', 'notifications/n1/read', (_) => Reply.json({'count': 1}));
      final c = makeContainer(env);
      addTearDown(c.dispose);
      expect(
        (await c.read(notificationsProvider.future)).single.isRead,
        isFalse,
      );

      await c.read(notificationsProvider.notifier).markRead('n1');

      expect(c.read(notificationsProvider).value!.single.isRead, isTrue);
      expect(env.adapter.last('PATCH', 'notifications/n1/read').data, {
        'isRead': true,
      });
    });

    test('403 (backend change not deployed) surfaces as a forbidden error, not a crash', () async {
      env.adapter.on(
        'GET',
        'notifications/me',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await expectLater(
        c.read(notificationsProvider.future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
    });
  });
}
