/// Form validators. Rules mirror the backend DTOs
/// (`login.dto.ts`, `reset-password.dto.ts`: email format, password >= 8).
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter your email address';
    if (!_email.hasMatch(s)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Enter your password';
    if (s.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  static String? otp(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter the 6-digit code from your email';
    if (!RegExp(r'^\d{6}$').hasMatch(s)) return 'The code is 6 digits';
    return null;
  }

  static String? Function(String?) matches(
    String Function() other,
    String message,
  ) =>
      (v) => (v ?? '') == other() ? null : message;

  /// Positive quantity with at most [maxDecimals] decimals (backend: 3 for materials).
  static String? quantity(String? v, {int maxDecimals = 3}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Enter a quantity';
    final n = double.tryParse(s);
    if (n == null) return 'Enter a number';
    if (n <= 0) return 'Quantity must be greater than zero';
    final dot = s.indexOf('.');
    if (dot >= 0 && s.length - dot - 1 > maxDecimals) {
      return 'Use at most $maxDecimals decimal places';
    }
    return null;
  }
}
