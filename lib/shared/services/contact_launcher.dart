import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Phone and email actions behind a small interface so screens can be tested
/// without the platform plugin. Each returns false when nothing could be opened
/// (no dialler or mail app, or nothing usable to open).
abstract class ContactLauncher {
  Future<bool> call(String phone);
  Future<bool> email(String address);

  /// Opens a web link (http or https only) outside the app, in the browser or a
  /// viewer that handles the file type.
  Future<bool> openLink(String url);
}

/// The number as a dialler wants it: digits, with a leading `+` kept. Null when
/// nothing dialable is left.
String? dialable(String raw) {
  final plus = raw.trim().startsWith('+') ? '+' : '';
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : '$plus$digits';
}

class UrlContactLauncher implements ContactLauncher {
  @override
  Future<bool> call(String phone) async {
    final number = dialable(phone);
    if (number == null) return false;
    return _open(Uri(scheme: 'tel', path: number));
  }

  @override
  Future<bool> email(String address) async {
    final a = address.trim();
    if (!a.contains('@')) return false;
    return _open(Uri(scheme: 'mailto', path: a));
  }

  @override
  Future<bool> openLink(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return false;
    }
    return _open(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _open(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    try {
      return await launchUrl(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }
}

final contactLauncherProvider = Provider<ContactLauncher>(
  (ref) => UrlContactLauncher(),
);
