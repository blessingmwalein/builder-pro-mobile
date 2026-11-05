import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/requests/application/requests_providers.dart';
import 'package:builder_pro_mobile/features/requests/data/request_models.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

const _mine = 'u1';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('models', () {
    test('type labels are plain language; unknown types are tidied', () {
      expect(entityTypeLabel('PROCUREMENT_PO'), 'Purchase order');
      expect(entityTypeLabel('PROCUREMENT_PR'), 'Purchase request');
      expect(entityTypeLabel('CHANGE_REQUEST'), 'Change request');
      expect(entityTypeLabel('SOMETHING_NEW'), 'Something New');
    });

    test('finds the step waiting for a given user, and only that one', () {
      final r = ApprovalRequest.tryParse(requestJson(second: true))!;
      expect(r.pendingStepFor(_mine)?.id, 'step1');
      expect(r.pendingStepFor('u7')?.id, 'step2');
      expect(r.pendingStepFor('nobody'), isNull);
      final decided = ApprovalRequest.tryParse(
        requestJson(myStatus: 'APPROVED'),
      )!;
      expect(decided.pendingStepFor(_mine), isNull);
    });

    test('steps are ordered and the requester is named', () {
      final r = ApprovalRequest.tryParse(requestJson(second: true))!;
      expect(r.steps.map((s) => s.order), [1, 2]);
      expect(r.requestedBy, 'Farai Ncube');
      expect(r.notes, 'Rebar for block A');
    });

    test('rows without an id are skipped', () {
      expect(ApprovalRequest.tryParse({'entityType': 'X'}), isNull);
    });
  });

  group('logic', () {
    Future<ProviderContainer> open(List<Map<String, dynamic>> rows) async {
      env.adapter.on(
        'GET',
        'approvals',
        (_) => Reply.json(paged(rows, limit: 20)),
      );
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      c.listen(requestsCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      return c;
    }

    ApprovalRequest req(ProviderContainer c, [String id = 'r1']) =>
        c.read(requestsCatalogProvider).items.firstWhere((r) => r.id == id);

    test(
      'only requests waiting for me are asked for, with page and limit',
      () async {
        await open([requestJson()]);
        final q = env.adapter.last('GET', 'approvals').query;
        expect(q['myPending'], 'true');
        expect(q['page'], 1);
        expect(q['limit'], 20);
      },
    );

    test(
      'approve sends APPROVED for MY step and removes the request',
      () async {
        final c = await open([requestJson(), requestJson(id: 'r2')]);
        env.adapter.on(
          'POST',
          'approvals/r1/steps/step1/decide',
          (_) => Reply.json({}, status: 201),
        );

        final note = await c
            .read(requestsCatalogProvider.notifier)
            .decide(req(c), approve: true);

        expect(note, isNull);
        expect(
          env.adapter.last('POST', 'approvals/r1/steps/step1/decide').data,
          {'decision': 'APPROVED'},
        );
        expect(c.read(requestsCatalogProvider).items.map((r) => r.id), ['r2']);
      },
    );

    test('reject sends REJECTED with the trimmed comment; blank comments are omitted', () async {
      final c = await open([requestJson(), requestJson(id: 'r2')]);
      env.adapter
        ..on(
          'POST',
          'approvals/r1/steps/step1/decide',
          (_) => Reply.json({}, status: 201),
        )
        ..on(
          'POST',
          'approvals/r2/steps/step1/decide',
          (_) => Reply.json({}, status: 201),
        );
      final n = c.read(requestsCatalogProvider.notifier);

      await n.decide(req(c), approve: false, comment: '  Over budget  ');
      expect(env.adapter.last('POST', 'approvals/r1/steps/step1/decide').data, {
        'decision': 'REJECTED',
        'comment': 'Over budget',
      });
      await n.decide(req(c, 'r2'), approve: false, comment: '  ');
      expect(env.adapter.last('POST', 'approvals/r2/steps/step1/decide').data, {
        'decision': 'REJECTED',
      });
    });

    test(
      'a request with no step for me cannot be decided (and disappears)',
      () async {
        final c = await open([requestJson(myStatus: 'APPROVED')]);
        await expectLater(
          c
              .read(requestsCatalogProvider.notifier)
              .decide(req(c), approve: true),
          throwsA(
            isA<AppException>().having(
              (e) => e.message,
              'message',
              contains('no longer waiting'),
            ),
          ),
        );
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
        expect(c.read(requestsCatalogProvider).items, isEmpty);
      },
    );

    test('a refusal (403) keeps the request', () async {
      final c = await open([requestJson()]);
      env.adapter.on(
        'POST',
        'approvals/r1/steps/step1/decide',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await expectLater(
        c.read(requestsCatalogProvider.notifier).decide(req(c), approve: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.forbidden,
          ),
        ),
      );
      expect(c.read(requestsCatalogProvider).items, hasLength(1));
    });

    test('no connection keeps the request and queues nothing', () async {
      final c = await open([requestJson()]);
      env.adapter.on(
        'POST',
        'approvals/r1/steps/step1/decide',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      await expectLater(
        c.read(requestsCatalogProvider.notifier).decide(req(c), approve: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.offline,
          ),
        ),
      );
      expect(c.read(requestsCatalogProvider).items, hasLength(1));
      expect(await env.db.outboxFor('u1'), isEmpty);
    });

    test(
      'timed out but recorded: read back, shown as done, NEVER sent twice',
      () async {
        final c = await open([requestJson()]);
        env.adapter
          ..on(
            'POST',
            'approvals/r1/steps/step1/decide',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            'approvals/r1',
            (_) => Reply.json(
              requestJson(status: 'APPROVED', myStatus: 'APPROVED'),
            ),
          );

        final note = await c
            .read(requestsCatalogProvider.notifier)
            .decide(req(c), approve: true);

        expect(note, contains('recorded'));
        expect(env.adapter.count('POST', 'approvals/r1/steps/step1/decide'), 1);
        expect(c.read(requestsCatalogProvider).items, isEmpty);
      },
    );

    test('timed out and NOT recorded: a clear message, the request stays, still one POST', () async {
      final c = await open([requestJson()]);
      env.adapter
        ..on(
          'POST',
          'approvals/r1/steps/step1/decide',
          (_) => Reply.fail(DioExceptionType.receiveTimeout),
        )
        ..on('GET', 'approvals/r1', (_) => Reply.json(requestJson()));

      await expectLater(
        c.read(requestsCatalogProvider.notifier).decide(req(c), approve: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('nothing was recorded'),
          ),
        ),
      );
      expect(env.adapter.count('POST', 'approvals/r1/steps/step1/decide'), 1);
      expect(c.read(requestsCatalogProvider).items, hasLength(1));
    });

    test(
      'timed out and decided differently meanwhile: reported, not overwritten',
      () async {
        final c = await open([requestJson()]);
        env.adapter
          ..on(
            'POST',
            'approvals/r1/steps/step1/decide',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            'approvals/r1',
            (_) => Reply.json(
              requestJson(status: 'REJECTED', myStatus: 'REJECTED'),
            ),
          );

        final note = await c
            .read(requestsCatalogProvider.notifier)
            .decide(req(c), approve: true);

        expect(note, contains('already been decided'));
        expect(c.read(requestsCatalogProvider).items, isEmpty);
      },
    );

    test(
      'timed out and the check also fails: the outcome stays unknown',
      () async {
        final c = await open([requestJson()]);
        env.adapter
          ..on(
            'POST',
            'approvals/r1/steps/step1/decide',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          )
          ..on(
            'GET',
            'approvals/r1',
            (_) => Reply.fail(DioExceptionType.connectionError),
          );
        await expectLater(
          c
              .read(requestsCatalogProvider.notifier)
              .decide(req(c), approve: true),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        expect(c.read(requestsCatalogProvider).items, hasLength(1));
      },
    );

    test('"already decided" (400) refreshes the list and explains', () async {
      final c = await open([requestJson()]);
      env.adapter.on(
        'POST',
        'approvals/r1/steps/step1/decide',
        (_) => Reply.json({
          'statusCode': 400,
          'message': 'This step has already been decided',
        }, status: 400),
      );
      await expectLater(
        c.read(requestsCatalogProvider.notifier).decide(req(c), approve: true),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('already been decided'),
          ),
        ),
      );
      expect(env.adapter.count('GET', 'approvals'), 2); // initial + refresh
    });

    test('the pending count reads /approvals/pending/count', () async {
      env.adapter.on(
        'GET',
        'approvals/pending/count',
        (_) => Reply.json({'count': 3}),
      );
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      c.listen(pendingRequestCountProvider, (_, _) {});
      expect(await c.read(pendingRequestCountProvider.future), 3);
    });
  });

  group('screen', () {
    SessionState owner() => SessionState.authenticated(
      testMe(permissions: ownerPerms, role: 'Owner'),
    );

    void apis(TestEnv e, {List<Map<String, dynamic>>? requests}) {
      e.adapter
        // Today is the manager's landing page.
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'GET',
          'time-tracking/weekly-summary',
          (_) => Reply.json({'entries': []}),
        )
        ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
        ..on('GET', 'tasks', (_) => Reply.json(paged([])))
        ..on(
          'GET',
          'approvals/pending/count',
          (_) => Reply.json({
            'count': (requests ?? [requestJson()]).length,
          }),
        )
        ..on(
          'GET',
          'approvals',
          (_) => Reply.json(
            paged(
              requests ??
                  [
                    requestJson(),
                    requestJson(id: 'r2', type: 'CHANGE_REQUEST', notes: null),
                  ],
              limit: 20,
            ),
          ),
        );
    }

    Future<void> openRequests(WidgetTester tester) async {
      // Requests sits under More for managers.
      await tester.tap(find.text('More').last);
      await settle(tester);
      // The More list is lazy: scroll until the item is built, then on screen.
      await tester.scrollUntilVisible(
        find.text('Requests'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Requests'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Requests'));
      await settle(tester);
    }

    testWidgets('Today prompts when requests are waiting and opens the inbox', (
      tester,
    ) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e);
      await pumpApp(tester, session: owner(), env: e);
      await settle(tester);

      expect(find.text('REQUESTS'), findsOneWidget);
      await tester.tap(find.textContaining('waiting for your decision'));
      await settle(tester);
      expect(find.text('Purchase order'), findsOneWidget);
    });

    testWidgets('Today says nothing when nothing is waiting', (tester) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e, requests: []);
      await pumpApp(tester, session: owner(), env: e);
      await settle(tester);
      expect(find.text('REQUESTS'), findsNothing);
    });

    testWidgets(
      'inbox lists who asked, the note and the approvers, and is honest about missing detail',
      (tester) async {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(
          e,
          requests: [
            requestJson(second: true),
            requestJson(id: 'r2', type: 'CHANGE_REQUEST', notes: null),
          ],
        );
        await pumpApp(tester, session: owner(), env: e);
        await settle(tester);
        await openRequests(tester);

        expect(find.text('2 waiting for you'), findsOneWidget);
        expect(find.text('Purchase order'), findsOneWidget);
        expect(find.text('Change request'), findsOneWidget);
        expect(find.textContaining('Farai Ncube'), findsWidgets);
        expect(find.text('Rebar for block A'), findsOneWidget);
        expect(find.text('0 of 2 approvers have approved'), findsOneWidget);
        expect(
          find.textContaining('for other kinds it shows only who asked'),
          findsOneWidget,
        );
        expect(e.adapter.last('GET', 'approvals').query['myPending'], 'true');
      },
    );

    testWidgets(
      'Approve confirms first (saying what the app cannot show), then decides',
      (tester) async {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(e);
        e.adapter.on(
          'POST',
          'approvals/r1/steps/step1/decide',
          (_) => Reply.json({}, status: 201),
        );
        await pumpApp(tester, session: owner(), env: e);
        await settle(tester);
        await openRequests(tester);

        await tester.tap(find.text('Approve').first);
        await settle(tester);
        expect(find.text('Approve this purchase order?'), findsOneWidget);
        expect(
          find.textContaining('does not show what is being approved'),
          findsOneWidget,
        );
        expect(e.adapter.count('POST', 'approvals/r1/steps/step1/decide'), 0);

        await tester.tap(find.widgetWithText(InkWell, 'Approve').last);
        await settle(tester);

        expect(e.adapter.last('POST', 'approvals/r1/steps/step1/decide').data, {
          'decision': 'APPROVED',
        });
        expect(find.text('1 waiting for you'), findsOneWidget);
        expect(find.text('Purchase order'), findsNothing);
      },
    );

    testWidgets('cancelling the confirmation sends nothing', (tester) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e);
      await pumpApp(tester, session: owner(), env: e);
      await settle(tester);
      await openRequests(tester);

      await tester.tap(find.text('Approve').first);
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(e.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(find.text('2 waiting for you'), findsOneWidget);
    });

    testWidgets(
      'Reject takes a reason and warns that it stops the whole request',
      (tester) async {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(e);
        e.adapter.on(
          'POST',
          'approvals/r1/steps/step1/decide',
          (_) => Reply.json({}, status: 201),
        );
        await pumpApp(tester, session: owner(), env: e);
        await settle(tester);
        await openRequests(tester);

        await tester.tap(find.text('Reject').first);
        await settle(tester);
        expect(find.text('Reject this purchase order?'), findsOneWidget);
        expect(find.textContaining('stops the whole request'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, 'Too expensive');
        await tester.tap(find.widgetWithText(InkWell, 'Reject').last);
        await settle(tester);

        expect(e.adapter.last('POST', 'approvals/r1/steps/step1/decide').data, {
          'decision': 'REJECTED',
          'comment': 'Too expensive',
        });
      },
    );

    testWidgets('a failed decision leaves the request and says why', (
      tester,
    ) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e);
      e.adapter.on(
        'POST',
        'approvals/r1/steps/step1/decide',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      await pumpApp(tester, session: owner(), env: e);
      await settle(tester);
      await openRequests(tester);

      await tester.tap(find.text('Approve').first);
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Approve').last);
      await settle(tester);

      expect(
        find.textContaining("offline or the server can't"),
        findsOneWidget,
      );
      expect(find.text('2 waiting for you'), findsOneWidget);
    });

    testWidgets('empty inbox', (tester) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e, requests: []);
      await pumpApp(tester, session: owner(), env: e);
      await settle(tester);
      await openRequests(tester);
      expect(find.text('Nothing waiting for you'), findsOneWidget);
    });

    testWidgets('a failed load is an error with Retry, not "nothing waiting"', (
      tester,
    ) async {
      final e = TestEnv();
      addTearDown(e.dispose);
      e.adapter
        ..on('GET', 'time-tracking/active', (_) => Reply.empty())
        ..on(
          'GET',
          'time-tracking/weekly-summary',
          (_) => Reply.json({'entries': []}),
        )
        ..on('GET', 'time-tracking', (_) => Reply.json(paged([])))
        ..on('GET', 'tasks', (_) => Reply.json(paged([])))
        ..on(
          'GET',
          'approvals/pending/count',
          (_) => Reply.fail(DioExceptionType.connectionError),
        )
        ..on(
          'GET',
          'approvals',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
      await pumpApp(tester, session: owner(), env: e);
      await settle(tester);
      await openRequests(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Nothing waiting for you'), findsNothing);
    });

    testWidgets('large text on a small phone, both themes, without overflow', (
      tester,
    ) async {
      for (final dark in [false, true]) {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(e, requests: [requestJson(second: true)]);
        final capture = ErrorCapture();
        await pumpApp(
          tester,
          session: owner(),
          env: e,
          size: const Size(320, 640),
          textScale: 2.0,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await settle(tester);
        await openRequests(tester);
        // The cards sit below the intro at this size; the list is lazy.
        await tester.scrollUntilVisible(
          find.text('Purchase order'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Purchase order'), findsOneWidget);
        await unmount(tester);
        expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
      }
    });
  });
}
