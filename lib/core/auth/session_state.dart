import 'package:flutter/foundation.dart';

import '../errors/app_exception.dart';
import '../permissions/permission_evaluator.dart';
import 'auth_models.dart';

enum SessionStatus {
  /// Reading stored credentials / verifying them.
  bootstrapping,
  unauthenticated,
  authenticated,

  /// The company's subscription is not active (HTTP 402).
  subscriptionBlocked,

  /// The refresh token was rejected; the user must sign in again.
  expired,

  /// Startup could not verify the session and nothing is cached.
  startupFailed,
}

@immutable
class SessionState {
  const SessionState._(
    this.status, {
    this.me,
    this.error,
    this.offline = false,
    this.notice,
  });

  const SessionState.bootstrapping() : this._(SessionStatus.bootstrapping);
  const SessionState.unauthenticated({String? notice})
    : this._(SessionStatus.unauthenticated, notice: notice);
  const SessionState.expired() : this._(SessionStatus.expired);
  const SessionState.startupFailed(AppException error)
    : this._(SessionStatus.startupFailed, error: error);

  const SessionState.authenticated(Me me, {bool offline = false})
    : this._(SessionStatus.authenticated, me: me, offline: offline);

  const SessionState.subscriptionBlocked(AppException error, {Me? me})
    : this._(SessionStatus.subscriptionBlocked, error: error, me: me);

  final SessionStatus status;
  final Me? me;
  final AppException? error;

  /// Authenticated from the cached profile because the server was unreachable.
  final bool offline;
  final String? notice;

  bool get isAuthenticated => status == SessionStatus.authenticated;

  PermissionEvaluator get permissions => isAuthenticated && me != null
      ? PermissionEvaluator(me!.permissions)
      : PermissionEvaluator.none;

  String? get subscriptionCode => error?.code;
}
