import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/server_features.dart';
import '../../../core/offline/app_database.dart';
import '../../../core/offline/write_queue.dart';
import '../../../core/providers.dart';
import '../../materials/application/materials_providers.dart';
import '../../time/application/time_providers.dart';
import '../data/queued_write_models.dart';
import 'write_handlers.dart';

/// The signed-in person's queue of writes saved without a connection.
final writeQueueProvider = Provider<WriteQueue?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  final time = ref.watch(timeRepositoryProvider);
  if (uid == null || time == null) return null;
  bool serverReadsEventTime() => ref.read(offlineWritesSupportedProvider);
  final queue = WriteQueue(
    db: ref.watch(appDatabaseProvider),
    userId: uid,
    handlers: [
      ClockInHandler(time, serverReadsEventTime),
      ClockOutHandler(time, serverReadsEventTime),
      MaterialUsageHandler(ref.watch(materialsRepositoryProvider)),
    ],
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// Everything waiting to be sent, oldest first.
final queuedWritesProvider = StreamProvider<List<QueuedWrite>>((ref) {
  final queue = ref.watch(writeQueueProvider);
  if (queue == null) return Stream.value(const []);
  return queue.watch();
});

/// Keeps the queue moving. Watched once, by the app itself: it sends what is
/// waiting when the phone reconnects, when the app comes back to the front,
/// when the server is first seen to support clock events saved offline, and a
/// moment after the app starts. After a write is recorded it refreshes what the
/// screens show.
final syncTriggerProvider = Provider<void>((ref) {
  final queue = ref.watch(writeQueueProvider);
  if (queue == null) return;

  void flush() => unawaited(queue.flush());

  ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
    if (next.value == true) flush();
  });
  ref.listen<int>(appResumeProvider, (_, _) => flush());
  ref.listen<bool>(offlineWritesSupportedProvider, (prev, next) {
    if (next) flush();
  });

  final sub = queue.sent.listen((kind) {
    if (!ref.mounted) return;
    if (WriteKind.isTime(kind)) {
      unawaited(ref.read(clockProvider.notifier).refreshQuietly());
      ref.invalidate(weekSummaryProvider);
      ref.invalidate(recentEntriesProvider);
    }
  });
  ref.onDispose(sub.cancel);

  Future<void>.microtask(flush);
});
