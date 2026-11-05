import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/preferences_store.dart';

const _themeModeKey = 'bp_theme_mode';

/// The saved choice (`system`, `light` or `dark`) as a [ThemeMode]; anything else,
/// including nothing saved, follows the phone.
ThemeMode parseThemeMode(String? raw) => switch (raw) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Reads the saved choice. Done before the app starts, so the first frame is
/// already in the right colours.
Future<ThemeMode> loadThemeMode(PreferencesStore store) async =>
    parseThemeMode(await store.readString(_themeModeKey));

/// What was saved when the app started; [themeModeProvider] begins from it.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);

/// Light, dark, or whatever the phone is set to. Kept on this phone for whoever
/// signs in on it (the sign-in screen needs it too), and never sent anywhere.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeModeProvider);

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    // The screen changes at once; saving is best effort, so a storage problem
    // only means the choice is forgotten next time.
    state = mode;
    try {
      await ref
          .read(preferencesStoreProvider)
          .writeString(_themeModeKey, mode.name);
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
