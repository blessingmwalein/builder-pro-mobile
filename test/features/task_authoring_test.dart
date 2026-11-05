import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/tasks/application/task_authoring.dart';
import 'package:builder_pro_mobile/features/tasks/presentation/task_form_screen.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

NewTaskInput _input({String title = 'Fix railing'}) =>
    NewTaskInput(projectId: 'p1', title: title);

Map<String, dynamic> _created({
  String id = 'new1',
  String title = 'Fix railing',
  DateTime? at,
}) => {
  ...taskJson(id: id, title: title),
  'createdAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
};

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('form validation', () {
    test('title is required and limited', () {
      expect(validateTitle(''), isNotNull);
      expect(validateTitle('   '), isNotNull);
      expect(validateTitle('Fix railing'), isNull);
      expect(validateTitle('x' * 201), isNotNull);
      expect(validateTitle('x' * 200), isNull);
    });

    test('hours are optional, positive, sane and at most 2 decimals', () {
      expect(validateHours(''), isNull);
      expect(validateHours('  '), isNull);
      expect(validateHours('8'), isNull);
      expect(validateHours('2,5'), isNull);
      expect(validateHours('0.25'), isNull);
      expect(validateHours('abc'), isNotNull);
      expect(validateHours('0'), isNotNull);
      expect(validateHours('-1'), isNotNull);
      expect(validateHours('10001'), isNotNull);
      expect(validateHours('1.234'), isNotNull);
    });

    test(
      'a due date is sent as noon local so it stays on the same calendar day',
      () {
        final due = dueInstant(DateTime(2026, 11, 5));
        expect(due.hour, 12);
        expect(due.toUtc().toLocal().day, 5);
        expect(
          dueInstant(DateTime(2026, 11, 5, 23, 59)),
          DateTime(2026, 11, 5, 12),
        );
      },
    );
  });

  group('create', () {
    test('sends only what was filled in, with a noon due date and string-free numbers', () async {
      env.adapter.on(
        'POST',
        'tasks',
        (_) => Reply.json(_created(), status: 201),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      final r = await c
          .read(taskAuthoringProvider)
          .create(
            NewTaskInput(
              projectId: 'p1',
              title: 'Fix railing',
              description: 'Block B stairs',
              priority: 'HIGH',
              dueDate: dueInstant(DateTime(2026, 11, 5)),
              estimatedHours: 2.5,
              assigneeIds: const ['u2', 'u3'],
            ),
          );

      final body = env.adapter.last('POST', 'tasks').data as Map;
      expect(body['projectId'], 'p1');
      expect(body['title'], 'Fix railing');
      expect(body['description'], 'Block B stairs');
      expect(body['priority'], 'HIGH');
      expect(body['estimatedHours'], 2.5);
      expect(body['assigneeIds'], ['u2', 'u3']);
      expect(DateTime.parse(body['dueDate'] as String).toLocal().hour, 12);
      expect(r.note, isNull);
      expect(r.task.id, 'new1');
    });

    test('a bare task sends no optional fields', () async {
      env.adapter.on(
        'POST',
        'tasks',
        (_) => Reply.json(_created(), status: 201),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      await c.read(taskAuthoringProvider).create(_input());

      expect(env.adapter.last('POST', 'tasks').data, {
        'projectId': 'p1',
        'title': 'Fix railing',
        'priority': 'MEDIUM',
      });
    });

    test(
      'a validation error from the server is shown and nothing else is tried',
      () async {
        env.adapter.on(
          'POST',
          'tasks',
          (_) => Reply.json({
            'statusCode': 400,
            'message': ['title must be a string'],
          }, status: 400),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);

        await expectLater(
          c.read(taskAuthoringProvider).create(_input()),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.validation,
            ),
          ),
        );
        expect(env.adapter.count('POST', 'tasks'), 1);
        expect(env.adapter.requests.where((r) => r.method == 'GET'), isEmpty);
      },
    );

    test('a refusal (403) is shown, never retried', () async {
      env.adapter.on(
        'POST',
        'tasks',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        c.read(taskAuthoringProvider).create(_input()),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(env.adapter.count('POST', 'tasks'), 1);
    });

    test(
      'no connection: plain offline error, nothing queued, no second POST',
      () async {
        env.adapter.on(
          'POST',
          'tasks',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(taskAuthoringProvider).create(_input()),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.offline,
            ),
          ),
        );
        expect(env.adapter.count('POST', 'tasks'), 1);
        expect(await env.db.outboxFor('u1'), isEmpty);
      },
    );

    group('after a timeout the project is checked before anything else', () {
      test(
        'created: found by title and time; shown as done; exactly one POST',
        () async {
          env.adapter
            ..on(
              'POST',
              'tasks',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              'tasks',
              (_) => Reply.json(paged([_created(id: 'found')], limit: 100)),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);

          final r = await c.read(taskAuthoringProvider).create(_input());

          expect(r.task.id, 'found');
          expect(r.note, contains('created'));
          expect(env.adapter.count('POST', 'tasks'), 1);
          final q = env.adapter.last('GET', 'tasks').query;
          expect(q['projectId'], 'p1');
          expect(q['status'], 'TODO');
        },
      );

      test(
        'an OLD task with the same title is not mistaken for the new one',
        () async {
          env.adapter
            ..on(
              'POST',
              'tasks',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              'tasks',
              (_) => Reply.json(
                paged([
                  _created(
                    id: 'old',
                    at: DateTime.now().subtract(const Duration(days: 3)),
                  ),
                ], limit: 100),
              ),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);

          await expectLater(
            c.read(taskAuthoringProvider).create(_input()),
            throwsA(
              isA<AppException>().having(
                (e) => e.message,
                'message',
                contains('no task was created'),
              ),
            ),
          );
        },
      );

      test('not created: a clear message and a safe retry', () async {
        env.adapter
          ..on(
            'POST',
            'tasks',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on('GET', 'tasks', (_) => Reply.json(paged([], limit: 100)));
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(taskAuthoringProvider).create(_input()),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              contains('no task was created'),
            ),
          ),
        );
        expect(env.adapter.count('POST', 'tasks'), 1);
      });

      test(
        'too many open tasks to be sure: says so instead of guessing',
        () async {
          env.adapter
            ..on(
              'POST',
              'tasks',
              (_) => Reply.fail(DioExceptionType.receiveTimeout),
            )
            ..on(
              'GET',
              'tasks',
              (_) => Reply.json(
                paged(
                  [_created(id: 'x', title: 'Other')],
                  limit: 100,
                  total: 450,
                ),
              ),
            );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            c.read(taskAuthoringProvider).create(_input()),
            throwsA(
              isA<AppException>().having(
                (e) => e.message,
                'message',
                contains('could not tell'),
              ),
            ),
          );
        },
      );

      test('the check also fails: the outcome stays unknown', () async {
        env.adapter
          ..on(
            'POST',
            'tasks',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            'tasks',
            (_) => Reply.fail(DioExceptionType.connectionError),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(taskAuthoringProvider).create(_input()),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
      });
    });
  });

  group('edit', () {
    test('sends the changed fields; blank description clears; no due date means leave it', () async {
      env.adapter.on('PUT', 'tasks/a', (_) => Reply.json({}));
      env.adapter.on('GET', 'tasks/my-queue', (_) => Reply.json([]));
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);

      await c
          .read(taskAuthoringProvider)
          .update(
            'a',
            title: 'New title',
            description: '',
            priority: 'CRITICAL',
            estimatedHours: 3,
          );

      expect(env.adapter.last('PUT', 'tasks/a').data, {
        'title': 'New title',
        'description': '',
        'priority': 'CRITICAL',
        'estimatedHours': 3.0,
      });
    });

    test('a due date is sent as an instant', () async {
      env.adapter.on('PUT', 'tasks/a', (_) => Reply.json({}));
      env.adapter.on('GET', 'tasks/my-queue', (_) => Reply.json([]));
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await c
          .read(taskAuthoringProvider)
          .update('a', dueDate: dueInstant(DateTime(2026, 12, 1)));
      final body = env.adapter.last('PUT', 'tasks/a').data as Map;
      expect(DateTime.parse(body['dueDate'] as String).toLocal().day, 1);
    });

    test('a timed-out edit is sent once more (it only sets fields) and then succeeds', () async {
      env.adapter
        ..on(
          'PUT',
          'tasks/a',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on('PUT', 'tasks/a', (_) => Reply.json({}))
        ..on('GET', 'tasks/my-queue', (_) => Reply.json([]));
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await c.read(taskAuthoringProvider).update('a', title: 'X');
      expect(env.adapter.count('PUT', 'tasks/a'), 2);
    });

    test(
      'if the retry also times out it is reported, with no third attempt',
      () async {
        env.adapter.on(
          'PUT',
          'tasks/a',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          c.read(taskAuthoringProvider).update('a', title: 'X'),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        expect(env.adapter.count('PUT', 'tasks/a'), 2);
      },
    );

    test('a refusal (403) is shown at once and not retried', () async {
      env.adapter.on(
        'PUT',
        'tasks/a',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(
        c.read(taskAuthoringProvider).update('a', title: 'X'),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(env.adapter.count('PUT', 'tasks/a'), 1);
    });
  });
}
