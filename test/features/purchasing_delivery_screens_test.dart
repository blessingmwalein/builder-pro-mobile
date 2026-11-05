import 'package:builder_pro_mobile/app/router/app_router.dart'
    show routerProvider;
import 'package:builder_pro_mobile/core/utils/format.dart';
import 'package:builder_pro_mobile/shared/components/app_button.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/manager_apis.dart';
import '../support/test_app.dart';

const _viewOnly = ['tasks.*', 'projects.view', 'materials.view', 'messaging.*'];

/// Supervisor replies plus one purchase order (`po1`: 40 bags of cement and
/// 5 m3 of sand) in the state a test asks for.
void _apis(
  TestEnv env, {
  String status = 'SENT',
  List<Map<String, dynamic>> notes = const [],
  bool orderFails = false,
}) {
  supervisorApis(env);
  env.adapter
    ..on(
      'GET',
      'procurement/purchase-orders',
      (_) => Reply.json(paged([poJson(status: status)], limit: 20)),
    )
    ..on(
      'GET',
      'procurement/purchase-orders/po1',
      (_) => orderFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              poJson(detail: true, status: status, deliveryNotes: notes),
            ),
    );
}

Future<void> _openOrder(WidgetTester tester) async {
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
  await tester.tap(find.widgetWithText(ChoiceChip, 'Orders'));
  await settle(tester);
  await tester.tap(find.text('Zim Cement'));
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

Future<void> _openForm(WidgetTester tester) async {
  await _scrollTo(tester, find.widgetWithText(InkWell, 'Record a delivery'));
  await tester.tap(find.widgetWithText(InkWell, 'Record a delivery'));
  await settle(tester);
  expect(find.text('Delivery for PO-2026-0001'), findsOneWidget);
}

void main() {
  group('order detail', () {
    testWidgets('a sent order offers to record a delivery', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);

      await _scrollTo(tester, find.text('Record a delivery'));
      expect(find.text('Record a delivery'), findsOneWidget);
      expect(find.textContaining('DELIVERIES'), findsNothing);
      expect(
        find.text('Sending an order to the supplier is done on the web app.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'deliveries already recorded are listed with their quantities',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(
          env,
          status: 'PARTIAL',
          notes: [
            dnJson(notes: 'Two bags torn', lines: [dnLine(received: 10)]),
            dnJson(id: 'dn2', by: 'u9', lines: [dnLine(received: 5)]),
          ],
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openOrder(tester);

        await _scrollTo(tester, find.text('DELIVERIES 2'));
        expect(find.text('Tue 20 Oct · received by you'), findsOneWidget);
        expect(
          find.text('Tue 20 Oct · received by a colleague'),
          findsOneWidget,
        );
        expect(find.text('Portland cement 50kg: 10 received'), findsOneWidget);
        expect(find.text('Portland cement 50kg: 5 received'), findsOneWidget);
        expect(find.text('Two bags torn'), findsOneWidget);
      },
    );

    testWidgets('a view-only role cannot record a delivery and is told why', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(
        tester,
        session: supervisorSession(perms: _viewOnly),
        env: env,
      );
      await settle(tester);
      await _openOrder(tester);

      await _scrollTo(
        tester,
        find.textContaining('Recording a delivery needs permission'),
      );
      expect(find.text('Record a delivery'), findsNothing);
    });

    testWidgets(
      'an order that is complete, a draft or cancelled has no button',
      (tester) async {
        for (final status in ['RECEIVED', 'DRAFT', 'CANCELLED']) {
          final env = TestEnv();
          addTearDown(env.dispose);
          _apis(env, status: status);
          await pumpApp(tester, session: supervisorSession(), env: env);
          await settle(tester);
          await _openOrder(tester);
          await _scrollTo(tester, find.textContaining('done on the web app'));
          expect(find.text('Record a delivery'), findsNothing, reason: status);
          await unmount(tester);
        }
      },
    );

    testWidgets(
      'everything recorded as received but the order not complete is flagged',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(
          env,
          status: 'PARTIAL',
          notes: [
            dnJson(
              lines: [
                dnLine(received: 40),
                dnLine(
                  description: 'River sand',
                  materialId: 'm2',
                  ordered: 5,
                  received: 5,
                ),
              ],
            ),
          ],
        );
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openOrder(tester);

        await _scrollTo(
          tester,
          find.textContaining('Everything ordered is recorded as received'),
        );
        expect(find.text('Record a delivery'), findsNothing);
      },
    );
  });

  group('receive form', () {
    testWidgets('shows what was ordered, what came before and what is left', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(
        env,
        status: 'PARTIAL',
        notes: [
          dnJson(lines: [dnLine(received: 10)]),
        ],
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);

      expect(
        find.text('Ordered 40 · received so far 10 · outstanding 30 bag'),
        findsOneWidget,
      );
      expect(
        find.text('Ordered 5 · received so far 0 · outstanding 5 m3'),
        findsOneWidget,
      );
      expect(find.text(Fmt.day(DateTime.now())), findsOneWidget);
    });

    testWidgets('"Everything outstanding arrived" fills every field', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);

      await tester.tap(find.text('Everything outstanding arrived'));
      await tester.pump();

      expect(find.widgetWithText(TextFormField, '40'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '5'), findsOneWidget);
    });

    testWidgets('nothing entered is stopped before anything is sent', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);

      await _scrollTo(tester, find.widgetWithText(InkWell, 'Record delivery'));
      await tester.tap(find.widgetWithText(InkWell, 'Record delivery'));
      await settle(tester);

      expect(
        find.text('Enter how much of at least one item arrived.'),
        findsOneWidget,
      );
      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('more than is outstanding is refused on the field', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '41');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Record delivery'));
      await tester.tap(find.widgetWithText(InkWell, 'Record delivery'));
      await settle(tester);

      expect(
        find.textContaining('Only 40 bag is still outstanding'),
        findsOneWidget,
      );
      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets(
      'confirms what is recorded, what is missing and the stock effect',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: supervisorSession(), env: env);
        await settle(tester);
        await _openOrder(tester);
        await _openForm(tester);

        await tester.enterText(find.byType(TextFormField).at(0), '30');
        await _scrollTo(
          tester,
          find.widgetWithText(InkWell, 'Record delivery'),
        );
        await tester.tap(find.widgetWithText(InkWell, 'Record delivery'));
        await settle(tester);

        expect(find.text('Record this delivery?'), findsOneWidget);
        expect(
          find.textContaining('Received: Portland cement 50kg 30 bag.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Nothing received yet of: River sand.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Stock goes up for 1 item linked to a material.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('cannot be changed or removed'),
          findsWidgets,
        );
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);

        await tester.tap(find.text('Cancel'));
        await settle(tester);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets('records the delivery once and goes back to the order', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-orders/po1/deliver',
        (_) => Reply.json(dnJson(), status: 201),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '30');
      await tester.enterText(find.byType(TextFormField).at(2), 'Two bags torn');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Record delivery'));
      await tester.tap(find.widgetWithText(InkWell, 'Record delivery'));
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Record delivery').last);
      await settle(tester, frames: 20);

      expect(
        env.adapter.count('POST', 'procurement/purchase-orders/po1/deliver'),
        1,
      );
      final body =
          env.adapter
                  .last('POST', 'procurement/purchase-orders/po1/deliver')
                  .data
              as Map;
      expect(body['deliveryDate'], Fmt.isoDay(DateTime.now()));
      expect(body['notes'], 'Two bags torn');
      expect((body['items'] as List).map((i) => i['quantityReceived']), [
        30.0,
        0.0,
      ]);
      expect(find.text('Delivery recorded.'), findsOneWidget);
      expect(find.text('Delivery for PO-2026-0001'), findsNothing);
    });

    testWidgets('two taps in one frame open one confirmation and send once', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-orders/po1/deliver',
        (_) => Reply.json(
          dnJson(),
          status: 201,
          delay: const Duration(seconds: 2),
        ),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);
      await tester.enterText(find.byType(TextFormField).at(0), '30');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Record delivery'));

      // Two activations before any frame is drawn. (A real second tap would land
      // on the confirmation's barrier, and `tester.tap` draws a frame, so call
      // the button's handler twice to reach the screen's own guard.)
      final press = tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Record delivery'))
          .onPressed!;
      press();
      press();
      await settle(tester);
      expect(find.text('Record this delivery?'), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'Record delivery').last);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(
        env.adapter.count('POST', 'procurement/purchase-orders/po1/deliver'),
        1,
      );
    });

    testWidgets('a refusal keeps the form and what was typed', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'procurement/purchase-orders/po1/deliver',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      await _openOrder(tester);
      await _openForm(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '30');
      await _scrollTo(tester, find.widgetWithText(InkWell, 'Record delivery'));
      await tester.tap(find.widgetWithText(InkWell, 'Record delivery'));
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Record delivery').last);
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '30'), findsOneWidget);
      expect(
        env.adapter.count('POST', 'procurement/purchase-orders/po1/deliver'),
        1,
      );
    });

    testWidgets('an order that is not waiting for a delivery says so', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'RECEIVED');
      final c = await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      c.read(routerProvider).go('/purchasing/orders/po1/receive');
      await settle(tester);

      expect(find.text('Not waiting for a delivery'), findsOneWidget);
      expect(find.text('This order is received.'), findsOneWidget);
    });

    testWidgets(
      'reaching the form by a link without materials.manage says so',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        final c = await pumpApp(
          tester,
          session: supervisorSession(perms: _viewOnly),
          env: env,
        );
        await settle(tester);
        c.read(routerProvider).go('/purchasing/orders/po1/receive');
        await settle(tester);

        expect(find.text('Not allowed'), findsOneWidget);
        expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    testWidgets('a failed load is an error with Try again', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, orderFails: true);
      final c = await pumpApp(tester, session: supervisorSession(), env: env);
      await settle(tester);
      c.read(routerProvider).go('/purchasing/orders/po1/receive');
      await settle(tester);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(
        env,
        status: 'PARTIAL',
        notes: [
          dnJson(notes: 'Two bags torn', lines: [dnLine(received: 10)]),
        ],
      );
      final capture = ErrorCapture();
      List<String> errors;
      try {
        final c = await pumpApp(
          tester,
          session: supervisorSession(),
          env: env,
          size: const Size(320, 640),
          textScale: 2.0,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await settle(tester);
        await _openOrder(tester);
        await _scrollTo(tester, find.text('DELIVERIES 1'));
        c.read(routerProvider).go('/purchasing/orders/po1/receive');
        await settle(tester);
        await tester.enterText(find.byType(TextFormField).at(0), '25');
        // Walk the whole form (drag the page itself: a notes field has a
        // scrollable of its own) so every part is laid out at this text size.
        for (var i = 0; i < 4; i++) {
          await tester.dragFrom(
            tester.getCenter(find.byType(Scaffold).last),
            const Offset(0, -700),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(find.text('Record delivery'), findsOneWidget);
        await unmount(tester);
      } finally {
        errors = capture.stop();
      }
      expect(errors, isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
