import 'package:builder_pro_mobile/app/router/app_router.dart'
    show routerProvider;
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

void _apis(
  TestEnv env, {
  String prStatus = 'SUBMITTED',
  String requestedById = 'u9',
  bool projectsFail = false,
}) {
  supervisorApis(env, projectsFail: projectsFail);
  env.adapter
    ..on('GET', 'procurement/purchase-requests', (o) {
      final status = o.queryParameters['status'];
      final all = [
        prJson(status: prStatus, requestedById: requestedById),
        prJson(
          id: 'pr2',
          number: 'PR-2026-0002',
          status: 'DRAFT',
          requestedById: 'u1',
          requester: 'Tendai',
          items: 1,
          notes: null,
        ),
        prJson(id: 'pr3', number: 'PR-2026-0003', status: 'APPROVED'),
      ];
      return Reply.json(
        paged(
          status == null
              ? all
              : all.where((p) => p['status'] == status).toList(),
          limit: 20,
        ),
      );
    })
    ..on(
      'GET',
      'procurement/purchase-requests/pr1',
      (_) => Reply.json(
        prJson(detail: true, status: prStatus, requestedById: requestedById),
      ),
    )
    ..on(
      'GET',
      'procurement/purchase-requests/pr2',
      (_) => Reply.json(
        prJson(
          id: 'pr2',
          number: 'PR-2026-0002',
          detail: true,
          status: 'DRAFT',
          requestedById: 'u1',
          items: 1,
        ),
      ),
    )
    ..on(
      'GET',
      'procurement/purchase-orders',
      (_) => Reply.json(
        paged([
          poJson(),
          poJson(
            id: 'po2',
            number: 'PO-2026-0002',
            supplier: 'Sand & Stone',
            total: '300.00',
            status: 'RECEIVED',
          ),
        ], limit: 20),
      ),
    )
    ..on(
      'GET',
      'procurement/purchase-orders/po1',
      (_) => Reply.json(poJson(detail: true)),
    );
}

Future<void> _openPurchasing(WidgetTester tester) async {
  await tester.tap(find.text('More').last);
  await settle(tester);
  await tester.scrollUntilVisible(
    find.text('Purchasing'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.text('Purchasing'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('Purchasing'));
  await settle(tester);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(f);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('lists', () {
    testWidgets('requests show number, status, who asked and how many items', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);

      expect(find.text('PR-2026-0001'), findsOneWidget);
      expect(find.text('Submitted'), findsWidgets);
      expect(find.text('Draft'), findsWidgets);
      expect(find.textContaining('Farai Ncube'), findsWidgets);
      expect(find.textContaining('2 items'), findsWidgets);
      expect(find.text('For the slab pour'), findsWidgets);
      expect(find.text('New purchase request'), findsOneWidget);
    });

    testWidgets('a status chip filters through the server', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Waiting'));
      await settle(tester);

      expect(
        env.adapter
            .last('GET', 'procurement/purchase-requests')
            .query['status'],
        'SUBMITTED',
      );
      expect(find.text('PR-2026-0001'), findsOneWidget);
      expect(find.text('PR-2026-0002'), findsNothing);
    });

    testWidgets('orders tab shows supplier, total and expected delivery', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Orders'));
      await settle(tester);

      expect(find.text('Zim Cement'), findsOneWidget);
      expect(find.text(r'$650.00'), findsOneWidget);
      expect(find.textContaining('Expected'), findsWidgets);
      expect(find.text('Sand & Stone'), findsOneWidget);
      expect(find.text('Received'), findsWidgets);
    });

    testWidgets('a view-only role cannot start a new request', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: ['tasks.*', 'projects.view', 'materials.view', 'messaging.*'],
        ),
        env: env,
      );
      await settle(tester);
      await _openPurchasing(tester);
      expect(find.text('PR-2026-0001'), findsOneWidget);
      expect(find.text('New purchase request'), findsNothing);
    });

    testWidgets('a failed load is an error with Retry, not "no requests"', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      supervisorApis(env);
      env.adapter.on(
        'GET',
        'procurement/purchase-requests',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No purchase requests yet'), findsNothing);
    });
  });

  group('request detail', () {
    Future<void> openFirst(WidgetTester tester) async {
      await tester.tap(find.text('PR-2026-0001'));
      await settle(tester);
    }

    testWidgets(
      'shows items with estimates, the estimated total and the linked order',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openFirst(tester);

        expect(find.text('Portland cement 50kg'), findsOneWidget);
        expect(find.text('40 bag × \$12.50'), findsOneWidget);
        expect(find.text(r'$500.00'), findsOneWidget);
        expect(find.text('Estimated total'), findsOneWidget);
        expect(find.text(r'$650.00'), findsWidgets);
        await _scrollTo(tester, find.text('PO-2026-0001'));
        expect(find.text('PO-2026-0001'), findsOneWidget);
      },
    );

    testWidgets('Approve confirms with the facts, then sends once', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-requests/pr1/approve',
        (_) => Reply.json({}, status: 201),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openFirst(tester);

      await _scrollTo(tester, find.widgetWithText(InkWell, 'Approve'));
      await tester.tap(find.widgetWithText(InkWell, 'Approve'));
      await settle(tester);
      expect(find.text('Approve PR-2026-0001?'), findsOneWidget);
      expect(
        find.textContaining('2 items, about \$650.00 estimated'),
        findsOneWidget,
      );
      expect(
        find.textContaining('You raised this request yourself'),
        findsNothing,
      );
      expect(
        env.adapter.count('POST', 'procurement/purchase-requests/pr1/approve'),
        0,
      );

      await tester.tap(find.widgetWithText(InkWell, 'Approve').last);
      await settle(tester);

      expect(
        env.adapter.count('POST', 'procurement/purchase-requests/pr1/approve'),
        1,
      );
      expect(find.text('Approved.'), findsOneWidget);
    });

    testWidgets(
      'approving your own request carries a plain reminder, not a block',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, requestedById: 'u1');
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openFirst(tester);

        await _scrollTo(tester, find.widgetWithText(InkWell, 'Approve'));
        await tester.tap(find.widgetWithText(InkWell, 'Approve'));
        await settle(tester);

        expect(
          find.textContaining('You raised this request yourself'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Reject takes a reason and warns that it replaces the requester notes',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'procurement/purchase-requests/pr1/reject',
          (_) => Reply.json({}, status: 201),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openFirst(tester);

        await _scrollTo(tester, find.widgetWithText(InkWell, 'Reject'));
        await tester.tap(find.widgetWithText(InkWell, 'Reject'));
        await settle(tester);
        expect(
          find.textContaining('replaces the notes they wrote'),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField).last, 'Over budget');
        await tester.tap(find.widgetWithText(InkWell, 'Reject').last);
        await settle(tester);

        expect(
          env.adapter
              .last('POST', 'procurement/purchase-requests/pr1/reject')
              .data,
          {'notes': 'Over budget'},
        );
      },
    );

    testWidgets('a refusal leaves the request and says why', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-requests/pr1/approve',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openFirst(tester);

      await _scrollTo(tester, find.widgetWithText(InkWell, 'Approve'));
      await tester.tap(find.widgetWithText(InkWell, 'Approve'));
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Approve').last);
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Approve'), findsOneWidget);
    });

    testWidgets('a view-only role sees no actions on a submitted request', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: ['tasks.*', 'projects.view', 'materials.view', 'messaging.*'],
        ),
        env: env,
      );
      await settle(tester);
      await _openPurchasing(tester);
      await openFirst(tester);

      await _scrollTo(
        tester,
        find.textContaining('Waiting for someone with approval rights'),
      );
      expect(find.widgetWithText(InkWell, 'Approve'), findsNothing);
      expect(find.widgetWithText(InkWell, 'Reject'), findsNothing);
    });

    testWidgets('a view-only role sees no Submit on a draft', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: ['tasks.*', 'projects.view', 'materials.view', 'messaging.*'],
        ),
        env: env,
      );
      await settle(tester);
      await _openPurchasing(tester);
      await tester.tap(find.text('PR-2026-0002'));
      await settle(tester);

      await _scrollTo(tester, find.text('ITEMS 1'));
      expect(find.widgetWithText(InkWell, 'Submit for approval'), findsNothing);
    });

    testWidgets(
      'a draft can be submitted for approval by someone who may manage requests',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'procurement/purchase-requests/pr2/submit',
          (_) => Reply.json({}, status: 201),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await tester.tap(find.text('PR-2026-0002'));
        await settle(tester);

        await _scrollTo(
          tester,
          find.widgetWithText(InkWell, 'Submit for approval'),
        );
        await tester.tap(find.widgetWithText(InkWell, 'Submit for approval'));
        await settle(tester);

        expect(
          env.adapter.count('POST', 'procurement/purchase-requests/pr2/submit'),
          1,
        );
        expect(find.text('Submitted for approval.'), findsOneWidget);
      },
    );
  });

  testWidgets(
    'order detail: items, total, deliveries, and a pointer to the web app',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Orders'));
      await settle(tester);
      await tester.tap(find.text('Zim Cement'));
      await settle(tester);

      expect(find.text('Portland cement 50kg'), findsOneWidget);
      expect(find.text('Order total'), findsOneWidget);
      expect(find.text('1 recorded'), findsOneWidget);
      expect(find.text('PR-2026-0001'), findsWidgets);
      await _scrollTo(tester, find.textContaining('done on the web app'));
      expect(find.text('Deliver to gate B'), findsOneWidget);
    },
  );

  group('new request', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.text('New purchase request'));
      await settle(tester);
      expect(find.text('New purchase request'), findsWidgets);
    }

    testWidgets(
      'an empty form is stopped with plain messages before anything is sent',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openForm(tester);

        await tester.tap(find.widgetWithText(InkWell, 'Submit for approval'));
        await settle(tester);

        expect(find.text('Say what is needed'), findsOneWidget);
        expect(find.text('Enter how much you used'), findsOneWidget);
        expect(find.text('Add a unit (bags, m3…)'), findsOneWidget);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets('creates and submits with several items', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter
        ..on(
          'POST',
          'procurement/purchase-requests',
          (_) => Reply.json(
            prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 2),
            status: 201,
          ),
        )
        ..on(
          'POST',
          'procurement/purchase-requests/new/submit',
          (_) => Reply.json({}, status: 201),
        );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), 'For level 2');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Portland cement',
      );
      await tester.enterText(find.byType(TextFormField).at(2), '40');
      await tester.enterText(find.byType(TextFormField).at(3), 'bags');
      await tester.enterText(find.byType(TextFormField).at(4), '12,50');
      await _scrollTo(tester, find.text('Add another item'));
      await tester.tap(find.text('Add another item'));
      await settle(tester);
      expect(find.text('ITEM 2'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(5), 'River sand');
      await tester.enterText(find.byType(TextFormField).at(6), '5');
      await tester.enterText(find.byType(TextFormField).at(7), 'm3');

      await _scrollTo(
        tester,
        find.widgetWithText(InkWell, 'Submit for approval'),
      );
      await tester.tap(find.widgetWithText(InkWell, 'Submit for approval'));
      await settle(tester, frames: 20);

      final body =
          env.adapter.last('POST', 'procurement/purchase-requests').data as Map;
      expect(body['notes'], 'For level 2');
      final items = body['items'] as List;
      expect(items, hasLength(2));
      expect(items[0], {
        'description': 'Portland cement',
        'quantity': 40.0,
        'unit': 'bags',
        'estimatedUnitCost': 12.5,
      });
      expect(items[1], {
        'description': 'River sand',
        'quantity': 5.0,
        'unit': 'm3',
      });
      expect(
        env.adapter.count('POST', 'procurement/purchase-requests/new/submit'),
        1,
      );
      expect(find.text('Submitted for approval.'), findsOneWidget);
      expect(
        find.text('New purchase request'),
        findsOneWidget,
      ); // back on the list (its button)
    });

    testWidgets('Save as draft does not submit', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-requests',
        (_) => Reply.json(
          prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 1),
          status: 201,
        ),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(1), 'Cement');
      await tester.enterText(find.byType(TextFormField).at(2), '10');
      await tester.enterText(find.byType(TextFormField).at(3), 'bags');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Save as draft'));
      await tester.tap(find.widgetWithText(InkWell, 'Save as draft'));
      await settle(tester, frames: 20);

      expect(env.adapter.count('POST', 'procurement/purchase-requests'), 1);
      expect(
        env.adapter.requests.where((r) => r.path.endsWith('/submit')),
        isEmpty,
      );
      expect(find.text('Saved as a draft.'), findsOneWidget);
    });

    testWidgets(
      'if submitting fails the draft is kept and the message says so',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter
          ..on(
            'POST',
            'procurement/purchase-requests',
            (_) => Reply.json(
              prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 1),
              status: 201,
            ),
          )
          ..on(
            'POST',
            'procurement/purchase-requests/new/submit',
            (_) => Reply.json({'statusCode': 403}, status: 403),
          );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openForm(tester);

        await tester.enterText(find.byType(TextFormField).at(1), 'Cement');
        await tester.enterText(find.byType(TextFormField).at(2), '10');
        await tester.enterText(find.byType(TextFormField).at(3), 'bags');
        await _scrollTo(
          tester,
          find.widgetWithText(InkWell, 'Submit for approval'),
        );
        await tester.tap(find.widgetWithText(InkWell, 'Submit for approval'));
        await settle(tester, frames: 20);

        expect(
          find.textContaining(
            'Saved as a draft, but it could not be submitted',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('a server refusal keeps the form and what was typed', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-requests',
        (_) => Reply.json({
          'statusCode': 400,
          'message': ['items must contain at least 1 elements'],
        }, status: 400),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(1), 'Cement');
      await tester.enterText(find.byType(TextFormField).at(2), '10');
      await tester.enterText(find.byType(TextFormField).at(3), 'bags');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Save as draft'));
      await tester.tap(find.widgetWithText(InkWell, 'Save as draft'));
      await settle(tester);

      expect(
        find.textContaining('items must contain at least 1'),
        findsOneWidget,
      );
      expect(find.text('Cement'), findsOneWidget);
    });

    testWidgets('a slow reply cannot be sent twice by tapping again', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-requests',
        (_) => Reply.json(
          prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 1),
          status: 201,
          delay: const Duration(seconds: 2),
        ),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openForm(tester);
      await tester.enterText(find.byType(TextFormField).at(1), 'Cement');
      await tester.enterText(find.byType(TextFormField).at(2), '10');
      await tester.enterText(find.byType(TextFormField).at(3), 'bags');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Save as draft'));

      // Two taps in the same frame: the button has not been disabled yet, so
      // only the screen's own lock stops the second one.
      await tester.tap(find.widgetWithText(InkWell, 'Save as draft'));
      await tester.tap(
        find.widgetWithText(InkWell, 'Save as draft'),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(env.adapter.count('POST', 'procurement/purchase-requests'), 1);
    });

    testWidgets(
      'the project is chosen from the whole list and sent with the request',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'procurement/purchase-requests',
          (_) => Reply.json(
            prJson(id: 'new', status: 'DRAFT', requestedById: 'u1', items: 1),
            status: 201,
          ),
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openForm(tester);

        await tester.tap(find.widgetWithText(InkWell, 'No specific project'));
        await settle(tester);
        expect(find.text('Harare Tower'), findsOneWidget);
        expect(find.text('Borrowdale Villas'), findsOneWidget);
        await tester.tap(find.text('Borrowdale Villas'));
        await settle(tester);
        expect(find.text('BV-02 · Borrowdale Villas'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField).at(1), 'Cement');
        await tester.enterText(find.byType(TextFormField).at(2), '10');
        await tester.enterText(find.byType(TextFormField).at(3), 'bags');
        await _scrollTo(tester, find.widgetWithText(InkWell, 'Save as draft'));
        await tester.tap(find.widgetWithText(InkWell, 'Save as draft'));
        await settle(tester, frames: 20);

        final body =
            env.adapter.last('POST', 'procurement/purchase-requests').data
                as Map;
        expect(body['projectId'], 'p2');
      },
    );

    testWidgets('"No specific project" clears a chosen project', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openPurchasing(tester);
      await openForm(tester);

      await tester.tap(find.widgetWithText(InkWell, 'No specific project'));
      await settle(tester);
      await tester.tap(find.text('Harare Tower'));
      await settle(tester);
      expect(find.text('HT-01 · Harare Tower'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'HT-01 · Harare Tower'));
      await settle(tester);
      await tester.tap(find.text('No specific project'));
      await settle(tester);
      expect(find.text('HT-01 · Harare Tower'), findsNothing);
    });

    testWidgets(
      'projects that cannot be loaded give an error and keep the form',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, projectsFail: true);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openPurchasing(tester);
        await openForm(tester);

        await tester.tap(find.widgetWithText(InkWell, 'No specific project'));
        await settle(tester);

        expect(find.text('Harare Tower'), findsNothing);
        expect(find.text('Add another item'), findsOneWidget);
      },
    );

    testWidgets('a role without materials.manage cannot open the form', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(
          perms: ['tasks.*', 'projects.view', 'materials.view', 'messaging.*'],
        ),
        env: env,
      );
      await settle(tester);
      await _openPurchasing(tester);
      expect(find.text('New purchase request'), findsNothing);
    });

    testWidgets(
      'reaching the form by a link without materials.manage says so',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        final c = await pumpApp(
          tester,
          session: supervisorSession(
            perms: [
              'tasks.*',
              'projects.view',
              'materials.view',
              'messaging.*',
            ],
          ),
          env: env,
        );
        await settle(tester);
        c.read(routerProvider).go('/purchasing/new');
        await settle(tester);

        expect(find.text('Not allowed'), findsOneWidget);
        expect(find.text('Add another item'), findsNothing);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );
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
        session: supervisorSession(),
        env: env,
        size: const Size(320, 640),
        textScale: 2.0,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await settle(tester);
      await _openPurchasing(tester);
      await tester.tap(find.text('PR-2026-0001'));
      await settle(tester);
      await _scrollTo(tester, find.textContaining('Estimated total'));
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
