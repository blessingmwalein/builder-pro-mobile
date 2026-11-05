import '../../core/auth/session_state.dart';
import 'destinations.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const forgotPassword = '/forgot-password';
  static const subscriptionBlocked = '/subscription-blocked';
  static const startupFailed = '/startup-failed';
  static const denied = '/denied';
  static const more = morePath;
  static const notifications = '/more/notifications';
}

const _publicRoutes = {Routes.login, Routes.forgotPassword};

/// Central redirect rule for GoRouter. Pure, so it is unit-tested.
///
/// Order matters: session state first, then per-route permission checks (which
/// also protect deep links and notification taps), then keeping signed-in users
/// off the auth screens.
String? computeRedirect(SessionState session, String location) {
  switch (session.status) {
    case SessionStatus.bootstrapping:
      return location == Routes.splash ? null : Routes.splash;
    case SessionStatus.unauthenticated:
    case SessionStatus.expired:
      return _publicRoutes.contains(location) ? null : Routes.login;
    case SessionStatus.subscriptionBlocked:
      return location == Routes.subscriptionBlocked
          ? null
          : Routes.subscriptionBlocked;
    case SessionStatus.startupFailed:
      return location == Routes.startupFailed ? null : Routes.startupFailed;
    case SessionStatus.authenticated:
      break;
  }

  final perms = session.permissions;
  final plan = planNavigation(perms);

  const authOnly = {
    Routes.splash,
    Routes.login,
    Routes.forgotPassword,
    Routes.subscriptionBlocked,
    Routes.startupFailed,
    '/',
  };
  if (authOnly.contains(location)) return plan.homePath;

  final required = requiredPermissionsFor(location);
  if (required != null && !perms.satisfies(required)) return Routes.denied;
  return null;
}
