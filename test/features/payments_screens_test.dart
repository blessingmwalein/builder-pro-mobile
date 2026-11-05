import 'package:builder_pro_mobile/app/router/app_router.dart'
    show routerProvider;
import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/shared/components/app_button.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

SessionState _as(List<String> perms) =>
    SessionState.authenticated(testMe(permissions: perms, role: 'Accountant'));

/// Can see invoices but not record payments.
const _viewOnly = ['invoices.view', 'financials.view'];

/// `inv1`: total 1150, 400 paid, 750 due, unless a test says otherwise.
void _apis(
  TestEnv env, {
  String status = 'SENT',
  String paid = '400.00',
  String balance = '750.00',
  bool detailFails = false,
}) {
  env.adapter
    ..on('GET', 'financials/summary', (_) => Reply.json(financeSummaryJson()))
    ..on('GET', 'invoices/aging-report', (_) => Reply.json(agingJson()))
    ..on(
      'GET',
      'invoices',
      (_) => Reply.json(
        paged([
          invoiceJson(status: status, paid: paid, balance: balance),
        ], limit: 20),
      ),
    )
    ..on(
      'GET',
      'invoices/inv1',
      (_) => detailFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(
              invoiceJson(
                detail: true,
                status: status,
                paid: paid,
                balance: balance,
              ),
            ),
    );
}

Future<void> _openInvoice(WidgetTester tester) async {
  await tester.tap(find.text('Invoices').last);
  await settle(tester);
  await tester.tap(find.text('Zim Properties').first);
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
  await _scrollTo(tester, find.widgetWithText(InkWell, 'Record a payment'));
  await tester.tap(find.widgetWithText(InkWell, 'Record a payment'));
  await settle(tester);
  expect(find.text('Payment for INV-2026-0001'), findsOneWidget);
}

Finder get _record => find.widgetWithText(InkWell, 'Record payment');

void main() {
  group('invoice detail', () {
    testWidgets(
      'an open invoice offers to record a payment, and shows no gateway data',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: _as(accountantPerms), env: env);
        await settle(tester);
        await _openInvoice(tester);

        await _scrollTo(tester, find.text('Record a payment'));
        expect(find.text('Record a payment'), findsOneWidget);
        expect(find.textContaining('4111'), findsNothing);
        expect(find.textContaining('tok_secret'), findsNothing);
        expect(
          find.textContaining('PayNow or EcoCash, and voiding'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a role that cannot mark invoices paid sees no button', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(_viewOnly), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _scrollTo(tester, find.textContaining('done on the web app'));
      expect(find.text('Record a payment'), findsNothing);
    });

    testWidgets('a paid, draft, void or settled invoice has no button', (
      tester,
    ) async {
      for (final c in {
        'PAID': ('PAID', '1150.00', '0.00'),
        'DRAFT': ('DRAFT', '0.00', '1150.00'),
        'VOID': ('VOID', '0.00', '1150.00'),
        'SENT with nothing owed': ('SENT', '1150.00', '0.00'),
      }.entries) {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env, status: c.value.$1, paid: c.value.$2, balance: c.value.$3);
        await pumpApp(tester, session: _as(accountantPerms), env: env);
        await settle(tester);
        await _openInvoice(tester);
        await _scrollTo(tester, find.textContaining('done on the web app'));
        expect(find.text('Record a payment'), findsNothing, reason: c.key);
        await unmount(tester);
      }
    });
  });

  group('record a payment', () {
    testWidgets('shows what is owed and offers cash and bank transfer only', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      expect(find.text(r'$750.00'), findsWidgets);
      expect(find.widgetWithText(ChoiceChip, 'Bank transfer'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Cash'), findsOneWidget);
      expect(find.text('PayNow'), findsNothing);
      expect(find.text('EcoCash'), findsNothing);
    });

    testWidgets('nothing chosen is stopped before anything is sent', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      await _scrollTo(tester, _record);
      await tester.tap(_record);
      await settle(tester);

      expect(find.text('Choose how it was paid'), findsOneWidget);
      expect(find.text('Enter the amount received'), findsOneWidget);
      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('more than is owed is refused on the field', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '750.01');
      await _scrollTo(tester, _record);
      await tester.tap(_record);
      await settle(tester);

      expect(find.textContaining('more than the balance due'), findsOneWidget);
      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('"The full balance" fills in what is owed', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      await _scrollTo(tester, find.text('The full balance'));
      await tester.tap(find.text('The full balance'));
      await tester.pump();

      expect(find.widgetWithText(TextFormField, '750.00'), findsOneWidget);
    });

    testWidgets(
      'confirms the amount, method, invoice and the new balance first',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        await pumpApp(tester, session: _as(accountantPerms), env: env);
        await settle(tester);
        await _openInvoice(tester);
        await _openForm(tester);

        await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField).first, '100');
        await _scrollTo(tester, _record);
        await tester.tap(_record);
        await settle(tester);

        expect(find.text('Record this payment?'), findsOneWidget);
        expect(
          find.textContaining(
            r'$100.00 by cash on INV-2026-0001 from Zim Properties',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(r'The balance due becomes $650.00'),
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

    testWidgets('paying the whole balance says it settles the invoice', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Bank transfer'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '750');
      await _scrollTo(tester, _record);
      await tester.tap(_record);
      await settle(tester);

      expect(find.textContaining('pays the invoice in full'), findsOneWidget);
      expect(find.textContaining('by bank transfer'), findsOneWidget);
    });

    testWidgets('records the payment once and goes back to the invoice', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'invoices/inv1/payments',
        (_) => Reply.json(payJson(), status: 201),
      );
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '100');
      await _scrollTo(tester, _record);
      await tester.tap(_record);
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Record payment').last);
      await settle(tester, frames: 20);

      expect(env.adapter.count('POST', 'invoices/inv1/payments'), 1);
      expect(env.adapter.last('POST', 'invoices/inv1/payments').data, {
        'method': 'CASH',
        'amount': 100.0,
      });
      expect(find.text('Payment recorded.'), findsOneWidget);
      expect(find.text('Payment for INV-2026-0001'), findsNothing);
    });

    testWidgets(
      'two activations in one frame open one confirmation and send once',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        _apis(env);
        env.adapter.on(
          'POST',
          'invoices/inv1/payments',
          (_) => Reply.json(
            payJson(),
            status: 201,
            delay: const Duration(seconds: 2),
          ),
        );
        await pumpApp(tester, session: _as(accountantPerms), env: env);
        await settle(tester);
        await _openInvoice(tester);
        await _openForm(tester);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
        await tester.pump();
        await tester.enterText(find.byType(TextFormField).first, '100');
        await _scrollTo(tester, _record);

        // Two activations before any frame is drawn (the second tap of a real
        // double tap would land on the confirmation's barrier).
        final press = tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Record payment'))
            .onPressed!;
        press();
        press();
        await settle(tester);
        expect(find.text('Record this payment?'), findsOneWidget);

        await tester.tap(find.widgetWithText(InkWell, 'Record payment').last);
        await tester.pump(const Duration(seconds: 3));
        await settle(tester);

        expect(env.adapter.count('POST', 'invoices/inv1/payments'), 1);
      },
    );

    testWidgets('a refusal keeps the form and what was typed', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      env.adapter.on(
        'POST',
        'invoices/inv1/payments',
        (_) => Reply.json({'statusCode': 403}, status: 403),
      );
      await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      await _openInvoice(tester);
      await _openForm(tester);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, '100');
      await _scrollTo(tester, _record);
      await tester.tap(_record);
      await settle(tester);
      await tester.tap(find.widgetWithText(InkWell, 'Record payment').last);
      await settle(tester);

      expect(find.textContaining("don't have permission"), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '100'), findsOneWidget);
      expect(env.adapter.count('POST', 'invoices/inv1/payments'), 1);
    });

    testWidgets('an invoice that is not open says so', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, status: 'PAID', paid: '1150.00', balance: '0.00');
      final c = await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      c.read(routerProvider).go('/invoices/inv1/pay');
      await settle(tester);

      expect(find.text('Not open for payments'), findsOneWidget);
      expect(find.text('Nothing is owed on this invoice.'), findsOneWidget);
    });

    testWidgets('reaching the form by a link without the right says so', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env);
      final c = await pumpApp(tester, session: _as(_viewOnly), env: env);
      await settle(tester);
      c.read(routerProvider).go('/invoices/inv1/pay');
      await settle(tester);

      expect(find.text('Not allowed'), findsOneWidget);
      expect(env.adapter.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('a failed load is an error with Try again', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      _apis(env, detailFails: true);
      final c = await pumpApp(tester, session: _as(accountantPerms), env: env);
      await settle(tester);
      c.read(routerProvider).go('/invoices/inv1/pay');
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
      _apis(env);
      final capture = ErrorCapture();
      List<String> errors;
      try {
        final c = await pumpApp(
          tester,
          session: _as(accountantPerms),
          env: env,
          size: const Size(320, 640),
          textScale: 2.0,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await settle(tester);
        await _openInvoice(tester);
        await _scrollTo(tester, find.text('Record a payment'));
        c.read(routerProvider).go('/invoices/inv1/pay');
        await settle(tester);
        // At this text size the chips are below the fold of a lazy list.
        await _scrollTo(tester, find.widgetWithText(ChoiceChip, 'Cash'));
        await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
        await tester.pump();
        // Drag the page itself (the amount field has a scrollable of its own).
        for (var i = 0; i < 3; i++) {
          await tester.dragFrom(
            tester.getCenter(find.byType(Scaffold).last),
            const Offset(0, -700),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(find.text('Record payment'), findsOneWidget);
        await unmount(tester);
      } finally {
        errors = capture.stop();
      }
      expect(errors, isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
