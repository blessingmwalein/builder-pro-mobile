import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// A position as the API wants it: latitude and longitude to seven decimals.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  static double _seven(double v) => (v * 1e7).round() / 1e7;

  /// The same point rounded to the seven decimals the server accepts.
  GeoPoint get rounded => GeoPoint(_seven(latitude), _seven(longitude));
}

/// Where the phone is, behind a small interface so the clock can be tested
/// without the platform plugin. Nothing here ever throws: a missing permission,
/// a switched-off location service or a slow fix all come back as null, so
/// clocking in or out is never held up or refused because of location.
abstract class LocationService {
  /// Asks for permission if it has not been decided yet. True when location can
  /// be read now.
  Future<bool> ensurePermission();

  /// The current position, or null when it cannot be had within [timeout].
  Future<GeoPoint?> currentPosition({
    Duration timeout = const Duration(seconds: 6),
  });
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<bool> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<GeoPoint?> currentPosition({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return GeoPoint(p.latitude, p.longitude).rounded;
    } catch (_) {
      // Last resort: the last position the phone knew about, if any.
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last == null
            ? null
            : GeoPoint(last.latitude, last.longitude).rounded;
      } catch (_) {
        return null;
      }
    }
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);
