/// `flutter_background_geolocation` adapter for `TrackingEngine`.
///
/// This is the 0.2.0 default engine. It wraps the (commercial) transistorsoft
/// SDK so the rest of the app can talk to it through the engine-agnostic
/// abstraction. In 0.3.0 a `TraceletEngine` will sit alongside this one.
library;

import 'dart:io';

import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;

import 'tracking_config.dart';
import 'tracking_engine.dart';

class FbgEngine implements TrackingEngine {
  const FbgEngine();

  @override
  Future<void> ready(TrackingConfig config) async {
    await bg.BackgroundGeolocation.ready(_buildBgConfig(config));
  }

  @override
  Future<void> setConfig(TrackingConfig config) async {
    await bg.BackgroundGeolocation.setConfig(_buildBgConfig(config));
  }

  @override
  Future<TrackingState> getState() async {
    final state = await bg.BackgroundGeolocation.state;
    return TrackingState(enabled: state.enabled, isMoving: state.isMoving);
  }

  @override
  Future<bool> start() async {
    final state = await bg.BackgroundGeolocation.start();
    return state.enabled;
  }

  @override
  Future<bool> stop() async {
    final state = await bg.BackgroundGeolocation.stop();
    return state.enabled;
  }

  @override
  Future<TrackedLocation> getCurrentPosition({
    int samples = 1,
    bool persist = true,
    Map<String, dynamic>? extras,
  }) async {
    final loc = await bg.BackgroundGeolocation.getCurrentPosition(
      samples: samples,
      persist: persist,
      extras: extras,
    );
    return _toTrackedLocation(loc);
  }

  @override
  Future<void> sync() => bg.BackgroundGeolocation.sync();

  @override
  Future<void> destroyLocation(String uuid) =>
      bg.BackgroundGeolocation.destroyLocation(uuid);

  @override
  void onEnabledChange(void Function(bool enabled) cb) {
    bg.BackgroundGeolocation.onEnabledChange(cb);
  }

  @override
  void onMotionChange(void Function(TrackedLocation location) cb) {
    bg.BackgroundGeolocation.onMotionChange((loc) => cb(_toTrackedLocation(loc)));
  }

  @override
  void onLocation(
    void Function(TrackedLocation location) cb,
    void Function(Object error) onError,
  ) {
    bg.BackgroundGeolocation.onLocation(
      (loc) => cb(_toTrackedLocation(loc)),
      (error) => onError(error),
    );
  }

  @override
  void onHeartbeat(void Function() cb) {
    bg.BackgroundGeolocation.onHeartbeat((_) => cb());
  }

  @override
  void registerHeadlessTask(Future<void> Function(HeadlessEvent event) cb) {
    bg.BackgroundGeolocation.registerHeadlessTask((bg.HeadlessEvent event) async {
      await cb(_toHeadlessEvent(event));
    });
  }

  @override
  Future<TrackingProviderState> getProviderState() async {
    final state = await bg.BackgroundGeolocation.providerState;
    return TrackingProviderState(
      gpsEnabled: state.gps,
      networkEnabled: state.network,
      status: switch (state.status) {
        bg.ProviderChangeEvent.AUTHORIZATION_STATUS_DENIED => TrackingAuthorizationStatus.denied,
        bg.ProviderChangeEvent.AUTHORIZATION_STATUS_RESTRICTED => TrackingAuthorizationStatus.restricted,
        bg.ProviderChangeEvent.AUTHORIZATION_STATUS_ALWAYS => TrackingAuthorizationStatus.granted,
        bg.ProviderChangeEvent.AUTHORIZATION_STATUS_WHEN_IN_USE => TrackingAuthorizationStatus.granted,
        _ => TrackingAuthorizationStatus.notDetermined,
      },
    );
  }

  @override
  Future<bool> isIgnoringBatteryOptimizations() =>
      bg.DeviceSettings.isIgnoringBatteryOptimizations;

  @override
  Future<void> requestIgnoreBatteryOptimizations() async {
    final request = await bg.DeviceSettings.showIgnoreBatteryOptimizations();
    if (!request.seen) {
      await bg.DeviceSettings.show(request);
    }
  }

  @override
  Future<String> getLog() async {
    final entries = await bg.Logger.getLog(bg.SQLQuery(order: bg.SQLQuery.ORDER_DESC));
    return entries.toString();
  }

  @override
  Future<void> emailLog(String email) =>
      bg.Logger.emailLog(email, bg.SQLQuery(order: bg.SQLQuery.ORDER_DESC));

  @override
  Future<void> destroyLog() => bg.Logger.destroyLog();

  static TrackedLocation _toTrackedLocation(bg.Location loc) {
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
      activityType: loc.activity.type,
      odometer: loc.odometer,
      extras: loc.extras?.cast<String, dynamic>() ?? const {},
    );
  }

  static HeadlessEvent _toHeadlessEvent(bg.HeadlessEvent event) {
    final type = switch (event.name) {
      bg.Event.ENABLEDCHANGE => HeadlessEventType.enabledChange,
      bg.Event.MOTIONCHANGE => HeadlessEventType.motionChange,
      bg.Event.HEARTBEAT => HeadlessEventType.heartbeat,
      bg.Event.LOCATION => HeadlessEventType.location,
      _ => HeadlessEventType.unknown,
    };
    final payload = switch (type) {
      HeadlessEventType.location || HeadlessEventType.motionChange =>
        _toTrackedLocation(event.event as bg.Location),
      _ => event.event,
    };
    return HeadlessEvent(type: type, payload: payload);
  }

  static bg.Config _buildBgConfig(TrackingConfig c) {
    final isHighest = c.isHighestAccuracy;
    final locUpdateMs = (c.locationUpdateIntervalSeconds ?? 0) * 1000;
    final fastestLocUpdateMs = (c.fastestLocationUpdateIntervalSeconds ?? 30) * 1000;
    final heartbeat = c.heartbeatIntervalSeconds ?? 0;

    return bg.Config(
      reset: c.reset,
      geolocation: bg.GeoConfig(
        desiredAccuracy: switch (c.accuracy) {
          TrackingAccuracy.highest =>
            Platform.isIOS ? bg.DesiredAccuracy.navigation : bg.DesiredAccuracy.high,
          TrackingAccuracy.high => bg.DesiredAccuracy.high,
          TrackingAccuracy.low => bg.DesiredAccuracy.low,
          TrackingAccuracy.medium => bg.DesiredAccuracy.medium,
        },
        distanceFilter: isHighest ? 0 : c.distanceFilterMeters?.toDouble(),
        locationUpdateInterval: Platform.isAndroid
            ? (isHighest ? 0 : (locUpdateMs > 0 ? locUpdateMs : null))
            : null,
        fastestLocationUpdateInterval:
            Platform.isAndroid ? (isHighest ? 0 : fastestLocUpdateMs) : null,
        disableElasticity: true,
        pausesLocationUpdatesAutomatically:
            Platform.isIOS ? !(isHighest || !c.stopDetection) : null,
        showsBackgroundLocationIndicator: Platform.isIOS ? false : null,
      ),
      app: bg.AppConfig(
        enableHeadless: Platform.isAndroid ? true : null,
        stopOnTerminate: false,
        startOnBoot: true,
        heartbeatInterval: heartbeat > 0 ? heartbeat.toDouble() : null,
        preventSuspend: Platform.isIOS ? (heartbeat > 0) : null,
        backgroundPermissionRationale: Platform.isAndroid
            ? bg.PermissionRationale(
                title:
                    'Allow {applicationName} to access this device\'s location in the background',
                message:
                    'For reliable tracking, please enable {backgroundPermissionOptionLabel} location access.',
                positiveAction: 'Change to {backgroundPermissionOptionLabel}',
                negativeAction: 'Cancel')
            : null,
        notification: Platform.isAndroid
            ? bg.Notification(
                smallIcon: 'drawable/ic_stat_notify',
                priority: bg.NotificationPriority.low,
              )
            : null,
      ),
      http: bg.HttpConfig(
        autoSync: false,
        url: _formatUrl(c.serverUrl),
        params: {if (c.deviceId != null) 'device_id': c.deviceId},
      ),
      logger: const bg.LoggerConfig(
        logLevel: bg.LogLevel.verbose,
        logMaxDays: 1,
      ),
      activity: bg.ActivityConfig(
        disableStopDetection: !c.stopDetection,
      ),
      persistence: bg.PersistenceConfig(
        maxRecordsToPersist: c.buffer ? -1 : 1,
        locationTemplate: c.locationBodyTemplate,
      ),
    );
  }

  static String? _formatUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.parse(url);
    if ((uri.path.isEmpty || uri.path == '') && !url.endsWith('/')) return '$url/';
    return url;
  }
}
