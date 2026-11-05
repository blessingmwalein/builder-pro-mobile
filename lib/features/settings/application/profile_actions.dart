import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/providers.dart';

/// Changing your own name and phone number.
class ProfileActions {
  ProfileActions(this._ref);
  final Ref _ref;

  /// `PUT /users/me`. It only sets the three fields it is given (a blank phone
  /// clears it), so after an uncertain failure it is sent once more; a second
  /// failure is reported. The signed-in profile is then reloaded.
  Future<void> update({
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    final api = _ref.read(apiClientProvider);
    Future<void> send() => api.put(
      'users/me',
      body: {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'phone': (phone ?? '').trim(),
      },
    );
    try {
      await send();
    } on AppException catch (e) {
      if (!e.outcomeUnknown) rethrow;
      await send();
    }
    try {
      await _ref.read(sessionProvider.notifier).refreshMe();
    } catch (_) {
      // The change is saved; the profile card catches up on the next refresh.
    }
  }
}

final profileActionsProvider = Provider<ProfileActions>(
  (ref) => ProfileActions(ref),
);

/// Validation for a name field: required, a sensible length.
String? validatePersonName(String? raw, String what) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return 'Enter your $what';
  if (t.length > 60) return 'Keep it under 60 characters';
  return null;
}

/// Validation for a phone number: optional, digits with `+`, spaces, dashes and
/// brackets, 7 to 20 characters.
String? validatePhone(String? raw) {
  final t = (raw ?? '').trim();
  if (t.isEmpty) return null;
  if (!RegExp(r'^[0-9+()\-\s]+$').hasMatch(t)) {
    return 'Use digits, spaces, + and - only';
  }
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7 || t.length > 20) return 'Enter a full phone number';
  return null;
}
