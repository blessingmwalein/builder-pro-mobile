import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/tasks/application/task_groups.dart';
import 'package:builder_pro_mobile/features/tasks/application/tasks_providers.dart';
import 'package:builder_pro_mobile/features/tasks/data/task_models.dart';
import 'package:builder_pro_mobile/features/tasks/data/tasks_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('parsing', () {
    test(
      'a task keeps its project, checklist progress and string estimate',
      () {
        final t = TaskItem.tryParse(
          taskJson(checklists: [checklistJson()], commentCount: 3),
        )!;
        expect(t.project.label, 'HT-01 · Harare Tower');
        expect(t.estimatedHours, 8);
        expect(t.checklistTotal, 2);
        expect(t.checklistDone, 1);
        expect(t.commentCount, 3);
        expect(t.assigneeNames, ['Tendai Moyo']);
      },
    );

    test('rows without an id are dropped; unknown fields are ignored', () {
      expect(TaskItem.tryParse({'title': 'no id'}), isNull);
      expect(TaskItem.tryParse(null), isNull);
      expect(
        TaskItem.tryParse({'id': 'x', 'surprise': 1})!.title,
        'Untitled task',
      );
    });

    test('overdue is by calendar day and never for done tasks', () {
      final now = DateTime(2026, 10, 26, 12);
      TaskItem task(String status, DateTime due) =>
          TaskItem.tryParse(taskJson(status: status, dueDate: _iso(due)))!;
      expect(task('TODO', DateTime(2026, 10, 25, 23)).isOverdue(now), isTrue);
      expect(task('TODO', DateTime(2026, 10, 26, 8)).isOverdue(now), isFalse);
      expect(task('DONE', DateTime(2026, 10, 20)).isOverdue(now), isFalse);
    });

    test('mime type lookup rejects HEIC and unknown types', () {
      expect(mimeTypeForAttachment('site.JPG'), 'image/jpeg');
      expect(mimeTypeForAttachment('plan.pdf'), 'application/pdf');
      expect(mimeTypeForAttachment('IMG_1.heic'), isNull);
      expect(mimeTypeForAttachment('noextension'), isNull);
    });
  });

  group('grouping', () {
    final now = DateTime(2026, 10, 26, 12);
    TaskItem t(String id, {String? due, String status = 'TODO'}) =>
        TaskItem.tryParse(taskJson(id: id, dueDate: due, status: status))!;

    test('orders Overdue, Today, Upcoming, No date and skips empty groups', () {
      final groups = groupTasks([
        t('none'),
        t('later', due: _iso(DateTime(2026, 11, 2, 12))),
        t('today', due: _iso(DateTime(2026, 10, 26, 15))),
        t('late', due: _iso(DateTime(2026, 10, 20, 12))),
      ], now);
      expect(groups.map((g) => g.$1), [
        TaskGroup.overdue,
        TaskGroup.today,
        TaskGroup.upcoming,
        TaskGroup.noDate,
      ]);
      expect(groups.first.$2.single.id, 'late');
    });

    test('keeps the server order inside a group', () {
      final groups = groupTasks([t('b'), t('a'), t('c')], now);
      expect(groups.single.$2.map((x) => x.id), ['b', 'a', 'c']);
    });

    test('hides done tasks and applies the status filter', () {
      final groups = groupTasks(
        [t('a', status: 'DONE'), t('b', status: 'IN_PROGRESS'), t('c')],
        now,
        status: 'IN_PROGRESS',
      );
      expect(groups.single.$2.single.id, 'b');
    });
  });

  group('queue + offline cache', () {
    test(
      'my-queue (a plain array) is loaded and cached for offline use',
      () async {
        env.adapter.on(
          'GET',
          'tasks/my-queue',
          (_) => Reply.json([taskJson(id: 'a'), taskJson(id: 'b')]),
        );
        final c = makeContainer(env);
        addTearDown(c.dispose);

        final snap = await c.read(tasksProvider.future);
        expect(snap.tasks.map((x) => x.id), ['a', 'b']);
        expect(snap.fromCache, isFalse);
        expect((await env.db.readCache('u1', 'task')).length, 2);
      },
    );

    test('with no connection the saved list is shown and flagged', () async {
      env.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.json([taskJson(id: 'a')]),
      );
      final online = makeContainer(env);
      await online.read(tasksProvider.future);
      online.dispose();

      final env2 = TestEnv(database: env.db);
      env2.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env2);
      addTearDown(c.dispose);

      final snap = await c.read(tasksProvider.future);
      expect(snap.fromCache, isTrue);
      expect(snap.tasks.single.id, 'a');
      expect(snap.fetchedAt, isNotNull);
    });

    test('with no connection and nothing saved it is an error', () async {
      env.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await expectLater(
        c.read(tasksProvider.future),
        throwsA(isA<AppException>()),
      );
    });

    test('queued changes + no connection: saved list at once, no second doomed request', () async {
      env.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.json([taskJson(id: 'a')]),
      );
      final online = makeContainer(env);
      await online.read(tasksProvider.future);
      online.dispose();
      await env.db.enqueue(
        id: 'op1',
        userId: 'u1',
        kind: 'task_status',
        targetId: 'a',
        payload: '{"status":"DONE"}',
      );

      final env2 = TestEnv(database: env.db);
      env2.adapter
        ..on(
          'PUT',
          'tasks/a/status',
          (_) => Reply.fail(DioExceptionType.connectionError),
        )
        ..on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson(id: 'a')]));
      final c = makeContainer(env2);
      addTearDown(c.dispose);

      final snap = await c.read(tasksProvider.future);

      expect(snap.fromCache, isTrue);
      expect(
        env2.adapter.count('GET', 'tasks/my-queue'),
        0,
        reason: 'must not wait out another timeout',
      );
      expect((await env.db.outboxFor('u1')).single.status, 'pending');
    });

    test(
      'a refused queued change does not block fetching fresh data',
      () async {
        env.adapter
          ..on(
            'PUT',
            'tasks/a/status',
            (_) => Reply.json({
              'statusCode': 404,
              'message': 'Task not found',
            }, status: 404),
          )
          ..on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson(id: 'b')]));
        await env.db.enqueue(
          id: 'op1',
          userId: 'u1',
          kind: 'task_status',
          targetId: 'a',
          payload: '{"status":"DONE"}',
        );
        final c = makeContainer(env);
        addTearDown(c.dispose);

        final snap = await c.read(tasksProvider.future);
        expect(snap.fromCache, isFalse);
        expect(snap.tasks.single.id, 'b');
      },
    );

    test('a refusal (403) is an error even when a cache exists', () async {
      env.adapter.on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson()]));
      final online = makeContainer(env);
      await online.read(tasksProvider.future);
      online.dispose();

      final env2 = TestEnv(database: env.db);
      env2.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env2);
      addTearDown(c.dispose);
      await expectLater(
        c.read(tasksProvider.future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
    });

    test("one worker's saved tasks are never shown to another user", () async {
      await env.db.replaceCache('someone-else', 'task', [
        (key: 'x', json: '{"id":"x","title":"Secret"}'),
      ]);
      env.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await expectLater(
        c.read(tasksProvider.future),
        throwsA(isA<AppException>()),
      );
    });

    test(
      'work projects are the distinct projects of the assigned tasks',
      () async {
        env.adapter.on(
          'GET',
          'tasks/my-queue',
          (_) => Reply.json([
            taskJson(id: 'a', projectId: 'p2', projectName: 'Borrowdale'),
            taskJson(id: 'b', projectId: 'p1'),
            taskJson(id: 'c', projectId: 'p2', projectName: 'Borrowdale'),
          ]),
        );
        final c = makeContainer(env);
        addTearDown(c.dispose);
        await c.read(tasksProvider.future);

        // Sorted by label: Borrowdale before Harare Tower.
        expect(c.read(workProjectsProvider).map((p) => p.id), ['p2', 'p1']);
      },
    );
  });

  group('changing status', () {
    test('online: sent to the server and reflected in the list', () async {
      env.adapter
        ..on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson(id: 'a')]))
        ..on(
          'PUT',
          'tasks/a/status',
          (_) => Reply.json(taskJson(id: 'a', status: 'IN_PROGRESS')),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(tasksProvider.future);

      final outcome = await c
          .read(taskActionsProvider)
          .setStatus('a', 'IN_PROGRESS');

      expect(outcome, StatusOutcome.sent);
      expect(env.adapter.last('PUT', 'tasks/a/status').data, {
        'status': 'IN_PROGRESS',
      });
      expect(c.read(tasksProvider).value!.tasks.single.status, 'IN_PROGRESS');
      expect(await env.db.outboxFor('u1'), isEmpty);
    });

    test('offline: saved on the phone, shown at once, sent later', () async {
      env.adapter
        ..on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson(id: 'a')]))
        ..on(
          'PUT',
          'tasks/a/status',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(tasksProvider.future);

      final outcome = await c.read(taskActionsProvider).setStatus('a', 'DONE');

      expect(outcome, StatusOutcome.queued);
      expect(c.read(tasksProvider).value!.tasks.single.status, 'DONE');
      final ops = await env.db.outboxFor('u1');
      expect(ops.single.targetId, 'a');
      expect(ops.single.status, 'pending');
    });

    test('a refusal is shown at once and is NOT queued', () async {
      env.adapter
        ..on('GET', 'tasks/my-queue', (_) => Reply.json([taskJson(id: 'a')]))
        ..on(
          'PUT',
          'tasks/a/status',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(tasksProvider.future);

      await expectLater(
        c.read(taskActionsProvider).setStatus('a', 'DONE'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(await env.db.outboxFor('u1'), isEmpty);
      expect(c.read(tasksProvider).value!.tasks.single.status, 'TODO');
    });

    test('flush sends queued changes oldest first and clears them', () async {
      env.adapter
        ..on('PUT', 'tasks/a/status', (_) => Reply.json({}))
        ..on('PUT', 'tasks/b/status', (_) => Reply.json({}));
      final c = makeContainer(env);
      addTearDown(c.dispose);
      final outbox = c.read(taskOutboxProvider)!;
      await outbox.queue('a', 'DONE');
      await outbox.queue('b', 'BLOCKED');

      final sent = await outbox.flush();

      expect(sent, 2);
      expect(env.adapter.requests.map((r) => r.path), [
        'tasks/a/status',
        'tasks/b/status',
      ]);
      expect(await env.db.outboxFor('u1'), isEmpty);
    });

    test(
      'queuing twice for the same task keeps only the latest status',
      () async {
        final c = makeContainer(env);
        addTearDown(c.dispose);
        final outbox = c.read(taskOutboxProvider)!;
        await outbox.queue('a', 'IN_PROGRESS');
        await outbox.queue('a', 'DONE');
        final ops = await env.db.outboxFor('u1');
        expect(ops.length, 1);
        expect(ops.single.payload, contains('DONE'));
      },
    );

    test(
      'flush stops at the first network failure and keeps everything queued',
      () async {
        env.adapter
          ..on(
            'PUT',
            'tasks/a/status',
            (_) => Reply.fail(DioExceptionType.connectionError),
          )
          ..on('PUT', 'tasks/b/status', (_) => Reply.json({}));
        final c = makeContainer(env);
        addTearDown(c.dispose);
        final outbox = c.read(taskOutboxProvider)!;
        await outbox.queue('a', 'DONE');
        await outbox.queue('b', 'DONE');

        expect(await outbox.flush(), 0);
        expect(env.adapter.count('PUT', 'tasks/b/status'), 0);
        final ops = await env.db.outboxFor('u1');
        expect(ops.map((o) => o.status), ['pending', 'pending']);
        expect(ops.first.attempts, 1);
      },
    );

    test(
      'a refused change is marked failed (and skipped), the rest still go',
      () async {
        env.adapter
          ..on(
            'PUT',
            'tasks/a/status',
            (_) => Reply.json({
              'statusCode': 404,
              'message': 'Task not found',
            }, status: 404),
          )
          ..on('PUT', 'tasks/b/status', (_) => Reply.json({}));
        final c = makeContainer(env);
        addTearDown(c.dispose);
        final outbox = c.read(taskOutboxProvider)!;
        await outbox.queue('a', 'DONE');
        await outbox.queue('b', 'DONE');

        expect(await outbox.flush(), 1);
        final ops = await env.db.outboxFor('u1');
        expect(ops.single.targetId, 'a');
        expect(ops.single.status, 'failed');
        expect(ops.single.lastError, contains('not found'));
      },
    );

    test('pending overlay shows the offline status on top of the server one', () async {
      env.adapter.on(
        'GET',
        'tasks/my-queue',
        (_) => Reply.json([taskJson(id: 'a')]),
      );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(tasksProvider.future);
      // Riverpod pauses a stream provider nobody listens to; widgets watch it.
      c.listen(queuedStatusOpsProvider, (_, _) {});
      await c.read(taskOutboxProvider)!.queue('a', 'BLOCKED');
      await pumpEventQueue(
        times: 50,
      ); // let the database stream deliver the change

      final task = c.read(tasksProvider).value!.tasks.single;
      final shown = withPendingStatus(task, c.read(pendingStatusProvider));
      expect(shown.status, 'BLOCKED');
    });
  });

  group('task detail', () {
    Map<String, dynamic> detail({List<Map<String, dynamic>>? checklists}) =>
        taskJson(
          id: 'a',
          checklists: checklists ?? [checklistJson()],
          comments: [
            {
              'id': 'cm1',
              'content': 'Rebar delivered',
              'createdAt': _iso(DateTime(2026, 10, 25, 9)),
              'user': {'id': 'u2', 'firstName': 'Rudo', 'lastName': 'Banda'},
            },
          ],
        );

    test('loads the task with comments and attachments', () async {
      env.adapter
        ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
        ..on(
          'GET',
          'tasks/a/attachments',
          (_) => Reply.json([
            {
              'id': 'at1',
              'fileName': 'slab.jpg',
              'contentType': 'image/jpeg',
              'sizeBytes': 120000,
            },
          ]),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);

      final s = await c.read(taskDetailProvider('a').future);
      expect(s.task.comments.single.authorName, 'Rudo Banda');
      expect(s.attachments.single.isImage, isTrue);
      expect(s.fromCache, isFalse);
    });

    test('a failing attachment list does not hide the task', () async {
      env.adapter
        ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
        ..on(
          'GET',
          'tasks/a/attachments',
          (_) => Reply.json({'statusCode': 500}, status: 500),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      final s = await c.read(taskDetailProvider('a').future);
      expect(s.task.title, 'Pour slab');
      expect(s.attachments, isEmpty);
    });

    test('offline falls back to the saved copy', () async {
      env.adapter
        ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
        ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]));
      final online = makeContainer(env);
      await online.read(taskDetailProvider('a').future);
      online.dispose();

      final env2 = TestEnv(database: env.db);
      env2.adapter
        ..on(
          'GET',
          'tasks/a',
          (_) => Reply.fail(DioExceptionType.connectionError),
        )
        ..on(
          'GET',
          'tasks/a/attachments',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
      final c = makeContainer(env2);
      addTearDown(c.dispose);
      final s = await c.read(taskDetailProvider('a').future);
      expect(s.fromCache, isTrue);
      expect(s.task.comments, hasLength(1));
    });

    test(
      'toggling a checklist item shows at once and calls the server once',
      () async {
        env.adapter
          ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
          ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]))
          ..on(
            'PUT',
            'tasks/a/checklists/cl1/items/i1/toggle',
            (_) => Reply.json({}),
          );
        final c = makeContainer(env);
        addTearDown(c.dispose);
        await c.read(taskDetailProvider('a').future);

        await c.read(taskDetailProvider('a').notifier).toggleItem('cl1', 'i1');

        final item = c
            .read(taskDetailProvider('a'))
            .value!
            .task
            .checklists
            .single
            .items
            .first;
        expect(item.isDone, isTrue);
        expect(
          env.adapter.count('PUT', 'tasks/a/checklists/cl1/items/i1/toggle'),
          1,
        );
      },
    );

    test('a refused toggle is undone', () async {
      env.adapter
        ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
        ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]))
        ..on(
          'PUT',
          'tasks/a/checklists/cl1/items/i1/toggle',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(taskDetailProvider('a').future);

      await expectLater(
        c.read(taskDetailProvider('a').notifier).toggleItem('cl1', 'i1'),
        throwsA(isA<AppException>()),
      );
      expect(
        c
            .read(taskDetailProvider('a'))
            .value!
            .task
            .checklists
            .single
            .items
            .first
            .isDone,
        isFalse,
      );
    });

    test(
      'after a timed-out toggle the server state is re-read, never re-sent',
      () async {
        env.adapter
          ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
          ..on(
            'GET',
            'tasks/a',
            (_) => Reply.json(
              detail(
                checklists: [
                  checklistJson(
                    items: [
                      {'id': 'i1', 'content': 'Wear hard hat', 'isDone': true},
                      {
                        'id': 'i2',
                        'content': 'Check scaffolding',
                        'isDone': true,
                      },
                    ],
                  ),
                ],
              ),
            ),
          )
          ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]))
          ..on(
            'PUT',
            'tasks/a/checklists/cl1/items/i1/toggle',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
        final c = makeContainer(env);
        addTearDown(c.dispose);
        await c.read(taskDetailProvider('a').future);

        await expectLater(
          c.read(taskDetailProvider('a').notifier).toggleItem('cl1', 'i1'),
          throwsA(isA<AppException>()),
        );
        expect(
          env.adapter.count('PUT', 'tasks/a/checklists/cl1/items/i1/toggle'),
          1,
        );
        expect(
          c
              .read(taskDetailProvider('a'))
              .value!
              .task
              .checklists
              .single
              .items
              .first
              .isDone,
          isTrue,
        );
      },
    );

    test('toggling an item that is no longer there does nothing (no crash, no request)', () async {
      env.adapter
        ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
        ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]));
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(taskDetailProvider('a').future);

      await c.read(taskDetailProvider('a').notifier).toggleItem('cl1', 'gone');
      await c.read(taskDetailProvider('a').notifier).toggleItem('nope', 'i1');

      expect(
        env.adapter.requests.where((r) => r.path.contains('toggle')),
        isEmpty,
      );
    });

    test('adding a comment appends it', () async {
      env.adapter
        ..on('GET', 'tasks/a', (_) => Reply.json(detail()))
        ..on('GET', 'tasks/a/attachments', (_) => Reply.json([]))
        ..on(
          'POST',
          'tasks/a/comments',
          (_) => Reply.json({
            'id': 'cm2',
            'content': 'On it',
            'createdAt': _iso(DateTime.now()),
            'user': {'id': 'u1', 'firstName': 'Tendai', 'lastName': 'Moyo'},
          }, status: 201),
        );
      final c = makeContainer(env);
      addTearDown(c.dispose);
      await c.read(taskDetailProvider('a').future);

      await c.read(taskDetailProvider('a').notifier).addComment('  On it  ');

      expect(env.adapter.last('POST', 'tasks/a/comments').data, {
        'content': 'On it',
      });
      expect(
        c
            .read(taskDetailProvider('a'))
            .value!
            .task
            .comments
            .map((x) => x.content),
        ['Rebar delivered', 'On it'],
      );
    });
  });
}
