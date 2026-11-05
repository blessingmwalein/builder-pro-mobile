import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:builder_pro_mobile/features/finance/application/finance_providers.dart';
import 'package:builder_pro_mobile/features/finance/application/payment_actions.dart';
import 'package:builder_pro_mobile/features/finance/data/finance_models.dart';
import 'package:builder_pro_mobile/features/finance/presentation/record_payment_screen.dart';
import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';

import '../support/api_fixtures.dart';
import '../support/fake_adapter.dart';
import '../support/fakes.dart';
import '../support/fixtures.dart';

Matcher _fails(AppErrorKind kind, {String? containing}) => isA<AppException>()
    .having((e) => e.kind, 'kind', kind)
    .having((e) => e.message, 'message', contains(containing ?? ''));

/// `inv1`: total 1150, 400 paid, 750 due (unless a test says otherwise).
Map<String, dynamic> _invoice({
  String status = 'SENT',
  String paid = '400.00',
  String balance = '750.00',
  List<Map<String, dynamic>>? payments,
}) => invoiceJson(
  detail: true,
  status: status,
  paid: paid,
  balance: balance,
  payments: payments,
);

void main() {
  late TestEnv env;
  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  group('models', () {
    InvoiceSummary parse(String status, String balance) =>
        InvoiceSummary.tryParse(invoiceJson(status: status, balance: balance))!;

    test(
      'only a sent, part-paid or overdue invoice with a balance is open',
      () {
        for (final e in {
          'SENT': true,
          'PARTIALLY_PAID': true,
          'OVERDUE': true,
          'DRAFT': false,
          'PAID': false,
          'VOID': false,
        }.entries) {
          expect(
            parse(e.key, '750.00').isOpenForPayment,
            e.value,
            reason: e.key,
          );
        }
      },
    );

    test('nothing owed means not open, even for a sent invoice', () {
      expect(parse('SENT', '0.00').isOpenForPayment, isFalse);
      expect(parse('SENT', '0.004').isOpenForPayment, isFalse);
      expect(parse('SENT', '0.01').isOpenForPayment, isTrue);
    });

    test('the app records cash and bank transfers only', () {
      expect(ManualPayment.all, ['BANK_TRANSFER', 'CASH']);
      expect(ManualPayment.all, isNot(contains('PAYNOW')));
      expect(ManualPayment.all, isNot(contains('ECOCASH')));
      expect(ManualPayment.label('BANK_TRANSFER'), 'Bank transfer');
      expect(ManualPayment.label('CASH'), 'Cash');
      expect(ManualPayment.label('ECOCASH'), 'EcoCash');
    });

    test('money is kept to the cent', () {
      expect(roundMoney(100.004), 100.0);
      expect(roundMoney(99.999), 100.0);
      expect(roundMoney(0.1 + 0.2), 0.3);
    });

    test('a payment reads its amount, method, status, date and reference', () {
      final p = PaymentRecord.tryParse(
        payJson(amount: 100, paidAt: DateTime.utc(2026, 10, 20, 9)),
      )!;
      expect(p.amount, 100);
      expect(p.method, 'CASH');
      expect(p.status, PaymentRecord.success);
      expect(p.paidAt, DateTime.utc(2026, 10, 20, 9));
      expect(p.reference, 'MANUAL-pay2');
    });
  });

  group('form validation', () {
    test('a positive amount, two decimals, no more than is owed', () {
      expect(validatePaymentAmount('', 750), isNotNull);
      expect(validatePaymentAmount('abc', 750), 'Enter an amount');
      expect(validatePaymentAmount('0', 750), 'Enter more than zero');
      expect(validatePaymentAmount('-5', 750), 'Enter more than zero');
      expect(validatePaymentAmount('100.123', 750), 'Use at most 2 decimals');
      expect(
        validatePaymentAmount('750.01', 750),
        contains('more than the balance'),
      );
      expect(validatePaymentAmount('100', 750), isNull);
      expect(validatePaymentAmount('100,50', 750), isNull);
      expect(validatePaymentAmount('750', 750), isNull);
    });
  });

  group('recording a payment', () {
    Future<String?> record(
      dynamic c, {
      String method = 'CASH',
      double amount = 100,
    }) => c
        .read(paymentActionsProvider)
        .record('inv1', method: method, amount: amount);

    void invoice(Map<String, dynamic> json) =>
        env.adapter.on('GET', 'invoices/inv1', (_) => Reply.json(json));

    void paymentOk() => env.adapter.on(
      'POST',
      'invoices/inv1/payments',
      (_) => Reply.json(payJson(), status: 201),
    );

    List<Recorded> requests() => env.adapter.requests;
    List<Recorded> posts() =>
        env.adapter.requests.where((r) => r.method == 'POST').toList();

    test(
      're-reads the invoice, then sends only the method and the amount',
      () async {
        invoice(_invoice());
        paymentOk();
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);

        expect(await record(c), isNull);

        expect(env.adapter.count('GET', 'invoices/inv1'), 1);
        expect(env.adapter.last('POST', 'invoices/inv1/payments').data, {
          'method': 'CASH',
          'amount': 100.0,
        });
        expect(posts(), hasLength(1));
      },
    );

    test('the amount goes to the cent', () async {
      invoice(_invoice());
      paymentOk();
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      await record(c, amount: 99.999);
      expect(
        (env.adapter.last('POST', 'invoices/inv1/payments').data
            as Map)['amount'],
        100.0,
      );
    });

    test('the full balance is allowed', () async {
      invoice(_invoice());
      paymentOk();
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      await record(c, amount: 750);
      expect(posts(), hasLength(1));
    });

    test('PayNow, EcoCash, card and anything else are never sent', () async {
      invoice(_invoice());
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      for (final method in ['PAYNOW', 'ECOCASH', 'CARD', 'OTHER']) {
        await expectLater(
          record(c, method: method),
          throwsA(_fails(AppErrorKind.validation, containing: 'web app')),
          reason: method,
        );
      }
      expect(requests(), isEmpty);
    });

    test('a zero, negative or absurd amount is never sent', () async {
      invoice(_invoice());
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      for (final amount in [0.0, -5.0, 0.004, double.nan, 2e9]) {
        await expectLater(
          record(c, amount: amount),
          throwsA(
            _fails(AppErrorKind.validation, containing: 'greater than zero'),
          ),
          reason: '$amount',
        );
      }
      expect(requests(), isEmpty);
    });

    test('an invoice that is not open for payments is never sent to', () async {
      for (final entry in {
        'DRAFT': ('DRAFT', '750.00'),
        'VOID': ('VOID', '750.00'),
        'PAID': ('PAID', '0.00'),
        'SENT with nothing owed': ('SENT', '0.00'),
      }.entries) {
        final e = TestEnv();
        addTearDown(e.dispose);
        e.adapter.on(
          'GET',
          'invoices/inv1',
          (_) => Reply.json(
            _invoice(status: entry.value.$1, balance: entry.value.$2),
          ),
        );
        final c = makeContainer(e, perms: ownerPerms);
        addTearDown(c.dispose);
        await expectLater(
          c
              .read(paymentActionsProvider)
              .record('inv1', method: 'CASH', amount: 100),
          throwsA(
            _fails(AppErrorKind.validation, containing: 'no longer open'),
          ),
          reason: entry.key,
        );
        expect(
          e.adapter.requests.where((r) => r.method == 'POST'),
          isEmpty,
          reason: entry.key,
        );
      }
    });

    test('more than the balance now (a payment was recorded meanwhile) is never sent', () async {
      // the form showed 750 due; now only 250 is
      invoice(_invoice(paid: '900.00', balance: '250.00'));
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      await expectLater(
        record(c, amount: 300),
        throwsA(_fails(AppErrorKind.validation, containing: r'$250.00')),
      );
      expect(posts(), isEmpty);
    });

    test(
      'offline when re-reading: a plain error and nothing is sent',
      () async {
        env.adapter.on(
          'GET',
          'invoices/inv1',
          (_) => Reply.fail(DioExceptionType.connectionError),
        );
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);
        await expectLater(record(c), throwsA(_fails(AppErrorKind.offline)));
        expect(posts(), isEmpty);
      },
    );

    test(
      'a refusal (403) is shown, never retried, and not "recovered"',
      () async {
        invoice(_invoice());
        env.adapter.on(
          'POST',
          'invoices/inv1/payments',
          (_) => Reply.json({'statusCode': 403}, status: 403),
        );
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);
        await expectLater(record(c), throwsA(_fails(AppErrorKind.forbidden)));
        expect(posts(), hasLength(1));
        expect(env.adapter.count('GET', 'invoices/inv1'), 1);
      },
    );

    test('a 400 on an invoice that has since closed says so', () async {
      env.adapter
        ..on('GET', 'invoices/inv1', (_) => Reply.json(_invoice()))
        ..on(
          'GET',
          'invoices/inv1',
          (_) => Reply.json(
            _invoice(status: 'PAID', paid: '1150.00', balance: '0.00'),
          ),
        )
        ..on(
          'POST',
          'invoices/inv1/payments',
          (_) => Reply.json({'statusCode': 400, 'message': 'x'}, status: 400),
        );
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      await expectLater(
        record(c),
        throwsA(_fails(AppErrorKind.validation, containing: 'changed since')),
      );
    });

    test(
      'any other 400 keeps the server words (the invoice is still open)',
      () async {
        invoice(_invoice());
        env.adapter.on(
          'POST',
          'invoices/inv1/payments',
          (_) => Reply.json({
            'statusCode': 400,
            'message': [
              'amount must be a number conforming to the specified constraints',
            ],
          }, status: 400),
        );
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);
        await expectLater(
          record(c),
          throwsA(
            _fails(AppErrorKind.validation, containing: 'amount must be'),
          ),
        );
      },
    );

    group('after a timeout the invoice is read back, never resent', () {
      void timeoutThen(List<Map<String, dynamic>> afterPayments) {
        env.adapter
          ..on('GET', 'invoices/inv1', (_) => Reply.json(_invoice()))
          ..on(
            'GET',
            'invoices/inv1',
            (_) => Reply.json(_invoice(payments: afterPayments)),
          )
          ..on(
            'POST',
            'invoices/inv1/payments',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
      }

      final existing = {
        'id': 'pay1',
        'amount': '400.00',
        'method': 'BANK_TRANSFER',
        'status': 'SUCCESS',
        'transactionRef': 'REF-123',
        'paidAt': DateTime(2026, 9, 20).toUtc().toIso8601String(),
      };

      test('a new payment of mine just now: reported as done', () async {
        timeoutThen([existing, payJson()]);
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);
        expect(await record(c), contains('we checked'));
        expect(posts(), hasLength(1));
      });

      test(
        'no new payment: nothing was recorded and a retry is safe',
        () async {
          timeoutThen([existing]);
          final c = makeContainer(env, perms: ownerPerms);
          addTearDown(c.dispose);
          await expectLater(
            record(c),
            throwsA(
              _fails(
                AppErrorKind.timeout,
                containing: 'no payment was recorded',
              ),
            ),
          );
          expect(posts(), hasLength(1));
        },
      );

      test('an old payment that was already there is not mistaken for the new one', () async {
        // the attempt matches pay1 exactly, but pay1 was already on the invoice
        timeoutThen([existing]);
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);
        await expectLater(
          record(c, method: 'BANK_TRANSFER', amount: 400),
          throwsA(
            _fails(AppErrorKind.timeout, containing: 'no payment was recorded'),
          ),
        );
      });

      // One disqualifier per case: each would be accepted if its own check were
      // dropped. Every one must read as a conflict, never as "done" (the user
      // would think a payment is recorded that is not) and never as "nothing
      // recorded" (a retry would pay on top of someone else's payment).
      final notMine = <String, Map<String, dynamic>>{
        'a different amount': payJson(amount: 120),
        'a different method': payJson(method: 'BANK_TRANSFER'),
        'one that has not been received (PENDING)': payJson(status: 'PENDING'),
        'one from two days ago': payJson(
          paidAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      };
      for (final entry in notMine.entries) {
        test('is not mistaken for mine: ${entry.key}', () async {
          timeoutThen([existing, entry.value]);
          final c = makeContainer(env, perms: ownerPerms);
          addTearDown(c.dispose);
          await expectLater(
            record(c),
            throwsA(
              _fails(
                AppErrorKind.validation,
                containing: 'A different payment was recorded',
              ),
            ),
          );
          expect(posts(), hasLength(1));
        });
      }

      test('the check also fails: the outcome stays unknown', () async {
        env.adapter
          ..on('GET', 'invoices/inv1', (_) => Reply.json(_invoice()))
          ..on(
            'GET',
            'invoices/inv1',
            (_) => Reply.fail(DioExceptionType.connectionError),
          )
          ..on(
            'POST',
            'invoices/inv1/payments',
            (_) => Reply.fail(DioExceptionType.receiveTimeout),
          );
        final c = makeContainer(env, perms: ownerPerms);
        addTearDown(c.dispose);
        await expectLater(
          record(c),
          throwsA(
            isA<AppException>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              isTrue,
            ),
          ),
        );
        expect(posts(), hasLength(1));
      });
    });

    test('a recorded payment reloads the invoice, the list, the summary and the receivables', () async {
      invoice(_invoice());
      paymentOk();
      env.adapter
        ..on(
          'GET',
          'invoices',
          (_) => Reply.json(paged([invoiceJson()], limit: 20)),
        )
        ..on('GET', 'financials/summary', (_) => Reply.json({}))
        ..on('GET', 'invoices/aging-report', (_) => Reply.json(agingJson()));
      final c = makeContainer(env, perms: ownerPerms);
      addTearDown(c.dispose);
      c.listen(invoicesCatalogProvider, (_, _) {});
      c.listen(financeSummaryProvider, (_, _) {});
      c.listen(agingReportProvider, (_, _) {});
      c.listen(invoiceDetailProvider('inv1'), (_, _) {});
      await pumpEventQueue(times: 30);
      final before = {
        'list': env.adapter.count('GET', 'invoices'),
        'summary': env.adapter.count('GET', 'financials/summary'),
        'aging': env.adapter.count('GET', 'invoices/aging-report'),
        'detail': env.adapter.count('GET', 'invoices/inv1'),
      };

      await record(c);
      await pumpEventQueue(times: 30);

      expect(env.adapter.count('GET', 'invoices'), before['list']! + 1);
      expect(
        env.adapter.count('GET', 'financials/summary'),
        before['summary']! + 1,
      );
      expect(
        env.adapter.count('GET', 'invoices/aging-report'),
        before['aging']! + 1,
      );
      // the action's own re-read, plus the detail reloading
      expect(
        env.adapter.count('GET', 'invoices/inv1'),
        greaterThan(before['detail']! + 1),
      );
    });
  });
}
