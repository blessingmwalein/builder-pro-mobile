import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/core/errors/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_app.dart';

void main() {
  testWidgets(
    'Worker sees the four field tabs plus More, and no office modules',
    (tester) async {
      await pumpApp(tester, session: SessionState.authenticated(testMe()));

      for (final label in [
        'Clock',
        'My Tasks',
        'Materials',
        'Messages',
        'More',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Invoices'), findsNothing);
      expect(find.text('Financials'), findsNothing);
    },
  );

  testWidgets('Accountant lands on Finance with finance tabs, no field tabs', (
    tester,
  ) async {
    await pumpApp(
      tester,
      session: SessionState.authenticated(
        testMe(permissions: accountantPerms, role: 'Accountant'),
      ),
    );

    for (final label in ['Finance', 'Invoices', 'Quotes', 'Requests', 'More']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Clock'), findsNothing);
    expect(find.text('My Tasks'), findsNothing);
    expect(find.text('Today'), findsNothing);
  });

  testWidgets('Accountant: Reports is in the app, nothing is left as web-only', (
    tester,
  ) async {
    await pumpApp(
      tester,
      session: SessionState.authenticated(
        testMe(permissions: accountantPerms, role: 'Accountant'),
      ),
    );
    await tester.tap(find.text('More').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Reports has an in-app screen now, so nothing is left to list as web-only.
    expect(find.text('On the web app for now'), findsNothing);
    expect(find.text('Reports'), findsOneWidget);
    // Financials has an in-app screen, so it is not listed as "web only".
    expect(find.text('Financials'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('custom role: only the permitted tabs appear', (tester) async {
    await pumpApp(
      tester,
      session: SessionState.authenticated(
        testMe(
          permissions: ['tasks.view', 'messaging.view'],
          role: 'Inspector',
        ),
      ),
    );
    expect(find.text('My Tasks'), findsWidgets);
    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Clock'), findsNothing);
    expect(find.text('Materials'), findsNothing);
  });

  testWidgets('signed-out user is shown login, not protected content', (
    tester,
  ) async {
    await pumpApp(tester, session: const SessionState.unauthenticated());
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Clock'), findsNothing);
  });

  testWidgets(
    'subscription-blocked user sees guidance with no billing action',
    (tester) async {
      await pumpApp(
        tester,
        session: SessionState.subscriptionBlocked(
          const AppException(
            AppErrorKind.subscription,
            'x',
            code: 'TRIAL_EXPIRED',
          ),
        ),
      );
      expect(find.text("Your company's free trial has ended"), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.textContaining('Pay'), findsNothing);
      expect(find.textContaining('Upgrade'), findsNothing);
    },
  );

  testWidgets('offline banner shows when the session came from the cache', (
    tester,
  ) async {
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe(), offline: true),
    );
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('renders in dark theme and large text without overflow', (
    tester,
  ) async {
    await pumpApp(
      tester,
      session: SessionState.authenticated(testMe()),
      brightness: Brightness.dark,
      textScale: 1.6,
      size: const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('More'), findsWidgets);
  });
}
