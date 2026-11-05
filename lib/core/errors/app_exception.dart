import 'package:dio/dio.dart';

enum AppErrorKind {
  /// The device could not reach the server. The request was NOT delivered.
  offline,

  /// Connection timed out before the request was sent. NOT delivered.
  timeout,

  /// Request may have been delivered but no response arrived. Outcome UNKNOWN.
  uncertain,
  unauthorized,
  forbidden,
  notFound,
  validation,
  conflict,
  subscription,
  rateLimited,
  server,
  malformed,
  cancelled,
  unknown,
}

/// Single error type surfaced by repositories and shown by the UI.
class AppException implements Exception {
  const AppException(
    this.kind,
    this.message, {
    this.statusCode,
    this.code,
    this.details = const [],
  });

  final AppErrorKind kind;
  final String message;
  final int? statusCode;

  /// Backend error code, e.g. `TRIAL_EXPIRED` on HTTP 402.
  final String? code;

  /// Field-level validation messages returned by the backend.
  final List<String> details;

  bool get isNetwork =>
      kind == AppErrorKind.offline || kind == AppErrorKind.timeout;

  /// True when it is NOT safe to blindly repeat a non-idempotent write.
  bool get outcomeUnknown => kind == AppErrorKind.uncertain;

  /// True when retrying the same request is reasonable for reads.
  bool get isRetryable =>
      isNetwork ||
      kind == AppErrorKind.uncertain ||
      kind == AppErrorKind.server ||
      kind == AppErrorKind.rateLimited;

  /// Message including validation details, for forms.
  String get fullMessage => details.isEmpty ? message : details.join('\n');

  factory AppException.fromDio(DioException e) {
    final inner = e.error;
    if (inner is AppException) return inner;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return const AppException(
          AppErrorKind.timeout,
          'The server took too long to respond. Check your connection and try again.',
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AppException(
          AppErrorKind.uncertain,
          'No response from the server. Your last action may or may not have been saved.',
        );
      case DioExceptionType.connectionError:
        return const AppException(
          AppErrorKind.offline,
          "You're offline or the server can't be reached.",
        );
      case DioExceptionType.cancel:
        return const AppException(AppErrorKind.cancelled, 'Request cancelled.');
      case DioExceptionType.transformTimeout:
        return const AppException(
          AppErrorKind.malformed,
          'The server sent an unexpected response.',
        );
      case DioExceptionType.badCertificate:
        return const AppException(
          AppErrorKind.unknown,
          'A secure connection could not be established.',
        );
      case DioExceptionType.badResponse:
        return AppException.fromResponse(
          e.response?.statusCode,
          e.response?.data,
        );
      case DioExceptionType.unknown:
        if (e.error is FormatException) {
          return const AppException(
            AppErrorKind.malformed,
            'The server sent an unexpected response.',
          );
        }
        return const AppException(
          AppErrorKind.offline,
          "You're offline or the server can't be reached.",
        );
    }
  }

  factory AppException.fromResponse(int? status, Object? body) {
    String? message;
    String? code;
    var details = <String>[];

    if (body is Map) {
      final raw = body['message'];
      if (raw is String) {
        message = raw;
      } else if (raw is List) {
        details = raw.map((e) => e.toString()).toList();
        message = details.isNotEmpty ? details.first : null;
      }
      final c = body['code'];
      if (c is String) code = c;
    } else if (body is String && body.isNotEmpty && body.length < 300) {
      message = body;
    }

    switch (status) {
      case 400:
      case 422:
        return AppException(
          AppErrorKind.validation,
          message ?? 'Some of the information is not valid.',
          statusCode: status,
          code: code,
          details: details,
        );
      case 401:
        return AppException(
          AppErrorKind.unauthorized,
          message ?? 'Your session has expired. Please sign in again.',
          statusCode: status,
          code: code,
        );
      case 402:
        return AppException(
          AppErrorKind.subscription,
          message ?? "Your company's subscription is not active.",
          statusCode: status,
          code: code,
        );
      case 403:
        return AppException(
          AppErrorKind.forbidden,
          "You don't have permission to do that.",
          statusCode: status,
          code: code,
        );
      case 404:
        return AppException(
          AppErrorKind.notFound,
          message ?? 'That item could not be found.',
          statusCode: status,
        );
      case 409:
        return AppException(
          AppErrorKind.conflict,
          message ?? 'That conflicts with existing data.',
          statusCode: status,
        );
      case 429:
        return AppException(
          AppErrorKind.rateLimited,
          'Too many requests. Please wait a moment and try again.',
          statusCode: status,
        );
      default:
        if (status != null && status >= 500) {
          return AppException(
            AppErrorKind.server,
            'The server ran into a problem. Please try again shortly.',
            statusCode: status,
          );
        }
        return AppException(
          AppErrorKind.unknown,
          message ?? 'Something went wrong.',
          statusCode: status,
        );
    }
  }

  @override
  String toString() => 'AppException($kind, $statusCode, $code, $message)';
}
