import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';

/// Response header the API sets when it understands the real time of a clock
/// event and recognises a repeat of one it already recorded.
const offlineWritesHeader = 'x-offline-writes';

const _preferenceKey = 'server_offline_writes';

/// Whether the server accepts clock events and material usage saved offline.
///
/// A clock event sent later is stamped with the time it was SENT unless the
/// server reads the time it HAPPENED, so the app saves clock events offline
/// only once it has seen this server say it can. The answer is remembered, so
/// it is known when the app starts without signal, and it is re-read from every
/// successful reply (a server rolled back to an older version turns it off).
class OfflineWritesSupport extends Notifier<bool> {
  bool _observed = false;

  @override
  bool build() {
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    final saved = await ref
        .read(preferencesStoreProvider)
        .readBool(_preferenceKey);
    // A live reply is newer than what was saved.
    if (!ref.mounted || _observed || !saved) return;
    state = true;
  }

  /// Called with what the latest successful reply said.
  void observe(bool supported) {
    _observed = true;
    if (state == supported) return;
    state = supported;
    unawaited(
      ref.read(preferencesStoreProvider).writeBool(_preferenceKey, supported),
    );
  }
}

final offlineWritesSupportedProvider =
    NotifierProvider<OfflineWritesSupport, bool>(OfflineWritesSupport.new);
