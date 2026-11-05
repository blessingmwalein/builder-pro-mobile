import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/projects/application/projects_providers.dart';
import 'package:builder_pro_mobile/features/projects/data/project_models.dart';
import 'package:builder_pro_mobile/features/tasks/data/task_list_repository.dart';
import 'package:builder_pro_mobile/features/tasks/data/task_models.dart';
import 'package:builder_pro_mobile/features/today/application/today_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('parsing', () {
    test('reads progress, client, counts and team', () {
      final p = ProjectSummary.tryParse(projectJson(members: [memberJson()]))!;
      expect(p.label, 'HT-01 · Harare Tower');
      expect(p.completionPercent, 40);
      expect(p.clientName, 'Zim Properties');
      expect(p.clientContact, 'Chipo Dube');
      expect(p.taskCount, 12);
      expect(p.memberCount, 3);
      expect(p.members.single.name, 'Rudo Banda');
      expect(p.members.single.role, 'Foreman');
    });

    test('budget and cost sent by the API are never exposed', () {
      final p = ProjectSummary.tryParse(projectJson())!;
      final dump = [
        p.toString(),
        p.name,
        p.description,
        p.clientEmail,
      ].join(' ');
      expect(dump, isNot(contains('2500000')));
      expect(dump, isNot(contains('812000')));
    });

    test('progress is clamped to 0..100 and bad rows are skipped', () {
      expect(
        ProjectSummary.tryParse(projectJson(completion: 140))!
            .completionPercent,
        100,
      );
      expect(
        ProjectSummary.tryParse(projectJson(completion: -5))!.completionPercent,
        0,
      );
      expect(ProjectSummary.tryParse({'name': 'no id'}), isNull);
      expect(ProjectSummary.tryParse(null), isNull);
    });

    test('a member without a name falls back to the email', () {
      final p = PersonRef.tryParse({
        'user': {'id': 'u9', 'email': 'a@b.test'},
      })!;
      expect(p.name, 'a@b.test');
    });
  });

  group('list', () {
    test(
      'always sends page and limit; search and status only when set',
      () async {
        env.adapter.on(
          'GET',
          'projects',
          (_) => Reply.json(paged([projectJson()], limit: 20)),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        c.listen(projectsCatalogProvider, (_, _) {});
        await pumpEventQueue(times: 20);

        var q = env.adapter.last('GET', 'projects').query;
        expect(q['page'], 1);
        expect(q['limit'], 20);
        expect(q.containsKey('search'), isFalse);
        expect(q.containsKey('status'), isFalse);

        await c.read(projectsCatalogProvider.notifier).setStatus('ACTIVE');
        await c.read(projectsCatalogProvider.notifier).search('tower');
        q = env.adapter.last('GET', 'projects').query;
        expect(q['status'], 'ACTIVE');
        expect(q['search'], 'tower');
        expect(c.read(projectsCatalogProvider).items, hasLength(1));
      },
    );

    test('a newer filter wins over a slow older reply', () async {
      env.adapter
        ..on('GET', 'projects', (_) => Reply.json(paged([])))
        ..on(
          'GET',
          'projects',
          (_) => Reply.json(
            paged([projectJson(id: 'old', name: 'Old')]),
            delay: const Duration(milliseconds: 300),
          ),
        )
        ..on(
          'GET',
          'projects',
          (_) => Reply.json(paged([projectJson(id: 'new', name: 'New')])),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectsCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);

      final n = c.read(projectsCatalogProvider.notifier);
      await Future.wait([n.setStatus('ON_HOLD'), n.setStatus('ACTIVE')]);

      expect(c.read(projectsCatalogProvider).items.map((p) => p.id), ['new']);
      expect(c.read(projectsCatalogProvider).status, 'ACTIVE');
    });

    test('load more appends without duplicates', () async {
      env.adapter
        ..on(
          'GET',
          'projects',
          (_) => Reply.json(paged([projectJson(id: 'a')], limit: 1, total: 2)),
        )
        ..on(
          'GET',
          'projects',
          (_) => Reply.json(
            paged(
              [projectJson(id: 'a'), projectJson(id: 'b')],
              page: 2,
              limit: 1,
              total: 2,
            ),
          ),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectsCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      await c.read(projectsCatalogProvider.notifier).loadMore();
      expect(c.read(projectsCatalogProvider).items.map((p) => p.id), [
        'a',
        'b',
      ]);
    });

    test('a failed load is an error state, not "no projects"', () async {
      env.adapter.on(
        'GET',
        'projects',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectsCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      final s = c.read(projectsCatalogProvider);
      expect(s.error?.kind, AppErrorKind.offline);
      expect(s.loading, isFalse);
    });
  });

  group('detail and tasks', () {
    test('detail includes the team', () async {
      env.adapter.on(
        'GET',
        'projects/p1',
        (_) => Reply.json(
          projectJson(
            members: [
              memberJson(),
              memberJson(id: 'u3', first: 'Farai', last: 'Ncube', role: null),
            ],
          ),
        ),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectDetailProvider('p1'), (_, _) {});
      final p = await c.read(projectDetailProvider('p1').future);
      expect(p.members.map((m) => m.name), ['Rudo Banda', 'Farai Ncube']);
    });

    test('a malformed detail reply is an error, not a blank screen', () async {
      env.adapter.on(
        'GET',
        'projects/p1',
        (_) => Reply.json({'unexpected': true}),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectDetailProvider('p1'), (_, _) {});
      await expectLater(
        c.read(projectDetailProvider('p1').future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.malformed,
          ),
        ),
      );
    });

    test('a missing project (404) is reported as not found', () async {
      env.adapter.on(
        'GET',
        'projects/zzz',
        (_) => Reply.json({
          'statusCode': 404,
          'message': 'Project not found',
        }, status: 404),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectDetailProvider('zzz'), (_, _) {});
      await expectLater(
        c.read(projectDetailProvider('zzz').future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.notFound,
          ),
        ),
      );
    });

    test('project tasks are requested by projectId with a limit, and report truncation', () async {
      env.adapter.on(
        'GET',
        'tasks',
        (_) => Reply.json(
          paged([taskJson(id: 'a'), taskJson(id: 'b')], limit: 100, total: 250),
        ),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectTasksProvider('p1'), (_, _) {});
      final page = await c.read(projectTasksProvider('p1').future);

      final q = env.adapter.last('GET', 'tasks').query;
      expect(q['projectId'], 'p1');
      expect(q['limit'], 100);
      expect(q['page'], 1);
      expect(page.items, hasLength(2));
      expect(page.total, 250);
      expect(page.truncated, isTrue);
    });
  });

  group('open tasks (Today)', () {
    test('reads each open status separately and merges them', () async {
      env.adapter.on('GET', 'tasks', (o) {
        final status = o.queryParameters['status'];
        return Reply.json(
          paged([taskJson(id: 'task-$status', status: '$status')], limit: 100),
        );
      });
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      final repo = c.read(taskListRepositoryProvider);

      final open = await repo.open();

      final statuses = env.adapter.requests
          .where((r) => r.path == 'tasks')
          .map((r) => r.query['status'])
          .toSet();
      expect(statuses, {'TODO', 'IN_PROGRESS', 'BLOCKED', 'REVIEW'});
      expect(statuses.contains('DONE'), isFalse);
      expect(open.tasks, hasLength(4));
      expect(open.truncated, isFalse);
    });

    test(
      'flags truncation when a status has more tasks than were loaded',
      () async {
        env.adapter.on(
          'GET',
          'tasks',
          (o) => Reply.json(
            paged(
              [taskJson(id: 'x${o.queryParameters['status']}')],
              limit: 100,
              total: o.queryParameters['status'] == 'TODO' ? 500 : 1,
            ),
          ),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        expect(
          (await c.read(taskListRepositoryProvider).open()).truncated,
          isTrue,
        );
      },
    );

    test(
      'one failing status fails the whole read (no half-complete overview)',
      () async {
        env.adapter.on(
          'GET',
          'tasks',
          (o) => o.queryParameters['status'] == 'BLOCKED'
              ? Reply.fail(DioExceptionType.connectionError)
              : Reply.json(paged([taskJson()])),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(taskListRepositoryProvider).open(),
          throwsA(isA<AppException>()),
        );
      },
    );

    test('overdue, due today and blocked are split correctly', () {
      final now = DateTime(2026, 10, 26, 12);
      String iso(DateTime d) => d.toUtc().toIso8601String();
      final tasks = OpenTasks([
        for (final (id, status, due) in [
          ('late', 'IN_PROGRESS', DateTime(2026, 10, 20, 12)),
          ('today', 'TODO', DateTime(2026, 10, 26, 16)),
          ('later', 'TODO', DateTime(2026, 11, 3, 12)),
          ('stuck', 'BLOCKED', DateTime(2026, 10, 25, 12)),
        ])
          TaskItem.tryParse(
            taskJson(id: id, status: status, dueDate: iso(due)),
          )!,
      ], truncated: false);

      expect(tasks.overdue(now).map((t) => t.id), ['late', 'stuck']);
      expect(tasks.dueToday(now).map((t) => t.id), ['today']);
      expect(tasks.blocked.map((t) => t.id), ['stuck']);
    });
  });
}
