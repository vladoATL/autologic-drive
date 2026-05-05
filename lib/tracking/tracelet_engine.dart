/// Tracelet adapter for `TrackingEngine`.
///
/// Tracelet is the open-source (Apache 2.0) replacement for the commercial
/// `flutter_background_geolocation` SDK. It provides the GPS lifecycle
/// (motion detection, geofencing, battery-aware sampling, headless background
/// execution) but its built-in HTTP sync posts JSON, while Traccar's OsmAnd
/// protocol on port 5055 wants query-string parameters. We therefore disable
/// Tracelet's HttpConfig and ship positions through `OsmAndSender` instead.
library;

import 'dart:io';

import 'package:tracelet/tracelet.dart' as tl;

import '../geolocation_service.dart' as geo;
import '../preferences.dart';
import '../sync/position_sender.dart';
import '../trip/live_trip_distance.dart';
import '../trip/trip_controller.dart';
import 'osmand_sender.dart';
import 'tracking_config.dart';
import 'tracking_engine.dart';

class TraceletEngine implements TrackingEngine {
  const TraceletEngine();

  @override
  Future<void> ready(TrackingConfig config) async {
    await tl.Tracelet.ready(_buildTlConfig(config));
  }

  @override
  Future<void> setConfig(TrackingConfig config) async {
    await tl.Tracelet.setConfig(_buildTlConfig(config));
  }

  @override
  Future<TrackingState> getState() async {
    final state = await tl.Tracelet.getState();
    return TrackingState(enabled: state.enabled, isMoving: state.isMoving);
  }

  @override
  Future<bool> start() async {
    await _ensureLocationAuthorization();
    final state = await tl.Tracelet.start();
    return state.enabled;
  }

  @override
  Future<bool> stop() async {
    final state = await tl.Tracelet.stop();
    return state.enabled;
  }

  @override
  Future<TrackedLocation> getCurrentPosition({
    int samples = 1,
    bool persist = true,
    Map<String, dynamic>? extras,
  }) async {
    await _ensureLocationAuthorization();
    final loc = await tl.Tracelet.getCurrentPosition();
    return _toTrackedLocation(loc);
  }

  /// Only ask for location permission when we don't already have it.
  /// Without this guard, Tracelet treats every call as a fresh prompt and
  /// jumps straight to the system Settings page when foreground access is
  /// granted but background isn't — flickering for the user.
  Future<void> _ensureLocationAuthorization() async {
    final current = await tl.Tracelet.getLocationAuthorization();
    if (current == tl.AuthorizationStatus.always ||
        current == tl.AuthorizationStatus.whenInUse) {
      return;
    }
    final result = await tl.Tracelet.requestLocationAuthorization();
    if (result != tl.AuthorizationStatus.always &&
        result != tl.AuthorizationStatus.whenInUse) {
      // Without at least foreground location permission, Tracelet's
      // foreground location service hits a SecurityException at startup
      // (Android 14+). Abort early so the caller can show an error.
      throw StateError('location_permission_denied');
    }
  }

  @override
  Future<void> dispatchLocation(TrackedLocation location) async {
    // Parallel sink: feed the AutoLogic Backend's positions buffer so the
    // Web Admin can render the real driven polyline. This is independent
    // of Traccar — failures here never block OsmAndSender below.
    final activeTrip = TripController.activeRecordId;
    if (activeTrip != null && activeTrip.isNotEmpty) {
      PositionSender.enqueue(activeTrip, location);
      LiveTripDistance.addPoint(location.latitude, location.longitude);
    }

    final url = Preferences.instance.getString(Preferences.url);
    final id = Preferences.instance.getString(Preferences.id);
    if (url == null || id == null) return;
    await OsmAndSender.send(url: url, deviceId: id, loc: location);
  }

  @override
  Future<void> sync() async {
    // No-op: Tracelet's built-in HTTP sync is disabled (it posts JSON, not
    // OsmAnd query-strings). `dispatchLocation` is the per-location entry
    // point and `OsmAndSender` handles its own retry queue.
  }

  @override
  Future<void> destroyLocation(String uuid) async {
    await tl.Tracelet.destroyLocation(uuid);
  }

  @override
  void onEnabledChange(void Function(bool enabled) cb) {
    tl.Tracelet.onEnabledChange(cb);
  }

  @override
  void onMotionChange(void Function(TrackedLocation location) cb) {
    tl.Tracelet.onMotionChange((loc) => cb(_toTrackedLocation(loc)));
  }

  @override
  void onLocation(
    void Function(TrackedLocation location) cb,
    void Function(Object error) onError,
  ) {
    tl.Tracelet.onLocation((loc) => cb(_toTrackedLocation(loc)));
    // Tracelet doesn't expose per-stream onError on `onLocation`; failures
    // surface through `onProviderChange` / `onAuthorization`. Caller-supplied
    // `onError` is kept for symmetry but currently unused.
  }

  @override
  void onHeartbeat(void Function() cb) {
    tl.Tracelet.onHeartbeat((_) => cb());
  }

  @override
  void registerHeadlessTask(Future<void> Function(HeadlessEvent event) cb) {
    // Tracelet's headless dispatcher requires a TOP-LEVEL or STATIC function
    // (it serialises the callback via `PluginUtilities.getCallbackHandle`,
    // which rejects closures). We therefore ignore the caller-supplied `cb`
    // and register a fixed top-level forwarder that translates
    // `tl.HeadlessEvent` to our `HeadlessEvent` and calls
    // `geolocation_service.headlessTask` directly.
    tl.Tracelet.registerHeadlessTask(traceletHeadlessForwarder);
  }

  @override
  Future<TrackingProviderState> getProviderState() async {
    final state = await tl.Tracelet.getProviderState();
    return TrackingProviderState(
      gpsEnabled: state.gps,
      networkEnabled: state.network,
      status: switch (state.status) {
        tl.AuthorizationStatus.denied ||
        tl.AuthorizationStatus.deniedForever => TrackingAuthorizationStatus.denied,
        tl.AuthorizationStatus.always ||
        tl.AuthorizationStatus.whenInUse => TrackingAuthorizationStatus.granted,
        tl.AuthorizationStatus.notDetermined => TrackingAuthorizationStatus.notDetermined,
      },
    );
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() =>
      tl.Tracelet.isIgnoringBatteryOptimizations();

  @override
  Future<void> requestIgnoreBatteryOptimizations() async {
    await tl.Tracelet.openBatterySettings();
  }

  @override
  Future<String> getLog() => tl.Tracelet.getLog();

  @override
  Future<void> emailLog(String email) async {
    await tl.Tracelet.emailLog(email);
  }

  @override
  Future<void> destroyLog() async {
    await tl.Tracelet.destroyLog();
  }

  static TrackedLocation _toTrackedLocation(tl.Location loc) {
    return TrackedLocation(
      uuid: loc.uuid,
      timestamp: loc.timestamp,
      latitude: loc.coords.latitude,
      longitude: loc.coords.longitude,
      accuracy: loc.coords.accuracy,
      speed: loc.coords.speed,
      heading: loc.coords.heading,
      altitude: loc.coords.altitude,
      isMoving: loc.isMoving,
      batteryLevel: loc.battery.level,
      batteryCharging: loc.battery.isCharging,
      activityType: loc.activity.type.name,
      odometer: loc.odometer,
      extras: loc.extras.map((k, v) => MapEntry(k, v)),
    );
  }

  static HeadlessEvent toHeadlessEvent(tl.HeadlessEvent event) =>
      _toHeadlessEvent(event);

  static HeadlessEvent _toHeadlessEvent(tl.HeadlessEvent event) {
    final type = switch (event.name) {
      'enabledchange' => HeadlessEventType.enabledChange,
      'motionchange' => HeadlessEventType.motionChange,
      'heartbeat' => HeadlessEventType.heartbeat,
      'location' => HeadlessEventType.location,
      _ => HeadlessEventType.unknown,
    };
    final payload = switch (type) {
      HeadlessEventType.location || HeadlessEventType.motionChange =>
        _toTrackedLocation(tl.Location.fromMap(event.event)),
      HeadlessEventType.enabledChange =>
        event.event['enabled'] as bool? ?? false,
      _ => event.event,
    };
    return HeadlessEvent(type: type, payload: payload);
  }
}

@pragma('vm:entry-point')
Future<void> traceletHeadlessForwarder(tl.HeadlessEvent event) async {
  await Preferences.init();
  await geo.headlessTask(TraceletEngine.toHeadlessEvent(event));
}

tl.Config _buildTlConfig(TrackingConfig c) {
  final isHighest = c.isHighestAccuracy;
  final locUpdateMs = (c.locationUpdateIntervalSeconds ?? 0) * 1000;
  final fastestLocUpdateMs = (c.fastestLocationUpdateIntervalSeconds ?? 30) * 1000;
  final heartbeat = c.heartbeatIntervalSeconds ?? 0;

  return tl.Config(
    geo: tl.GeoConfig(
      desiredAccuracy: switch (c.accuracy) {
        // Tracelet has no `highest`/`navigation` tier — `high` is the top.
        TrackingAccuracy.highest => tl.DesiredAccuracy.high,
        TrackingAccuracy.high => tl.DesiredAccuracy.high,
        TrackingAccuracy.medium => tl.DesiredAccuracy.medium,
        TrackingAccuracy.low => tl.DesiredAccuracy.low,
      },
      distanceFilter: isHighest ? 0 : (c.distanceFilterMeters?.toDouble() ?? 10),
      locationUpdateInterval: Platform.isAndroid
          ? (isHighest ? 0 : (locUpdateMs > 0 ? locUpdateMs : 1000))
          : 1000,
      fastestLocationUpdateInterval:
          Platform.isAndroid ? (isHighest ? 0 : fastestLocUpdateMs) : 500,
      disableElasticity: true,
      pausesLocationUpdatesAutomatically: Platform.isIOS && !isHighest && c.stopDetection,
      showsBackgroundLocationIndicator: false,
      // Cap battery drain to ~5% per hour of active tracking. Tracelet
      // self-tunes accuracy / sampling to stay within this budget. 0.0
      // disables the budget engine.
      batteryBudgetPerHour: 5.0,
      // Let Tracelet adjust GeoConfig dynamically based on speed / activity
      // (driving → standard sampling; walking → coarser; idle → significant
      // changes only). Plays nicely with stopDetection.
      enableAdaptiveMode: true,
    ),
    motion: tl.MotionConfig(
      disableStopDetection: !c.stopDetection,
      // Treat the device as stationary after 3 minutes of no motion (default
      // is 5). Shorter window means faster transition to low-power sampling
      // when stopped at lights / parked.
      stopTimeout: 3,
      // Use accelerometer-only motion classification — avoids needing the
      // ACTIVITY_RECOGNITION runtime permission while still detecting
      // moving↔stationary transitions reliably.
      disableMotionActivityUpdates: true,
    ),
    app: tl.AppConfig(
      stopOnTerminate: false,
      startOnBoot: true,
      heartbeatInterval: heartbeat > 0 ? heartbeat : -1,
      preventSuspend: Platform.isIOS && heartbeat > 0,
      foregroundService: const tl.ForegroundServiceConfig(
        channelId: 'autologic_tracking',
        channelName: 'AutoLogic Drive — sledovanie',
        notificationTitle: 'AutoLogic Drive',
        notificationText: 'Zaznamenávam jazdu',
        notificationSmallIcon: 'drawable/ic_stat_notify',
      ),
    ),
    persistence: tl.PersistenceConfig(
      maxRecordsToPersist: c.buffer ? -1 : 1,
    ),
    logger: const tl.LoggerConfig(
      logLevel: tl.LogLevel.verbose,
    ),
    // HttpConfig intentionally omitted (defaults to disabled `url: null`)
    // — we ship via OsmAndSender, not Tracelet's built-in JSON sync.
  );
}
