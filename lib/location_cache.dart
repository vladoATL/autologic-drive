import 'package:autologic_drive/preferences.dart';
import 'package:autologic_drive/tracking/tracking_engine.dart';

class CachedLocation {
  final String timestamp;
  final double latitude;
  final double longitude;
  final double heading;
  const CachedLocation({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.heading,
  });
}

class LocationCache {
  static CachedLocation? _last;

  static CachedLocation? get() {
    if (_last == null) {
      final timestamp = Preferences.instance.getString(Preferences.lastTimestamp);
      final latitude = Preferences.instance.getDouble(Preferences.lastLatitude);
      final longitude = Preferences.instance.getDouble(Preferences.lastLongitude);
      final heading = Preferences.instance.getDouble(Preferences.lastHeading);
      if (timestamp != null && latitude != null && longitude != null && heading != null) {
        _last = CachedLocation(
          timestamp: timestamp,
          latitude: latitude,
          longitude: longitude,
          heading: heading,
        );
      }
    }
    return _last;
  }

  static Future<void> set(TrackedLocation location) async {
    final last = CachedLocation(
      timestamp: location.timestamp,
      latitude: location.latitude,
      longitude: location.longitude,
      heading: location.heading,
    );
    Preferences.instance.setString(Preferences.lastTimestamp, last.timestamp);
    Preferences.instance.setDouble(Preferences.lastLatitude, last.latitude);
    Preferences.instance.setDouble(Preferences.lastLongitude, last.longitude);
    Preferences.instance.setDouble(Preferences.lastHeading, last.heading);
    _last = last;
  }
}
