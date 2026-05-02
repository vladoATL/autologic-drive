/// Engine-agnostic tracking abstraction.
///
/// `TrackingEngine` insulates the rest of the app from the concrete background
/// geolocation SDK (currently `flutter_background_geolocation`, in 0.3.0
/// `tracelet`). Switch implementations by changing the `engine` singleton in
/// `lib/tracking/engine.dart`.
library;

import 'tracking_config.dart';

abstract class TrackingEngine {
  Future<void> ready(TrackingConfig config);
  Future<void> setConfig(TrackingConfig config);

  Future<TrackingState> getState();
  Future<bool> start();
  Future<bool> stop();

  Future<TrackedLocation> getCurrentPosition({
    int samples = 1,
    bool persist = true,
    Map<String, dynamic>? extras,
  });

  /// Ship a single location to the configured server.
  ///
  /// FBG-style adapters that own their own HTTP layer can no-op here and
  /// rely on `sync()`. Adapters without a built-in HTTP layer (Tracelet)
  /// implement this via a custom sender (see `OsmAndSender`).
  Future<void> dispatchLocation(TrackedLocation location);

  Future<void> sync();
  Future<void> destroyLocation(String uuid);

  void onEnabledChange(void Function(bool enabled) cb);
  void onMotionChange(void Function(TrackedLocation location) cb);
  void onLocation(
    void Function(TrackedLocation location) cb,
    void Function(Object error) onError,
  );
  void onHeartbeat(void Function() cb);

  void registerHeadlessTask(Future<void> Function(HeadlessEvent event) cb);

  Future<TrackingProviderState> getProviderState();
  Future<bool> isIgnoringBatteryOptimizations();
  Future<void> requestIgnoreBatteryOptimizations();

  Future<String> getLog();
  Future<void> emailLog(String email);
  Future<void> destroyLog();
}

class TrackingState {
  final bool enabled;
  final bool? isMoving;
  const TrackingState({required this.enabled, this.isMoving});
}

class TrackedLocation {
  final String uuid;
  final String timestamp;
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final double heading;
  final double altitude;
  final bool isMoving;
  final double? batteryLevel;
  final bool? batteryCharging;
  final String? activityType;
  final double? odometer;
  final Map<String, dynamic> extras;

  const TrackedLocation({
    required this.uuid,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.altitude,
    required this.isMoving,
    this.batteryLevel,
    this.batteryCharging,
    this.activityType,
    this.odometer,
    this.extras = const {},
  });
}

class TrackingProviderState {
  final bool gpsEnabled;
  final bool networkEnabled;
  final TrackingAuthorizationStatus status;
  const TrackingProviderState({
    required this.gpsEnabled,
    required this.networkEnabled,
    required this.status,
  });

  bool get isPermissionDenied =>
      status == TrackingAuthorizationStatus.denied ||
      status == TrackingAuthorizationStatus.restricted;
}

enum TrackingAuthorizationStatus { granted, denied, restricted, notDetermined }

enum HeadlessEventType { enabledChange, motionChange, heartbeat, location, unknown }

class HeadlessEvent {
  final HeadlessEventType type;
  final dynamic payload;
  const HeadlessEvent({required this.type, required this.payload});
}
