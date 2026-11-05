import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/stages/application/stages_providers.dart';
import 'package:builder_pro_mobile/features/stages/data/stage_models.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

Matcher _fails(AppErrorKind kind, {String? containing}) => isA<AppException>()
    .having((e) => e.kind, 'kind', kind)
    .having((e) => e.message, 'message', contains(containing ?? ''));

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('models', () {
    test('a stage reads its name, status, calendar days and approver', () {
      final s = ProjectStage.tryParse(
        stageJson(
          status: 'COMPLETED',
          requiresApproval: true,
          plannedStart: DateTime.utc(2026, 10, 1),
          plannedEnd: DateTime.utc(2026, 10, 20),
          actualStart: DateTime.utc(2026, 10, 2),
          actualEnd: DateTime.utc(2026, 10, 21),
          approvedBy: 'Chipo Dube',
          approvedAt: DateTime.utc(2026, 10, 21, 8),
          notes: 'Signed off',
        ),
      )!;
      expect(s.name, 'Site survey');
      expect(s.workflowCode, 'PLANNING');
      expect(s.isCompleted, isTrue);
      expect(s.isFinished, isTrue);
      expect(s.requiresApproval, isTrue);
      expect(s.awaitsApproval, isFalse);
      expect(s.plannedStart, DateTime.utc(2026, 10, 1));
      expect(s.actualEnd, DateTime.utc(2026, 10, 21));
      expect(s.approvedBy, 'Chipo Dube');
      expect(s.notes, 'Signed off');
    });

    test('a stage that needs approval and is not completed awaits it', () {
      final s = ProjectStage.tryParse(
        stageJson(status: 'IN_PROGRESS', requiresApproval: true),
      )!;
      expect(s.awaitsApproval, isTrue);
      expect(s.isFinished, isFalse);
    });

    test('completed and skipped stages are finished, the rest are not', () {
      for (final e in {
        'PENDING': false,
        'IN_PROGRESS': false,
        'BLOCKED': false,
        'COMPLETED': true,
        'SKIPPED': true,
      }.entries) {
        expect(
          ProjectStage.tryParse(stageJson(status: e.key))!.isFinished,
          e.value,
          reason: e.key,
        );
      }
    });

    test('rows without an id or a name are skipped', () {
      expect(ProjectStage.tryParse({'stageName': 'x'}), isNull);
      expect(ProjectStage.tryParse({'id': 's1'}), isNull);
    });

    test('workflow codes read as plain words', () {
      expect(workflowLabel('PROJECT_INITIATION'), 'Project initiation');
      expect(workflowLabel('EXECUTION'), 'Execution');
      expect(workflowLabel(' handover  '), 'Handover');
      expect(workflowLabel(''), 'Stages');
    });

    test('stages are grouped by workflow and kept in stage order', () {
      final groups = groupStages([
        for (final j in [
          stageJson(id: 'b2', code: 'PLANNING', order: 2, name: 'Design'),
          stageJson(id: 'a1', code: 'EXECUTION', order: 1, name: 'Dig'),
          stageJson(id: 'b1', code: 'PLANNING', order: 1, name: 'Survey'),
        ])
          ProjectStage.tryParse(j)!,
      ]);
      expect(groups.map((g) => g.code), ['EXECUTION', 'PLANNING']);
      expect(groups[1].stages.map((s) => s.name), ['Survey', 'Design']);
      expect(groups[1].label, 'Planning');
    });
  });

  group('reading', () {
    test('the stages come from one plain array', () async {
      env.adapter.on(
        'GET',
        'projects/p1/stages',
        (_) => Reply.json([
          stageJson(),
          stageJson(id: 's2', name: 'Design', order: 2),
        ]),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectStagesProvider('p1'), (_, _) {});
      final list = await c.read(projectStagesProvider('p1').future);
      expect(list.map((s) => s.name), ['Site survey', 'Design']);
    });

    test('a refusal is an error, not an empty list', () async {
      env.adapter.on(
        'GET',
        'projects/p1/stages',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectStagesProvider('p1'), (_, _) {});
      await expectLater(
        c.read(projectStagesProvider('p1').future),
        throwsA(_fails(AppErrorKind.forbidden)),
      );
    });
  });

  group('changing a status', () {
    Future<void> setStatus(dynamic c) => c
        .read(stageActionsProvider)
        .setStatus('p1', 's1', StageStatus.inProgress);

    test('sends only the status, once', () async {
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s1',
        (_) => Reply.json(stageJson()),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await setStatus(c);
      expect(env.adapter.count('PATCH', 'projects/p1/stages/s1'), 1);
      expect(env.adapter.last('PATCH', 'projects/p1/stages/s1').data, {
        'status': 'IN_PROGRESS',
      });
    });

    test(
      'after an uncertain failure it is sent once more, and then succeeds',
      () async {
        env.adapter
          ..on(
            'PATCH',
            'projects/p1/stages/s1',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'PATCH',
            'projects/p1/stages/s1',
            (_) => Reply.json(stageJson()),
          );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await setStatus(c);
        expect(env.adapter.count('PATCH', 'projects/p1/stages/s1'), 2);
      },
    );

    test('a second failure is reported, never a third send', () async {
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s1',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(setStatus(c), throwsA(isA<AppException>()));
      expect(env.adapter.count('PATCH', 'projects/p1/stages/s1'), 2);
    });

    test('a refusal (403) is shown and never retried', () async {
      env.adapter.on(
        'PATCH',
        'projects/p1/stages/s1',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      await expectLater(setStatus(c), throwsA(_fails(AppErrorKind.forbidden)));
      expect(env.adapter.count('PATCH', 'projects/p1/stages/s1'), 1);
    });

    test('a change reloads the stages', () async {
      env.adapter
        ..on('GET', 'projects/p1/stages', (_) => Reply.json([stageJson()]))
        ..on('PATCH', 'projects/p1/stages/s1', (_) => Reply.json(stageJson()));
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectStagesProvider('p1'), (_, _) {});
      await c.read(projectStagesProvider('p1').future);
      expect(env.adapter.count('GET', 'projects/p1/stages'), 1);

      await setStatus(c);
      await pumpEventQueue(times: 20);

      expect(env.adapter.count('GET', 'projects/p1/stages'), 2);
    });
  });

  group('approving', () {
    Future<String?> approve(dynamic c) =>
        c.read(stageActionsProvider).approve('p1', 's1');

    test('a recorded approval reloads the stages', () async {
      env.adapter
        ..on('GET', 'projects/p1/stages', (_) => Reply.json([stageJson()]))
        ..on(
          'POST',
          'projects/p1/stages/s1/approve',
          (_) => Reply.json(stageJson(status: 'COMPLETED'), status: 201),
        );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      c.listen(projectStagesProvider('p1'), (_, _) {});
      await c.read(projectStagesProvider('p1').future);

      await approve(c);
      await pumpEventQueue(times: 20);

      expect(env.adapter.count('GET', 'projects/p1/stages'), 2);
    });

    test('sends one approval', () async {
      env.adapter.on(
        'POST',
        'projects/p1/stages/s1/approve',
        (_) => Reply.json(stageJson(status: 'COMPLETED'), status: 201),
      );
      final c = makeContainer(env, perms: supervisorPerms);
      addTearDown(c.dispose);
      expect(await approve(c), isNull);
      expect(env.adapter.count('POST', 'projects/p1/stages/s1/approve'), 1);
    });

    test(
      'a refusal (403) is shown, never retried, and nothing is read back',
      () async {
        env.adapter.on(
          'POST',
          'projects/p1/stages/s1/approve',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(approve(c), throwsA(_fails(AppErrorKind.forbidden)));
        expect(env.adapter.count('POST', 'projects/p1/stages/s1/approve'), 1);
        expect(env.adapter.count('GET', 'projects/p1/stages'), 0);
      },
    );

    test(
      'a 400 (already completed, or no approval needed) keeps the server words',
      () async {
        env.adapter.on(
          'POST',
          'projects/p1/stages/s1/approve',
          (_) => Reply.json({
            'statusCode': 400,
            'message': 'Stage is already completed',
          }, status: 400),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          approve(c),
          throwsA(
            _fails(AppErrorKind.validation, containing: 'already completed'),
          ),
        );
      },
    );

    group('after a timeout the stages are read back, never resent', () {
      void timeoutPost() => env.adapter.on(
        'POST',
        'projects/p1/stages/s1/approve',
        (_) => Reply.fail(DioExceptionType.receiveTimeout),
      );

      test('completed: reported as done', () async {
        timeoutPost();
        env.adapter.on(
          'GET',
          'projects/p1/stages',
          (_) => Reply.json([stageJson(status: 'COMPLETED')]),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        expect(await approve(c), contains('we checked'));
        expect(env.adapter.count('POST', 'projects/p1/stages/s1/approve'), 1);
      });

      test(
        'still in progress: nothing was recorded and a retry is safe',
        () async {
          timeoutPost();
          env.adapter.on(
            'GET',
            'projects/p1/stages',
            (_) => Reply.json([
              stageJson(status: 'IN_PROGRESS', requiresApproval: true),
            ]),
          );
          final c = makeContainer(env, perms: supervisorPerms);
          addTearDown(c.dispose);
          await expectLater(
            approve(c),
            throwsA(
              _fails(AppErrorKind.timeout, containing: 'nothing was recorded'),
            ),
          );
          expect(env.adapter.count('POST', 'projects/p1/stages/s1/approve'), 1);
        },
      );

      test('the stage is gone: the stages changed', () async {
        timeoutPost();
        env.adapter.on(
          'GET',
          'projects/p1/stages',
          (_) => Reply.json([stageJson(id: 'other')]),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          approve(c),
          throwsA(
            _fails(
              AppErrorKind.validation,
              containing: 'no longer on the project',
            ),
          ),
        );
      });

      test('the check also fails: the outcome stays unknown', () async {
        timeoutPost();
        env.adapter.on(
          'GET',
          'projects/p1/stages',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: supervisorPerms);
        addTearDown(c.dispose);
        await expectLater(
          approve(c),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        expect(env.adapter.count('POST', 'projects/p1/stages/s1/approve'), 1);
      });
    });
  });
}
