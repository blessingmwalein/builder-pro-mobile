import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';

/// Short feedback at the bottom of the screen. Errors use the plain-language
/// message from [AppException]; nothing technical is shown to the worker.
abstract final class Snack {
  static void show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  static void error(BuildContext context, Object error) {
    show(
      context,
      error is AppException
          ? error.fullMessage
          : 'Something went wrong. Please try again.',
    );
  }
}
