import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/features/purchasing/application/purchasing_providers.dart';
import 'package:builder_pro_mobile/features/requests/application/requests_providers.dart';
import 'package:builder_pro_mobile/features/requests/data/request_models.dart'
    show approvalEffect;
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

/// The approvals API carries only a type and an id, so the Requests inbox looks
/// purchase requests and orders up to show what is being approved.
void main() {
  SessionState owner({List<String> perms = ownerPerms}) =>
      SessionState.authenticated(testMe(permissions: perms, role: 'Owner'));

  Map<String, dynamic> approval(String id, String type, String entityId) => {
    ...requestJson(id: id, type: type, notes: null),
    'entityId': entityId,
  };

  void apis(TestEnv e, List<Map<String, dynamic>> requests) {
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
        (_) => Reply.json({'count': requests.length}),
      )
      ..on('GET', 'approvals', (_) => Reply.json(paged(requests, limit: 20)))
      ..on(
        'POST',
        'approvals/r1/steps/step1/decide',
        (_) => Reply.json({}, status: 201),
      );
  }

  Future<void> openRequests(WidgetTester tester) async {
    await tester.tap(find.text('More').last);
    await settle(tester);
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

  testWidgets('a purchase request shows its items, estimate and project', (
    tester,
  ) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'PROCUREMENT_PR', 'pr1')]);
    e.adapter.on(
      'GET',
      'procurement/purchase-requests/pr1',
      (_) => Reply.json(prJson(detail: true)),
    );
    await pumpApp(tester, session: owner(), env: e);
    await settle(tester);
    await openRequests(tester);

    expect(find.textContaining('2 items · \$650.00 estimated'), findsOneWidget);
  });

  testWidgets('approving it says what is being approved, not a warning', (
    tester,
  ) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'PROCUREMENT_PR', 'pr1')]);
    e.adapter.on(
      'GET',
      'procurement/purchase-requests/pr1',
      (_) => Reply.json(prJson(detail: true)),
    );
    await pumpApp(tester, session: owner(), env: e);
    await settle(tester);
    await openRequests(tester);

    await tester.tap(find.text('Approve').first);
    await settle(tester);

    expect(find.textContaining('2 items · \$650.00 estimated'), findsWidgets);
    expect(
      find.textContaining('does not show what is being approved'),
      findsNothing,
    );
    expect(e.adapter.count('POST', 'approvals/r1/steps/step1/decide'), 0);
  });

  testWidgets(
    'approving an order says it will be marked as sent; a request does not',
    (tester) async {
      for (final po in [true, false]) {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(e, [
          po
              ? approval('r1', 'PROCUREMENT_PO', 'po1')
              : approval('r1', 'PROCUREMENT_PR', 'pr1'),
        ]);
        e.adapter
          ..on(
            'GET',
            'procurement/purchase-orders/po1',
            (_) => Reply.json(poJson(detail: true)),
          )
          ..on(
            'GET',
            'procurement/purchase-requests/pr1',
            (_) => Reply.json(prJson(detail: true)),
          );
        await pumpApp(tester, session: owner(), env: e);
        await settle(tester);
        await openRequests(tester);

        await tester.tap(find.text('Approve').first);
        await settle(tester);
        expect(
          find.textContaining('the order is marked as sent'),
          po ? findsOneWidget : findsNothing,
          reason: po ? 'order' : 'request',
        );
        await unmount(tester);
      }
    },
  );

  group('purchasing screens follow a decision made in the inbox', () {
    late TestEnv env;
    setUp(() => env = TestEnv());
    tearDown(() => env.dispose());

    Future<void> decideAndCount(String type, String entityId) async {
      apis(env, [approval('r1', type, entityId)]);
      env.adapter.on(
        'GET',
        'procurement/purchase-requests',
        (_) => Reply.json(paged([prJson()], limit: 20)),
      );
      env.adapter.on(
        'GET',
        'procurement/purchase-orders',
        (_) => Reply.json(paged([poJson()], limit: 20)),
      );
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      c.listen(requestsCatalogProvider, (_, _) {});
      c.listen(purchaseRequestsProvider, (_, _) {});
      c.listen(purchaseOrdersProvider, (_, _) {});
      await pumpEventQueue(times: 30);
      expect(env.adapter.count('GET', 'procurement/purchase-requests'), 1);
      expect(env.adapter.count('GET', 'procurement/purchase-orders'), 1);

      final r = c.read(requestsCatalogProvider).items.single;
      await c.read(requestsCatalogProvider.notifier).decide(r, approve: true);
      await pumpEventQueue(times: 30);
    }

    test('a decided purchase request reloads both purchasing lists', () async {
      await decideAndCount('PROCUREMENT_PR', 'pr1');
      expect(env.adapter.count('GET', 'procurement/purchase-requests'), 2);
      expect(env.adapter.count('GET', 'procurement/purchase-orders'), 2);
    });

    test('a decided change request leaves them alone', () async {
      await decideAndCount('CHANGE_REQUEST', 'cr1');
      expect(env.adapter.count('GET', 'procurement/purchase-requests'), 1);
      expect(env.adapter.count('GET', 'procurement/purchase-orders'), 1);
    });
  });

  testWidgets('a purchase order shows its supplier, total and item count', (
    tester,
  ) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'PROCUREMENT_PO', 'po1')]);
    e.adapter.on(
      'GET',
      'procurement/purchase-orders/po1',
      (_) => Reply.json(poJson(detail: true)),
    );
    await pumpApp(tester, session: owner(), env: e);
    await settle(tester);
    await openRequests(tester);

    expect(find.textContaining('Zim Cement · \$650.00'), findsOneWidget);
  });

  testWidgets('when the lookup fails the card and the confirmation say so', (
    tester,
  ) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'PROCUREMENT_PR', 'pr1')]);
    e.adapter.on(
      'GET',
      'procurement/purchase-requests/pr1',
      (_) => Reply.fail(DioExceptionType.connectionError),
    );
    await pumpApp(tester, session: owner(), env: e);
    await settle(tester);
    await openRequests(tester);

    expect(find.textContaining('estimated'), findsNothing);
    await tester.tap(find.text('Approve').first);
    await settle(tester);
    expect(
      find.textContaining('does not show what is being approved'),
      findsOneWidget,
    );
  });

  testWidgets('a refused lookup (403) is treated the same, never guessed', (
    tester,
  ) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'PROCUREMENT_PR', 'pr1')]);
    e.adapter.on(
      'GET',
      'procurement/purchase-requests/pr1',
      (_) => Reply.json({'statusCode': 403}, status: 403),
    );
    await pumpApp(tester, session: owner(), env: e);
    await settle(tester);
    await openRequests(tester);

    expect(find.textContaining('estimated'), findsNothing);
    expect(find.text('Approve'), findsWidgets);
  });

  testWidgets('without purchasing access nothing is looked up', (tester) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'PROCUREMENT_PR', 'pr1')]);
    // No materials permission at all: the owner set minus materials.*
    final perms = [...ownerPerms]..remove('materials.*');
    await pumpApp(
      tester,
      session: owner(perms: perms),
      env: e,
    );
    await settle(tester);
    await openRequests(tester);

    expect(
      e.adapter.requests.where((r) => r.path.startsWith('procurement')),
      isEmpty,
    );
    await tester.tap(find.text('Approve').first);
    await settle(tester);
    expect(
      find.textContaining('does not show what is being approved'),
      findsOneWidget,
    );
  });

  testWidgets('other kinds of request are not looked up either', (
    tester,
  ) async {
    final e = TestEnv();
    addTearDown(e.dispose);
    apis(e, [approval('r1', 'CHANGE_REQUEST', 'cr1')]);
    await pumpApp(tester, session: owner(), env: e);
    await settle(tester);
    await openRequests(tester);

    expect(find.text('Change request'), findsOneWidget);
    expect(
      e.adapter.requests.where((r) => r.path.startsWith('procurement')),
      isEmpty,
    );
  });

  group('what approving does, by kind of request', () {
    test('the text for each kind', () {
      expect(approvalEffect('PROCUREMENT_PO'), contains('marked as sent'));
      expect(
        approvalEffect('CHANGE_REQUEST'),
        contains('does not apply its cost or days'),
      );
      expect(approvalEffect('BUDGET'), contains('records your decision only'));
      expect(approvalEffect('BUDGET'), contains('the budget itself'));
      expect(approvalEffect('DOCUMENT'), contains('the document itself'));
      expect(approvalEffect('STAGE'), contains('the project stage itself'));
    });

    test('purchase requests and unknown kinds add nothing', () {
      expect(approvalEffect('PROCUREMENT_PR'), isNull);
      expect(approvalEffect('SOMETHING_NEW'), isNull);
    });

    testWidgets('each kind\'s confirmation says what approving does', (
      tester,
    ) async {
      for (final entry in {
        'CHANGE_REQUEST': 'does not apply its cost or days',
        'STAGE': 'It does not change the project stage itself',
        'DOCUMENT': 'It does not change the document itself',
        'BUDGET': 'It does not change the budget itself',
      }.entries) {
        final e = TestEnv();
        addTearDown(e.dispose);
        apis(e, [approval('r1', entry.key, 'x1')]);
        await pumpApp(tester, session: owner(), env: e);
        await settle(tester);
        await openRequests(tester);

        await tester.tap(find.text('Approve').first);
        await settle(tester);

        expect(
          find.textContaining(entry.value),
          findsOneWidget,
          reason: entry.key,
        );
        expect(e.adapter.count('POST', 'approvals/r1/steps/step1/decide'), 0);
        await unmount(tester);
      }
    });
  });

  testWidgets('large text on a small phone with a context line, both themes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final e = TestEnv();
      addTearDown(e.dispose);
      apis(e, [approval('r1', 'PROCUREMENT_PR', 'pr1')]);
      e.adapter.on(
        'GET',
        'procurement/purchase-requests/pr1',
        (_) => Reply.json(prJson(detail: true)),
      );
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
      // At 2× text the card is below the info card; the list is lazy.
      await tester.scrollUntilVisible(
        find.textContaining('estimated'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('estimated'), findsOneWidget);
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
