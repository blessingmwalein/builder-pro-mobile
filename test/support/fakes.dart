import 'dart:async';

import 'package:builder_pro_mobile/core/offline/app_database.dart';
import 'package:builder_pro_mobile/core/providers.dart';
import 'package:builder_pro_mobile/features/messaging/application/messaging_providers.dart';
import 'package:builder_pro_mobile/features/messaging/data/messaging_models.dart';
import 'package:builder_pro_mobile/features/messaging/data/realtime_messages.dart';
import 'package:builder_pro_mobile/shared/services/photo_picker.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fake_adapter.dart';

/// Every test opens its own in-memory database; Drift's warning about that is noise here.
void quietDriftWarnings() =>
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

AppDatabase _memoryDb() {
  quietDriftWarnings();
  return AppDatabase(NativeDatabase.memory());
}

/// A Dio wired to a [FakeAdapter], configured like the real client.
Dio testDio(FakeAdapter adapter) => Dio(
  BaseOptions(
    baseUrl: 'https://api.test/api/v1/',
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ),
)..httpClientAdapter = adapter;

/// In-memory realtime channel the test can drive.
class FakeRealtime implements RealtimeMessages {
  final _messages = StreamController<ChatMessage>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final joined = <String>[];
  bool connected = false;
  bool started = false;

  @override
  Stream<ChatMessage> get messages => _messages.stream;

  @override
  Stream<bool> get connection => _connection.stream;

  @override
  bool get isConnected => connected;

  @override
  void start() => started = true;

  @override
  void join(String conversationId) => joined.add(conversationId);

  @override
  void dispose() {}

  void push(ChatMessage m) => _messages.add(m);

  void setConnected(bool up) {
    connected = up;
    _connection.add(up);
  }
}

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.result);
  PickedPhoto? result;
  final requested = <PhotoSource>[];

  @override
  Future<PickedPhoto?> pick(PhotoSource source) async {
    requested.add(source);
    return result;
  }
}

/// Everything a widget/repository test needs so nothing touches the network,
/// disk or platform plugins.
class TestEnv {
  TestEnv({
    AppDatabase? database,
    FakeRealtime? realtime,
    this.online = true,
    this.realtimeOverride,
  }) : adapter = FakeAdapter(),
       db = database ?? _memoryDb(),
       realtime = realtime ?? FakeRealtime();

  final FakeAdapter adapter;
  final AppDatabase db;
  final FakeRealtime realtime;

  /// What the phone reports for connectivity.
  final bool online;

  /// Replaces the default fake realtime channel (to observe its lifecycle).
  final Override? realtimeOverride;

  List<Override> get overrides => [
    dioOverridesProvider.overrideWithValue((
      main: testDio(adapter),
      refresh: testDio(FakeAdapter()),
    )),
    appDatabaseProvider.overrideWithValue(db),
    connectivityProvider.overrideWith((ref) => Stream.value(online)),
    realtimeOverride ?? realtimeMessagesProvider.overrideWithValue(realtime),
  ];

  Future<void> dispose() => db.close();
}
