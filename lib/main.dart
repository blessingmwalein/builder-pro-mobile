import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/theme/theme_mode.dart';
import 'core/storage/preferences_store.dart';
import 'features/notifications/application/push_providers.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Alerts are optional: if Firebase cannot start (a build without its
  // configuration, a phone without Google services) the app still runs, and the
  // Notifications screen simply does not offer alerts.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (_) {
    firebaseReady = false;
  }

  // Light or dark, as last chosen on this phone, so the first frame is right.
  final themeMode = await loadThemeMode(SecurePreferencesStore());

  runApp(
    ProviderScope(
      // No automatic provider retries: a failed write must never be repeated silently.
      retry: (_, _) => null,
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        initialThemeModeProvider.overrideWithValue(themeMode),
      ],
      child: const BuilderProApp(),
    ),
  );
}
