import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';
import '../storage/token_store.dart';
import 'server_features.dart';

enum _RefreshResult { ok, rejected, unavailable }

/// HTTP client for the BuilderPro API.
///
/// * Adds `Authorization: Bearer` and `x-tenant-slug` to authenticated calls.
/// * On 401 performs ONE shared (single-flight) token refresh, then retries once.
///   Refresh rotates both tokens server-side, so concurrent refreshes must never race.
/// * Maps every failure to [AppException]; raises session events for 401/402.
/// * Never logs headers, bodies or tokens.
class ApiClient {
  ApiClient({
    required AppConfig config,
    required this._tokens,
    Dio? dio,
    Dio? refreshDio,
  }) : dio = dio ?? _buildDio(config),
       _refreshDio = refreshDio ?? _buildDio(config) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );
  }

  final TokenStore _tokens;
  final Dio dio;
  final Dio _refreshDio;

  String? _accessToken;
  String? _refreshToken;
  String? _tenantSlug;
  Future<_RefreshResult>? _refreshing;

  /// Called when the refresh token is rejected (session truly over).
  void Function()? onSessionExpired;

  /// Called when the API answers 402 (subscription not active).
  void Function(AppException error)? onSubscriptionBlocked;

  /// Called with every successful reply: whether the server said it accepts
  /// clock events and usage saved offline (see `server_features.dart`).
  void Function(bool supported)? onOfflineWritesSeen;

  static const _retriedKey = 'bp_retried';
  static const _noAuthKey = 'bp_no_auth';
  static const retryAfterRefreshCode = 'RETRY_AFTER_REFRESH';

  static Dio _buildDio(AppConfig config) => Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl.endsWith('/')
          ? config.apiBaseUrl
          : '${config.apiBaseUrl}/',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
      validateStatus: (s) => s != null && s >= 200 && s < 300,
    ),
  );

  // ---- session ---------------------------------------------------------

  /// Loads persisted tokens into memory. Returns true when a session exists.
  Future<bool> restore() async {
    _accessToken = await _tokens.readAccessToken();
    _refreshToken = await _tokens.readRefreshToken();
    _tenantSlug = await _tokens.readTenantSlug();
    return _refreshToken != null && _refreshToken!.isNotEmpty;
  }

  bool get hasSession => (_refreshToken ?? '').isNotEmpty;

  /// Current access token, for the realtime socket handshake only.
  String? get accessToken => _accessToken;
  String? get tenantSlug => _tenantSlug;

  Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _tokens.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  Future<void> setTenantSlug(String slug) async {
    _tenantSlug = slug;
    await _tokens.saveTenantSlug(slug);
  }

  Future<void> clearSession() async {
    _accessToken = null;
    _refreshToken = null;
    _tenantSlug = null;
    await _tokens.clear();
  }

  // ---- interceptors ----------------------------------------------------

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[_noAuthKey] != true) {
      final token = _accessToken;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      final slug = _tenantSlug;
      if (slug != null && slug.isNotEmpty) {
        options.headers['x-tenant-slug'] = slug;
      }
    }
    handler.next(options);
  }

  void _onResponse(Response<dynamic> response, ResponseInterceptorHandler h) {
    onOfflineWritesSeen?.call(
      response.headers.value(offlineWritesHeader) == '1',
    );
    h.next(response);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final status = err.response?.statusCode;
    final opts = err.requestOptions;
    final isAuthCall = opts.extra[_noAuthKey] == true;

    if (status == 401 &&
        !isAuthCall &&
        opts.extra[_retriedKey] != true &&
        hasSession) {
      final result = await _refreshTokens();
      if (result == _RefreshResult.rejected) {
        const ex = AppException(
          AppErrorKind.unauthorized,
          'Your session has expired. Please sign in again.',
          statusCode: 401,
        );
        return handler.reject(
          DioException(
            requestOptions: opts,
            error: ex,
            type: DioExceptionType.badResponse,
            response: err.response,
          ),
        );
      }
      if (result == _RefreshResult.unavailable) {
        // Could not reach the server to refresh: stay signed in, report offline.
        const ex = AppException(
          AppErrorKind.offline,
          "You're offline or the server can't be reached.",
        );
        return handler.reject(
          DioException(
            requestOptions: opts,
            error: ex,
            type: DioExceptionType.connectionError,
          ),
        );
      }
      if (opts.data is FormData) {
        // A consumed multipart body cannot be re-sent; the caller rebuilds it.
        const ex = AppException(
          AppErrorKind.unauthorized,
          'Please try again.',
          statusCode: 401,
          code: retryAfterRefreshCode,
        );
        return handler.reject(
          DioException(
            requestOptions: opts,
            error: ex,
            type: DioExceptionType.badResponse,
            response: err.response,
          ),
        );
      }
      try {
        opts.extra[_retriedKey] = true;
        final response = await dio.fetch<dynamic>(opts);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.reject(e);
      }
    }

    final mapped = AppException.fromDio(err);
    if (mapped.kind == AppErrorKind.subscription) {
      onSubscriptionBlocked?.call(mapped);
    }
    return handler.reject(
      DioException(
        requestOptions: opts,
        response: err.response,
        type: err.type,
        error: mapped,
      ),
    );
  }

  /// Single-flight refresh. Concurrent 401s await the same attempt.
  Future<_RefreshResult> _refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<_RefreshResult> _doRefresh() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) {
      onSessionExpired?.call();
      return _RefreshResult.rejected;
    }
    try {
      final res = await _refreshDio.post<dynamic>(
        'auth/refresh',
        data: {'refreshToken': refresh},
        options: Options(extra: {_noAuthKey: true}),
      );
      final body = res.data;
      if (body is! Map ||
          body['accessToken'] is! String ||
          body['refreshToken'] is! String) {
        onSessionExpired?.call();
        return _RefreshResult.rejected;
      }
      await setTokens(
        accessToken: body['accessToken'] as String,
        refreshToken: body['refreshToken'] as String,
      );
      return _RefreshResult.ok;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Only a definite rejection ends the session. A network failure or 5xx
      // while refreshing must not log a worker out on a site with poor signal.
      if (status == 401 || status == 403 || status == 400) {
        onSessionExpired?.call();
        return _RefreshResult.rejected;
      }
      return _RefreshResult.unavailable;
    }
  }

  // ---- requests --------------------------------------------------------

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send(
    () => dio.get<dynamic>(
      path,
      queryParameters: _clean(query),
      options: _opts(auth),
    ),
  );

  Future<dynamic> post(String path, {Object? body, bool auth = true}) =>
      _send(() => dio.post<dynamic>(path, data: body, options: _opts(auth)));

  Future<dynamic> put(String path, {Object? body}) =>
      _send(() => dio.put<dynamic>(path, data: body, options: _opts(true)));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => dio.patch<dynamic>(path, data: body, options: _opts(true)));

  Future<dynamic> delete(String path) =>
      _send(() => dio.delete<dynamic>(path, options: _opts(true)));

  /// Multipart upload. [build] is called again if a token refresh is needed.
  Future<dynamic> postMultipart(
    String path,
    FormData Function() build, {
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      return await _send(
        () => dio.post<dynamic>(
          path,
          data: build(),
          options: _opts(true),
          onSendProgress: onProgress,
        ),
      );
    } on AppException catch (e) {
      if (e.code == retryAfterRefreshCode) {
        return _send(
          () => dio.post<dynamic>(
            path,
            data: build(),
            options: _opts(true),
            onSendProgress: onProgress,
          ),
        );
      }
      rethrow;
    }
  }

  Options _opts(bool auth) => Options(extra: {if (!auth) _noAuthKey: true});

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    return Map.fromEntries(
      q.entries.where((e) => e.value != null && e.value.toString().isNotEmpty),
    );
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is String && data.isEmpty) return null;
      return data;
    } on DioException catch (e) {
      throw AppException.fromDio(e);
    }
  }
}
