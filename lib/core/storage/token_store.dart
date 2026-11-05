import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the signed-in session. Implementations must never log values.
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<String?> readTenantSlug();
  Future<String?> readMeCache();

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  });
  Future<void> saveTenantSlug(String slug);

  /// Last known `/auth/me` payload, so the app can open on a site with no signal.
  /// It only drives UI; the backend authorises every request independently.
  Future<void> saveMeCache(String json);

  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  static const _access = 'bp_access_token';
  static const _refresh = 'bp_refresh_token';
  static const _slug = 'bp_tenant_slug';
  static const _me = 'bp_me_cache';

  @override
  Future<String?> readAccessToken() => _s.read(key: _access);
  @override
  Future<String?> readRefreshToken() => _s.read(key: _refresh);
  @override
  Future<String?> readTenantSlug() => _s.read(key: _slug);
  @override
  Future<String?> readMeCache() => _s.read(key: _me);

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _s.write(key: _access, value: accessToken);
    await _s.write(key: _refresh, value: refreshToken);
  }

  @override
  Future<void> saveTenantSlug(String slug) => _s.write(key: _slug, value: slug);

  @override
  Future<void> saveMeCache(String json) => _s.write(key: _me, value: json);

  @override
  Future<void> clear() async {
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
    await _s.delete(key: _slug);
    await _s.delete(key: _me);
  }
}

/// In-memory store for tests.
class MemoryTokenStore implements TokenStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> readAccessToken() async => _m['a'];
  @override
  Future<String?> readRefreshToken() async => _m['r'];
  @override
  Future<String?> readTenantSlug() async => _m['s'];
  @override
  Future<String?> readMeCache() async => _m['m'];

  @override
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _m['a'] = accessToken;
    _m['r'] = refreshToken;
  }

  @override
  Future<void> saveTenantSlug(String slug) async => _m['s'] = slug;

  @override
  Future<void> saveMeCache(String json) async => _m['m'] = json;

  @override
  Future<void> clear() async => _m.clear();
}
