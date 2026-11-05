import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A canned HTTP response (or failure) for [FakeAdapter].
class Reply {
  Reply.json(Object? body, {this.status = 200, this.delay = Duration.zero})
    : bodyText = body == null ? '' : jsonEncode(body),
      failure = null;

  Reply.empty({this.status = 200})
    : bodyText = '',
      delay = Duration.zero,
      failure = null;

  Reply.fail(DioExceptionType type)
    : status = 0,
      bodyText = '',
      delay = Duration.zero,
      failure = type;

  final int status;
  final String bodyText;
  final Duration delay;
  final DioExceptionType? failure;
}

class Recorded {
  Recorded(this.method, this.path, this.headers, this.data, this.query);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Object? data;
  final Map<String, dynamic> query;
}

/// Deterministic Dio adapter for tests; no network is ever touched.
class FakeAdapter implements HttpClientAdapter {
  final Map<String, List<Reply Function(RequestOptions)>> _routes = {};
  final List<Recorded> requests = [];

  /// Registers a handler. Handlers for the same route are consumed in order;
  /// the last one repeats.
  void on(
    String method,
    String path,
    Reply Function(RequestOptions o) handler,
  ) {
    _routes.putIfAbsent('$method $path', () => []).add(handler);
  }

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).length;

  Recorded last(String method, String path) =>
      requests.lastWhere((r) => r.method == method && r.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      Recorded(
        options.method,
        options.path,
        Map.of(options.headers),
        options.data,
        Map.of(options.queryParameters),
      ),
    );
    final list = _routes['${options.method} ${options.path}'];
    if (list == null || list.isEmpty) {
      throw StateError('No fake route for ${options.method} ${options.path}');
    }
    final handler = list.length > 1 ? list.removeAt(0) : list.first;
    final reply = handler(options);
    if (reply.delay > Duration.zero) await Future<void>.delayed(reply.delay);
    if (reply.failure != null) {
      throw DioException(requestOptions: options, type: reply.failure!);
    }
    return ResponseBody.fromString(
      reply.bodyText,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
