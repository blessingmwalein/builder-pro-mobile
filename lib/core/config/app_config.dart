/// Build-time configuration. Override with `--dart-define=API_BASE_URL=...`.
///
/// No credentials belong here: the app only ever holds the signed-in user's tokens.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.appName = 'ownit2buildit'});

  /// Hosted BuilderPro API used by the web app (see builder-pro-web/.env.local).
  static const String defaultApiBaseUrl =
      'https://api.ownit2buildit.com/api/v1';

  static const String _apiFromEnv = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );

  factory AppConfig.fromEnvironment() =>
      const AppConfig(apiBaseUrl: _apiFromEnv);

  final String apiBaseUrl;
  final String appName;

  /// Socket.IO origin: the API host without the `/api/v1` prefix (the gateway
  /// namespace `/messaging` is not under the global prefix).
  String get socketOrigin {
    final uri = Uri.parse(apiBaseUrl);
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ).toString();
  }
}
