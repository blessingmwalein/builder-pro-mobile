import 'package:builder_pro_mobile/app/app.dart';
import 'package:builder_pro_mobile/core/auth/session_state.dart';
import 'package:builder_pro_mobile/core/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'fixtures.dart';

/// Pumps the full app (real router, theme, shell) with a fixed session.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required SessionState session,
  List<Override> overrides = const [],
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  TestEnv? env,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });

  // Default to an offline-looking fake API, an in-memory database and no
  // sockets, so a test that does not care about data still touches nothing real.
  final testEnv = env ?? TestEnv();
  if (env == null) addTearDown(testEnv.dispose);

  final container = ProviderContainer(
    overrides: [
      ...testEnv.overrides,
      sessionProvider.overrideWith(() => FakeSession(session)),
      ...overrides,
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const BuilderProApp(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

/// Collects Flutter framework errors (overflow, bad constraints…) raised while
/// the test runs, each with the file:line of the widget that caused it, so a
/// failure says WHERE the layout broke instead of just "overflowed".
/// Call [stop] before the final `expect`: flutter_test requires the handler to
/// be restored first.
class ErrorCapture {
  ErrorCapture() : _previous = FlutterError.onError {
    FlutterError.onError = (details) {
      final lines = details.toString().split('\n');
      final where = lines
          .where(
            (l) => l.contains('.dart:') && l.contains('builder-pro-mobile/lib'),
          )
          .take(2);
      errors.add('${details.exceptionAsString()} @ ${where.join(' | ')}');
    };
  }

  final FlutterExceptionHandler? _previous;
  final errors = <String>[];

  List<String> stop() {
    FlutterError.onError = _previous;
    return errors;
  }
}

/// Lets queued async work (fake HTTP, in-memory database) finish without
/// waiting for a live timer, which would never "settle".
Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Removes the app from the tree and lets Riverpod dispose auto-dispose
/// providers (they schedule their disposal on a zero-length timer), so a test
/// that pumps the app more than once leaves no pending timers behind.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}
