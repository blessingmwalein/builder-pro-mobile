import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small on-device settings (a handful of switches), kept apart from the
/// sign-in tokens. Nothing here is sent anywhere.
abstract class PreferencesStore {
  Future<bool> readBool(String key, {bool fallback = false});
  Future<void> writeBool(String key, bool value);
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
}

class SecurePreferencesStore implements PreferencesStore {
  SecurePreferencesStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<bool> readBool(String key, {bool fallback = false}) async {
    try {
      final v = await _s.read(key: key);
      if (v == null) return fallback;
      return v == 'true';
    } catch (_) {
      return fallback;
    }
  }

  @override
  Future<void> writeBool(String key, bool value) =>
      _s.write(key: key, value: value ? 'true' : 'false');

  @override
  Future<String?> readString(String key) async {
    try {
      return await _s.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeString(String key, String value) =>
      _s.write(key: key, value: value);
}

final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => SecurePreferencesStore(),
);
