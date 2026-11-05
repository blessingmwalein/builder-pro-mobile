import '../errors/app_exception.dart';
import '../network/api_client.dart';
import 'auth_models.dart';

/// Wraps the `/auth/*` endpoints of builder-pro-back.
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// `POST /auth/login` → 201 `{accessToken, refreshToken, tokenType, expiresIn}`.
  ///
  /// [companySlug] is required by the backend only when the same email exists
  /// in several companies (it answers 401 "Multiple accounts found…").
  Future<AuthTokens> login({
    required String email,
    required String password,
    String? companySlug,
  }) async {
    final body = await _api.post(
      'auth/login',
      auth: false,
      body: {
        'email': email.trim(),
        'password': password,
        if (companySlug != null && companySlug.trim().isNotEmpty)
          'companySlug': companySlug.trim(),
      },
    );
    final tokens = AuthTokens.tryParse(body);
    if (tokens == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected sign-in response.',
      );
    }
    return tokens;
  }

  /// `GET /auth/me`. Throws a 402 [AppException] when the subscription is blocked.
  Future<Me> me() async {
    final body = await _api.get('auth/me');
    final me = Me.tryParse(body);
    if (me == null) {
      throw const AppException(
        AppErrorKind.malformed,
        'The server sent an unexpected profile response.',
      );
    }
    return me;
  }

  /// `POST /auth/forgot-password` — always answers with a generic message.
  Future<void> forgotPassword({
    required String email,
    String? companySlug,
  }) async {
    await _api.post(
      'auth/forgot-password',
      auth: false,
      body: {
        'email': email.trim(),
        if (companySlug != null && companySlug.trim().isNotEmpty)
          'companySlug': companySlug.trim(),
      },
    );
  }

  /// `POST /auth/reset-password` with the 6-digit code from the email (15 min).
  Future<void> resetPassword({
    required String email,
    required String otp,
    required String password,
    String? companySlug,
  }) async {
    await _api.post(
      'auth/reset-password',
      auth: false,
      body: {
        'email': email.trim(),
        'otp': otp.trim(),
        'password': password,
        if (companySlug != null && companySlug.trim().isNotEmpty)
          'companySlug': companySlug.trim(),
      },
    );
  }
}

/// True when the login error means "same email in several companies".
bool isMultipleAccountsError(AppException e) =>
    e.kind == AppErrorKind.unauthorized &&
    e.message.toLowerCase().contains('companyslug');
