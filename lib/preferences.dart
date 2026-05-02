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
          lastTimestamp, lastLatitude, lastLongitude, lastHeading,
          // Trip + vehicles (TripController, VehicleRepository, OsmAndSender):
          'trip_active', 'trip_vehicle_mac', 'trip_started_at', 'trip_source',
          'vehicles', 'osmand_outbox',
        },
      ),
    );
    if (instance.getString(id) == null) {
      await instance.setString(id, (Random().nextInt(90000000) + 10000000).toString());
      await instance.setString(url, kAutoLogicServer.url);
      await instance.setString(accuracy, 'medium');
      await instance.setInt(interval, 300);
      await instance.setInt(distance, 75);
      await instance.setBool(buffer, true);
      await instance.setBool(stopDetection, true);
      await instance.setInt(fastestInterval, 30);
      await instance.setString(language, 'sk');
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
