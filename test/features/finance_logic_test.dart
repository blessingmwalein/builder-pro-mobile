import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/core/utils/format.dart';
import 'package:builder_pro_mobile/features/finance/application/finance_providers.dart';
import 'package:builder_pro_mobile/features/finance/data/finance_models.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('money formatting', () {
    test('uses the company currency with two decimals and grouping', () {
      expect(Fmt.money(1234.5, 'USD'), r'$1,234.50');
      expect(Fmt.money(0, 'USD'), r'$0.00');
      expect(Fmt.money(-12, 'USD'), contains('12.00'));
      expect(
        Fmt.money(1234.5, 'ZWL'),
        allOf(contains('ZWL'), contains('1,234.50')),
      );
    });

    test('a blank currency falls back to USD; case is ignored', () {
      expect(Fmt.money(5, ''), r'$5.00');
      expect(Fmt.money(5, 'usd'), r'$5.00');
    });

    test('percent drops a trailing .0', () {
      expect(Fmt.percent(12), '12%');
      expect(Fmt.percent(12.5), '12.5%');
      expect(Fmt.percent(12.04), '12%');
    });

    test(
      'the currency provider reads the tenant currency from the session',
      () {
        final c = makeContainer(env, perms: accountantPerms);
        addTearDown(c.dispose);
        expect(c.read(currencyProvider), 'USD');
      },
    );
  });

  group('overview', () {
    test('summary reads collected, costs, profit and budget', () async {
      env.adapter.on(
        'GET',
        'financials/summary',
        (_) => Reply.json(financeSummaryJson()),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(financeSummaryProvider, (_, _) {});

      final s = await c.read(financeSummaryProvider.future);

      expect(s.collected, 55000);
      expect(s.actualCost, 40000);
      expect(s.profit, 15000);
      expect(s.budgetPlanned, 100000);
      expect(s.budgetLeft, 60000);
    });

    test(
      'the inflated "expected" and "outstanding" figures are not carried over',
      () {
        final dump = FinanceSummary.parse(financeSummaryJson()).toString();
        expect(dump, isNot(contains('999999')));
        expect(dump, isNot(contains('888888')));
      },
    );

    test('aging totals, buckets and entries (most overdue first)', () async {
      env.adapter.on(
        'GET',
        'invoices/aging-report',
        (_) => Reply.json(agingJson()),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(agingReportProvider, (_, _) {});

      final a = await c.read(agingReportProvider.future);

      expect(a.notDue, 500);
      expect(a.days1to30, 300);
      expect(a.over90, 1200);
      expect(a.total, 2000);
      expect(a.overdue, 1500);
      expect(a.entries.map((e) => e.number), [
        'INV-0003',
        'INV-0002',
        'INV-0001',
      ]);
      expect(a.entries.first.isOverdue, isTrue);
      expect(a.entries.last.isOverdue, isFalse);
    });

    test('an empty aging report is zeros, not an error', () {
      final a = AgingReport.parse({'buckets': {}, 'totals': {}});
      expect(a.total, 0);
      expect(a.entries, isEmpty);
    });

    test('a failed summary is an error for the screen to show', () async {
      env.adapter.on(
        'GET',
        'financials/summary',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(financeSummaryProvider, (_, _) {});
      await expectLater(
        c.read(financeSummaryProvider.future),
        throwsA(isA<AppException>()),
      );
    });

    test(
      '403 on the summary (no financials.view) is a forbidden error',
      () async {
        env.adapter.on(
          'GET',
          'financials/summary',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: accountantPerms);
        addTearDown(c.dispose);
        c.listen(financeSummaryProvider, (_, _) {});
        await expectLater(
          c.read(financeSummaryProvider.future),
          throwsA(
            isA<AppException>().having(
              (e) => e.kind,
              'kind',
              AppErrorKind.forbidden,
            ),
          ),
        );
      },
    );
  });

  group('invoices', () {
    test('list sends page and limit and parses string money', () async {
      env.adapter.on(
        'GET',
        'invoices',
        (_) => Reply.json(paged([invoiceJson()], limit: 20)),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoicesCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);

      final q = env.adapter.last('GET', 'invoices').query;
      expect(q['page'], 1);
      expect(q['limit'], 20);
      expect(q.containsKey('status'), isFalse);
      final i = c.read(invoicesCatalogProvider).items.single;
      expect(i.total, 1150);
      expect(i.paid, 400);
      expect(i.balance, 750);
      expect(i.clientName, 'Zim Properties');
    });

    test('the status filter goes to the server', () async {
      env.adapter.on(
        'GET',
        'invoices',
        (_) => Reply.json(paged([invoiceJson()], limit: 20)),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoicesCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);

      await c.read(invoicesCatalogProvider.notifier).setFilter('OVERDUE');

      expect(env.adapter.last('GET', 'invoices').query['status'], 'OVERDUE');
      expect(c.read(invoicesCatalogProvider).filter, 'OVERDUE');
    });

    test('a newer filter wins over a slow older reply', () async {
      env.adapter
        ..on('GET', 'invoices', (_) => Reply.json(paged([])))
        ..on(
          'GET',
          'invoices',
          (_) => Reply.json(
            paged([invoiceJson(id: 'old')]),
            delay: const Duration(milliseconds: 300),
          ),
        )
        ..on(
          'GET',
          'invoices',
          (_) => Reply.json(paged([invoiceJson(id: 'new')])),
        );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoicesCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);

      final n = c.read(invoicesCatalogProvider.notifier);
      await Future.wait([n.setFilter('PAID'), n.setFilter('SENT')]);

      expect(c.read(invoicesCatalogProvider).items.map((i) => i.id), ['new']);
      expect(c.read(invoicesCatalogProvider).filter, 'SENT');
    });

    test('load more appends without duplicates', () async {
      env.adapter
        ..on(
          'GET',
          'invoices',
          (_) => Reply.json(paged([invoiceJson(id: 'a')], limit: 1, total: 2)),
        )
        ..on(
          'GET',
          'invoices',
          (_) => Reply.json(
            paged(
              [invoiceJson(id: 'a'), invoiceJson(id: 'b')],
              page: 2,
              limit: 1,
              total: 2,
            ),
          ),
        );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoicesCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      await c.read(invoicesCatalogProvider.notifier).loadMore();
      expect(c.read(invoicesCatalogProvider).items.map((i) => i.id), [
        'a',
        'b',
      ]);
    });

    test('a failed first page is an error, never an empty list', () async {
      env.adapter.on(
        'GET',
        'invoices',
        (_) => Reply.fail(DioExceptionType.connectionError),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoicesCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      final s = c.read(invoicesCatalogProvider);
      expect(s.error?.kind, AppErrorKind.offline);
      expect(s.items, isEmpty);
      expect(s.loading, isFalse);
    });

    test(
      'detail reads lines, totals, payments and the quote it came from',
      () async {
        env.adapter.on(
          'GET',
          'invoices/inv1',
          (_) => Reply.json(invoiceJson(detail: true)),
        );
        final c = makeContainer(env, perms: accountantPerms);
        addTearDown(c.dispose);
        c.listen(invoiceDetailProvider('inv1'), (_, _) {});

        final d = await c.read(invoiceDetailProvider('inv1').future);

        expect(d.lines.map((l) => l.description), [
          'Concrete supply',
          'Labour',
        ]);
        expect(d.lines.first.quantity, 10);
        expect(d.lines.first.unit, 'm3');
        expect(d.subtotal, 1000);
        expect(d.tax, 150);
        expect(d.retentionPercent, 5);
        expect(d.quoteNumber, 'Q-2026-0007');
        expect(d.clientContact, 'Chipo Dube');
        expect(d.payments.single.amount, 400);
        expect(d.payments.single.reference, 'REF-123');
      },
    );

    test('raw gateway data on a payment is never read', () {
      final d = InvoiceDetail.tryParse(invoiceJson(detail: true))!;
      final dump = [
        d.payments.map((p) => '${p.method} ${p.status} ${p.reference}').join(),
        d.summary.clientName,
      ].join(' ');
      expect(dump, isNot(contains('SECRET')));
      expect(dump, isNot(contains('tok_')));
      // Client address and phone from the full client record are not read either.
      expect(dump, isNot(contains('secret street')));
    });

    test('a malformed reply is an error', () async {
      env.adapter.on(
        'GET',
        'invoices/x',
        (_) => Reply.json({'unexpected': true}),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoiceDetailProvider('x'), (_, _) {});
      await expectLater(
        c.read(invoiceDetailProvider('x').future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.malformed,
          ),
        ),
      );
    });

    test('a missing invoice (404) is reported as not found', () async {
      env.adapter.on(
        'GET',
        'invoices/gone',
        (_) => Reply.json({
          'statusCode': 404,
          'message': 'Invoice not found',
        }, status: 404),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(invoiceDetailProvider('gone'), (_, _) {});
      await expectLater(
        c.read(invoiceDetailProvider('gone').future),
        throwsA(
          isA<AppException>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.notFound,
          ),
        ),
      );
    });
  });

  group('quotes', () {
    test('list sends page and limit and the status filter', () async {
      env.adapter.on(
        'GET',
        'quotes',
        (_) => Reply.json(paged([quoteJson()], limit: 20)),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(quotesCatalogProvider, (_, _) {});
      await pumpEventQueue(times: 20);
      expect(env.adapter.last('GET', 'quotes').query['limit'], 20);

      await c.read(quotesCatalogProvider.notifier).setFilter('APPROVED');
      expect(env.adapter.last('GET', 'quotes').query['status'], 'APPROVED');
      expect(c.read(quotesCatalogProvider).items.single.total, 5750);
    });

    test('detail reads totals, discount, tax and rejection notes', () async {
      env.adapter.on(
        'GET',
        'quotes/q9',
        (_) => Reply.json(quoteJson(id: 'q9', status: 'REJECTED')),
      );
      final c = makeContainer(env, perms: accountantPerms);
      addTearDown(c.dispose);
      c.listen(quoteDetailProvider('q9'), (_, _) {});

      final d = await c.read(quoteDetailProvider('q9').future);

      expect(d.subtotal, 5000);
      expect(d.discount, 250);
      expect(d.tax, 1000);
      expect(d.taxRate, 15);
      expect(d.summary.total, 5750);
      expect(d.rejectionNotes, 'Too expensive');
      expect(d.lines.single.description, 'Excavation');
    });

    test('rows without an id are skipped', () {
      expect(QuoteSummary.tryParse({'title': 'no id'}), isNull);
      expect(InvoiceSummary.tryParse(null), isNull);
    });
  });
}
