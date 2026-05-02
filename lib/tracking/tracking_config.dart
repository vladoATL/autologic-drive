/// Engine-agnostic tracking configuration.
///
/// Built from `Preferences` and consumed by a `TrackingEngine` implementation.
/// Each engine adapter maps these primitive fields to its native config object.
library;

enum TrackingAccuracy { highest, high, medium, low }

class TrackingConfig {
  final bool reset;
  final TrackingAccuracy accuracy;
  final int? distanceFilterMeters;
  final int? locationUpdateIntervalSeconds;
  final int? fastestLocationUpdateIntervalSeconds;
  final int? heartbeatIntervalSeconds;
  final bool stopDetection;
  final bool buffer;
  final String? serverUrl;
  final String? deviceId;
  final String locationBodyTemplate;

  const TrackingConfig({
    required this.reset,
    required this.accuracy,
    this.distanceFilterMeters,
    this.locationUpdateIntervalSeconds,
    this.fastestLocationUpdateIntervalSeconds,
    this.heartbeatIntervalSeconds,
    required this.stopDetection,
    required this.buffer,
    this.serverUrl,
    this.deviceId,
    required this.locationBodyTemplate,
  });

  bool get isHighestAccuracy => accuracy == TrackingAccuracy.highest;
}
