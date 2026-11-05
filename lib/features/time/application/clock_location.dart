import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/preferences_store.dart';
import '../../../shared/services/location_service.dart';

/// Whether this person has chosen to record where they are when they clock in
/// and out. Off until they turn it on, kept per person on this phone, and never
/// required: clocking in works the same whatever the answer.
class ClockLocationPreference extends AsyncNotifier<bool> {
  String? get _key {
    final uid = ref.read(currentUserIdProvider);
    return uid == null ? null : 'bp_clock_location_$uid';
  }

  @override
  Future<bool> build() async {
    final key = _key;
    if (key == null) return false;
    return ref.read(preferencesStoreProvider).readBool(key);
  }

  /// Turns recording on or off. Turning it on asks the phone for permission
  /// first; if that is refused (or location is switched off) it stays off and
  /// the reason is returned. Null means it worked.
  Future<String?> setEnabled(bool on) async {
    final key = _key;
    if (key == null) return 'Sign in first.';
    if (on) {
      final allowed = await ref
          .read(locationServiceProvider)
          .ensurePermission();
      if (!allowed) {
        state = const AsyncData(false);
        return 'Location is switched off or not allowed for this app. Turn it on in the phone settings, then try again.';
      }
    }
    await ref.read(preferencesStoreProvider).writeBool(key, on);
    state = AsyncData(on);
    return null;
  }
}

final clockLocationProvider =
    AsyncNotifierProvider<ClockLocationPreference, bool>(
      ClockLocationPreference.new,
    );
