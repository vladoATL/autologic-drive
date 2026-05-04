import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import 'server_presets.dart';
import 'tracking/tracking_config.dart';

class Preferences {
  static Future<void>? _initFuture;
  static late SharedPreferencesWithCache instance;

  static const String id = 'id';
  static const String url = 'url';
  static const String accuracy = 'accuracy';
  static const String distance = 'distance';
  static const String interval = 'interval';
  static const String angle = 'angle';
  static const String heartbeat = 'heartbeat';
  static const String fastestInterval = 'fastest_interval';
  static const String buffer = 'buffer';
  static const String wakelock = 'wakelock';
  static const String stopDetection = 'stop_detection';
  static const String password = 'password';
  static const String language = 'language';
  static const String autoDetect = 'auto_detect';
  static const String apiUrl = 'api_url';
  /// AutoLogic Backend (.NET 10) base URL — separate from Traccar `apiUrl`
  /// because the two services run on different ports (Traccar admin :8082,
  /// AutoLogic Backend :8080). Used by `BackendApi`, `PositionSender`
  /// and `TripSync`.
  static const String backendApiUrl = 'backend_api_url';
  static const String authCookie = 'auth_cookie';
  static const String authEmail = 'auth_email';
  static const String authUserId = 'auth_user_id';
  static const String driverName = 'driver_name';
  // AutoLogic Backend (.NET) tokens — separate from Traccar /api/session.
  // Set when the user is paired via QR or logs in through /api/v1/auth/login.
  static const String backendAccessToken = 'backend_access_token';
  static const String backendRefreshToken = 'backend_refresh_token';
  static const String backendAccessExpiresAt = 'backend_access_expires_at';
  static const String backendUserId = 'backend_user_id';
  static const String backendTenantId = 'backend_tenant_id';
  static const String backendRole = 'backend_role';
  static const String onboardingDone = 'onboarding_done';
  static const String minTripDistanceMeters = 'min_trip_distance_m';
  static const int defaultMinTripDistanceMeters = 200;
  static const String tripRetentionDays = 'trip_retention_days';
  static const int defaultTripRetentionDays = 60;
  /// Sentinel for "never delete" — stored as -1 in the pref.
  static const int tripRetentionNever = -1;
  static const String backendSyncEnabled = 'backend_sync_enabled';
  static const String monitorServiceEnabled = 'monitor_service_enabled';

  static const String lastTimestamp = 'lastTimestamp';
  static const String lastLatitude = 'lastLatitude';
  static const String lastLongitude = 'lastLongitude';
  static const String lastHeading = 'lastHeading';

  static Future<void> init() async {
    _initFuture ??= _createInstance();
    await _initFuture;
  }

  static Future<void> _createInstance() async {
    instance = await SharedPreferencesWithCache.create(
      sharedPreferencesOptions: Platform.isAndroid
        ? SharedPreferencesAsyncAndroidOptions(backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences)
        : SharedPreferencesOptions(),
      cacheOptions: SharedPreferencesWithCacheOptions(
        allowList: {
          id, url, accuracy, distance, interval, angle, heartbeat,
          fastestInterval, buffer,  wakelock, stopDetection, password, language, autoDetect,
          apiUrl, backendApiUrl, authCookie, authEmail, authUserId, driverName, onboardingDone,
          backendAccessToken, backendRefreshToken, backendAccessExpiresAt,
          backendUserId, backendTenantId, backendRole,
          minTripDistanceMeters,
          tripRetentionDays,
          backendSyncEnabled,
          monitorServiceEnabled,
          lastTimestamp, lastLatitude, lastLongitude, lastHeading,
          // Trip + vehicles (TripController, VehicleRepository, OsmAndSender):
          'trip_active', 'trip_vehicle_mac', 'trip_started_at', 'trip_source',
          'trip_record_id',
          'vehicles', 'osmand_outbox',
        },
      ),
    );
    if (instance.getString(id) == null) {
      await instance.setString(id, (Random().nextInt(90000000) + 10000000).toString());
      await instance.setString(url, kAutoLogicServer.url);
      // Tighter defaults for trip use case: GPS sample every ~20 m so
      // Traccar's straight-line map rendering between points still follows
      // the road. The fastest interval (30 s) caps how often we sample at
      // a stoplight; the 60 s interval is the floor when distanceFilter
      // wouldn't have triggered yet.
      await instance.setString(accuracy, 'high');
      await instance.setInt(interval, 60);
      await instance.setInt(distance, 20);
      await instance.setBool(buffer, true);
      await instance.setBool(stopDetection, true);
      await instance.setInt(fastestInterval, 30);
      await instance.setString(language, 'sk');
      await instance.setString(apiUrl, kAutoLogicServer.apiUrl);
      await instance.setString(backendApiUrl, kAutoLogicServer.backendApiUrl);
    }
    // Migration: pre-0.5.0 installs don't have apiUrl seeded.
    final existingApi = instance.getString(apiUrl);
    if (existingApi == null || existingApi.isEmpty) {
      await instance.setString(apiUrl, kAutoLogicServer.apiUrl);
    }
    // Migration: pre-0.13.1 installs reused `apiUrl` for the backend; that
    // pointed at Traccar admin :8082 which doesn't host /api/v1/auth/*.
    // Seed `backendApiUrl` from the preset so PositionSender / BackendApi
    // hit :8080.
    final existingBackend = instance.getString(backendApiUrl);
    if (existingBackend == null || existingBackend.isEmpty) {
      await instance.setString(backendApiUrl, kAutoLogicServer.backendApiUrl);
    }
    // Migration: pre-0.8.1 installs had distance=75 / interval=300 which
    // produced jagged Traccar route lines. Bump to the new tighter defaults
    // unless the driver intentionally raised them.
    if ((instance.getInt(distance) ?? 0) >= 75) {
      await instance.setInt(distance, 20);
    }
    if ((instance.getInt(interval) ?? 0) >= 300) {
      await instance.setInt(interval, 60);
    }
  }

  static TrackingConfig trackingConfig(bool reset) {
    return TrackingConfig(
      reset: reset,
      accuracy: switch (instance.getString(accuracy)) {
        'highest' => TrackingAccuracy.highest,
        'high' => TrackingAccuracy.high,
        'low' => TrackingAccuracy.low,
        _ => TrackingAccuracy.medium,
      },
      distanceFilterMeters: instance.getInt(distance),
      locationUpdateIntervalSeconds: instance.getInt(interval),
      fastestLocationUpdateIntervalSeconds: instance.getInt(fastestInterval) ?? 30,
      heartbeatIntervalSeconds: instance.getInt(heartbeat) ?? 0,
      stopDetection: instance.getBool(stopDetection) ?? true,
      buffer: instance.getBool(buffer) != false,
      serverUrl: instance.getString(url),
      deviceId: instance.getString(id),
      locationBodyTemplate: _locationTemplate(),
    );
  }

  static String _locationTemplate() {
    return '''{
      "timestamp": "<%= timestamp %>",
      "coords": {
        "latitude": <%= latitude %>,
        "longitude": <%= longitude %>,
        "accuracy": <%= accuracy %>,
        "speed": <%= speed %>,
        "heading": <%= heading %>,
        "altitude": <%= altitude %>
      },
      "is_moving": <%= is_moving %>,
      "odometer": <%= odometer %>,
      "event": "<%= event %>",
      "battery": {
        "level": <%= battery.level %>,
        "is_charging": <%= battery.is_charging %>
      },
      "activity": {
        "type": "<%= activity.type %>"
      },
      "extras": {},
      "_": "&id=${instance.getString(id)}&lat=<%= latitude %>&lon=<%= longitude %>&timestamp=<%= timestamp %>&"
    }'''.split('\n').map((line) => line.trimLeft()).join();
  }
}
