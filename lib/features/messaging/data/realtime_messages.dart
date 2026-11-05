import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'messaging_models.dart';

/// Live message push. The thread screen works without it (it polls), so every
/// failure here is silent and the connection retries in the background.
abstract class RealtimeMessages {
  /// Messages the server pushed, for any conversation joined so far.
  Stream<ChatMessage> get messages;

  /// Emits whenever the connection goes up or down.
  Stream<bool> get connection;

  bool get isConnected;

  /// Starts connecting (idempotent).
  void start();

  /// Subscribes to a conversation; re-subscribed automatically after a reconnect.
  void join(String conversationId);

  void dispose();
}

/// Socket.IO client for the `/messaging` namespace of builder-pro-back.
///
/// The server verifies the JWT during the handshake only, so [tokenProvider] is
/// asked for a fresh token on every (re)connect.
class SocketIoMessages implements RealtimeMessages {
  SocketIoMessages({
    required this.origin,
    required this.tokenProvider,
    this.tenantSlug,
  });

  final String origin;
  final Future<String?> Function() tokenProvider;
  final String? tenantSlug;

  final _messages = StreamController<ChatMessage>.broadcast();
  final _connection = StreamController<bool>.broadcast();
  final _joined = <String>{};
  io.Socket? _socket;

  @override
  Stream<ChatMessage> get messages => _messages.stream;

  @override
  Stream<bool> get connection => _connection.stream;

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  void start() {
    if (_socket != null) return;
    final socket = io.io(
      '$origin/messaging',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuthFn((callback) async {
            callback({'token': await tokenProvider() ?? ''});
          })
          .setExtraHeaders({
            if (tenantSlug != null && tenantSlug!.isNotEmpty)
              'x-tenant-slug': tenantSlug!,
          })
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          .build(),
    );
    _socket = socket;

    socket
      ..onConnect((_) {
        _connection.add(true);
        for (final id in _joined) {
          socket.emit('join-conversation', {'conversationId': id});
        }
      })
      ..onDisconnect((_) => _connection.add(false))
      ..onConnectError((_) => _connection.add(false))
      ..on('conversation-message', (data) {
        if (data is! Map) return;
        final m = ChatMessage.tryParse(
          data.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (m != null && !_messages.isClosed) _messages.add(m);
      })
      ..connect();
  }

  @override
  void join(String conversationId) {
    _joined.add(conversationId);
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('join-conversation', {'conversationId': conversationId});
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    _socket = null;
    _messages.close();
    _connection.close();
  }
}
