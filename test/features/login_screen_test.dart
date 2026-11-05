import 'package:builder_pro_mobile/app/app.dart';
import 'package:builder_pro_mobile/core/providers.dart';
import 'package:builder_pro_mobile/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_adapter.dart';
import '../support/fixtures.dart';

Dio _dio(FakeAdapter a) => Dio(
  BaseOptions(
    baseUrl: 'https://api.test/api/v1/',
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ),
)..httpClientAdapter = a;

/// Real session controller + fake HTTP (so the login screen drives actual logic).
Future<(FakeAdapter, MemoryTokenStore)> _pumpLogin(WidgetTester tester) async {
  final adapter = FakeAdapter();
  final store = MemoryTokenStore();
  tester.view.physicalSize = const Size(390, 844) * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      dioOverridesProvider.overrideWithValue((
        main: _dio(adapter),
        refresh: _dio(FakeAdapter()),
      )),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  // Boot with no stored session so the router shows /login.
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const BuilderProApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (adapter, store);
}

void main() {
  testWidgets('validates email and password before calling the API', (
    tester,
  ) async {
    final (adapter, _) = await _pumpLogin(tester);
    expect(find.text('Sign in'), findsWidgets);

    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pump();

    expect(find.text('Enter your email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(adapter.requests, isEmpty);

    await tester.enterText(find.byType(TextFormField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('wrong password shows a friendly message', (tester) async {
    final (adapter, _) = await _pumpLogin(tester);
    adapter.on(
      'POST',
      'auth/login',
      (_) => Reply.json({'message': 'Invalid credentials'}, status: 401),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tendai@acme.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrongpass1');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('"multiple accounts" reveals the company code field', (
    tester,
  ) async {
    final (adapter, _) = await _pumpLogin(tester);
    adapter.on(
      'POST',
      'auth/login',
      (_) => Reply.json({
        'message': 'Multiple accounts found for this email. Please include companySlug.',
      }, status: 401),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tendai@acme.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();

    expect(find.text('Company code'), findsOneWidget);
    expect(find.textContaining('more than one company'), findsOneWidget);
  });

  testWidgets('a double tap sends exactly one login request', (tester) async {
    final (adapter, _) = await _pumpLogin(tester);
    adapter.on(
      'POST',
      'auth/login',
      (_) => Reply.json(
        {'message': 'Invalid credentials'},
        status: 401,
        delay: const Duration(milliseconds: 300),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tendai@acme.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    final button = find.widgetWithText(InkWell, 'Sign in').last;
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(button, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(adapter.count('POST', 'auth/login'), 1);
  });

  testWidgets('successful login moves to the worker home tab', (tester) async {
    final (adapter, store) = await _pumpLogin(tester);
    adapter.on(
      'POST',
      'auth/login',
      (_) => Reply.json({
        'accessToken': 'a',
        'refreshToken': 'r',
        'tokenType': 'Bearer',
        'expiresIn': '15m',
      }, status: 201),
    );
    adapter.on('GET', 'auth/me', (_) => Reply.json(meJson()));

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'tendai@acme.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.tap(find.widgetWithText(InkWell, 'Sign in').last);
    await tester.pumpAndSettle();

    expect(find.text('My Tasks'), findsWidgets);
    expect(find.text('Sign in'), findsNothing);
    expect(await store.readRefreshToken(), 'r');
  });
}
