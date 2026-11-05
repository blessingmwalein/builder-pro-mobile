import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';
import '../support/test_app.dart';

SessionState accountant({List<String>? perms}) => SessionState.authenticated(
  testMe(permissions: perms ?? accountantPerms, role: 'Accountant'),
);

void financeApis(
  TestEnv env, {
  bool summaryFails = false,
  bool agingFails = false,
  bool invoicesFail = false,
  bool onlyRejectedQuote = false,
}) {
  env.adapter
    ..on(
      'GET',
      'financials/summary',
      (_) => summaryFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(financeSummaryJson()),
    )
    ..on(
      'GET',
      'invoices/aging-report',
      (_) => agingFails
          ? Reply.fail(DioExceptionType.connectionError)
          : Reply.json(agingJson()),
    )
    ..on('GET', 'invoices', (o) {
      if (invoicesFail) return Reply.fail(DioExceptionType.connectionError);
      final status = o.queryParameters['status'];
      final all = [
        invoiceJson(),
        invoiceJson(
          id: 'inv2',
          number: 'INV-2026-0002',
          status: 'OVERDUE',
          client: 'Beta Ltd',
          total: '300.00',
          paid: '0.00',
          balance: '300.00',
        ),
        invoiceJson(
          id: 'inv3',
          number: 'INV-2026-0003',
          status: 'PAID',
          client: 'Gamma Ltd',
          total: '800.00',
          paid: '800.00',
          balance: '0.00',
        ),
      ];
      return Reply.json(
        paged(
          status == null
              ? all
              : all.where((i) => i['status'] == status).toList(),
          limit: 20,
        ),
      );
    })
    ..on('GET', 'invoices/inv1', (_) => Reply.json(invoiceJson(detail: true)))
    ..on(
      'GET',
      'invoices/i-90',
      (_) => Reply.json(
        invoiceJson(
          id: 'i-90',
          number: 'INV-0003',
          status: 'OVERDUE',
          client: 'Gamma Ltd',
          detail: true,
        ),
      ),
    )
    ..on(
      'GET',
      'quotes',
      (o) => Reply.json(
        paged(
          onlyRejectedQuote
              ? [quoteJson(status: 'REJECTED')]
              : [
                  quoteJson(),
                  quoteJson(
                    id: 'q2',
                    number: 'Q-2026-0008',
                    title: 'Roofing',
                    status: 'APPROVED',
                    total: '9000.00',
                  ),
                ],
          limit: 20,
        ),
      ),
    )
    ..on(
      'GET',
      'quotes/q1',
      (_) => Reply.json(
        quoteJson(status: onlyRejectedQuote ? 'REJECTED' : 'SENT'),
      ),
    )
    ..on(
      'GET',
      'quotes/q3',
      (_) => Reply.json(quoteJson(id: 'q3', status: 'REJECTED')),
    );
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await settle(tester);
}

void main() {
  testWidgets(
    'an accountant lands on Finance: money owed and money in and out',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      await pumpApp(tester, session: accountant(), env: env);
      await settle(tester);

      expect(find.text('Amounts in USD'), findsOneWidget);
      expect(find.text('OWED TO YOU'), findsOneWidget);
      expect(find.text(r'$2,000.00'), findsOneWidget); // unpaid total
      expect(find.text(r'$1,500.00'), findsWidgets); // overdue total
      expect(find.text('Not due yet'), findsOneWidget);
      expect(find.text('Over 90 days late'), findsOneWidget);
      // Most overdue first.
      expect(find.text('Gamma Ltd'), findsOneWidget);
      expect(find.textContaining('INV-0003 · 147 days late'), findsOneWidget);
      // Money in and out.
      await tester.scrollUntilVisible(
        find.text('COLLECTED'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(r'$55,000.00'), findsOneWidget);
      expect(find.text(r'$40,000.00'), findsOneWidget);
      expect(find.text(r'$15,000.00'), findsOneWidget);
      expect(find.text(r'$60,000.00'), findsWidgets);
      // The inflated figures are never shown.
      expect(find.textContaining('999,999'), findsNothing);
      expect(find.textContaining('888,888'), findsNothing);
      expect(find.textContaining('77%'), findsNothing);
    },
  );

  testWidgets(
    'sections follow permissions: invoices only means no money in/out',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      await pumpApp(
        tester,
        session: accountant(perms: ['invoices.view']),
        env: env,
      );
      await settle(tester);

      expect(find.text('OWED TO YOU'), findsOneWidget);
      expect(find.text('MONEY IN AND OUT'), findsNothing);
      expect(
        env.adapter.requests.where((r) => r.path == 'financials/summary'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'sections follow permissions: financials only means no receivables',
    (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      await pumpApp(
        tester,
        session: accountant(perms: ['financials.view']),
        env: env,
      );
      await settle(tester);

      expect(find.text('MONEY IN AND OUT'), findsOneWidget);
      expect(find.text('OWED TO YOU'), findsNothing);
      expect(
        env.adapter.requests.where((r) => r.path == 'invoices/aging-report'),
        isEmpty,
      );
    },
  );

  testWidgets('one failing section does not hide the other', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    financeApis(env, summaryFails: true);
    await pumpApp(tester, session: accountant(), env: env);
    await settle(tester);

    expect(find.text(r'$2,000.00'), findsOneWidget); // receivables still show
    await tester.scrollUntilVisible(
      find.text('MONEY IN AND OUT'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping a most-overdue invoice opens it', (tester) async {
    final env = TestEnv();
    addTearDown(env.dispose);
    financeApis(env);
    await pumpApp(tester, session: accountant(), env: env);
    await settle(tester);

    await tester.tap(find.text('Gamma Ltd'));
    await settle(tester);
    expect(find.text('LINES'), findsOneWidget);
    expect(find.text('Balance due'), findsOneWidget);
  });

  group('invoices', () {
    testWidgets('list shows status, due date, total and what is still owing', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      await pumpApp(tester, session: accountant(), env: env);
      await settle(tester);
      await openTab(tester, 'Invoices');

      expect(find.text('Zim Properties'), findsOneWidget);
      expect(find.text('Sent'), findsWidgets);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text(r'$1,150.00'), findsOneWidget);
      expect(find.text(r'$750.00 owing'), findsOneWidget);
      // Paid in full: nothing owing is shown.
      expect(find.text(r'$800.00'), findsOneWidget);
      expect(find.textContaining('owing'), findsNWidgets(2));
    });

    testWidgets('the status chip filters through the server', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      await pumpApp(tester, session: accountant(), env: env);
      await settle(tester);
      await openTab(tester, 'Invoices');

      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Paid'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Paid'));
      await settle(tester);

      expect(env.adapter.last('GET', 'invoices').query['status'], 'PAID');
      expect(find.text('Gamma Ltd'), findsOneWidget);
      expect(find.text('Zim Properties'), findsNothing);
    });

    testWidgets(
      'detail: lines, totals, balance due, payments, no gateway data',
      (tester) async {
        final env = TestEnv();
        addTearDown(env.dispose);
        financeApis(env);
        await pumpApp(tester, session: accountant(), env: env);
        await settle(tester);
        await openTab(tester, 'Invoices');
        await tester.tap(find.text('Zim Properties'));
        await settle(tester);

        expect(find.text('INV-2026-0001'), findsWidgets);
        expect(find.text('Concrete supply'), findsOneWidget);
        expect(find.text('10 m3 × \$85.00'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Balance due'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(r'$750.00'), findsOneWidget);
        expect(find.text('Retention 5% applies.'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.textContaining('REF-123'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.textContaining('Bank Transfer'), findsOneWidget);
        expect(find.textContaining('SECRET'), findsNothing);
        expect(find.textContaining('tok_'), findsNothing);
        expect(find.textContaining('secret street'), findsNothing);
      },
    );

    testWidgets('a failed load is an error with Retry, not "no invoices"', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env, invoicesFail: true);
      await pumpApp(tester, session: accountant(), env: env);
      await settle(tester);
      await openTab(tester, 'Invoices');

      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No invoices yet'), findsNothing);
    });
  });

  group('quotes', () {
    testWidgets('list and detail, including discount and tax lines', (
      tester,
    ) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      await pumpApp(tester, session: accountant(), env: env);
      await settle(tester);
      await openTab(tester, 'Quotes');

      expect(find.text('Foundation works'), findsOneWidget);
      expect(find.text('Roofing'), findsOneWidget);
      expect(find.text(r'$5,750.00'), findsOneWidget);
      expect(find.text('Approved'), findsWidgets);

      await tester.tap(find.text('Foundation works'));
      await settle(tester);
      expect(find.text('Excavation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Tax (15%)'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Tax (15%)'), findsOneWidget);
      expect(find.text(r'$1,000.00'), findsOneWidget);
      expect(find.text(r'-$250.00'), findsOneWidget);
      expect(find.text(r'$5,750.00'), findsWidgets);
      expect(find.textContaining('done on the web app'), findsOneWidget);
    });

    testWidgets('a rejected quote shows why', (tester) async {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env, onlyRejectedQuote: true);
      await pumpApp(tester, session: accountant(), env: env);
      await settle(tester);
      await openTab(tester, 'Quotes');
      await tester.tap(find.text('Foundation works'));
      await settle(tester);

      expect(find.text('WHY IT WAS REJECTED'), findsOneWidget);
      expect(find.text('Too expensive'), findsOneWidget);
    });
  });

  testWidgets('large text on a small phone, both themes, without overflow', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      final env = TestEnv();
      addTearDown(env.dispose);
      financeApis(env);
      final capture = ErrorCapture();
      await pumpApp(
        tester,
        session: accountant(),
        env: env,
        size: const Size(320, 640),
        textScale: 2.0,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      await settle(tester);
      expect(find.text('OWED TO YOU'), findsOneWidget);
      await openTab(tester, 'Invoices');
      await tester.tap(find.text('Zim Properties'));
      await settle(tester);
      await unmount(tester);
      expect(capture.stop(), isEmpty, reason: dark ? 'dark' : 'light');
    }
  });
}
