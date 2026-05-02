import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:wakelock_partial_android/wakelock_partial_android.dart';

import 'location_cache.dart';
import 'preferences.dart';
import 'tracking/engine.dart';
import 'tracking/tracking_engine.dart';
import 'util/app_logger.dart';

class GeolocationService {
  static Future<void> init() async {
    await engine.ready(Preferences.trackingConfig(false));
    if (Platform.isAndroid) {
      engine.registerHeadlessTask(headlessTask);
    }
    engine.onEnabledChange(_onEnabledChange);
    engine.onMotionChange(onMotionChange);
    engine.onHeartbeat(onHeartbeat);
    engine.onLocation(onLocation, (error) {
      developer.log('Location error', error: error);
    });
  }

  static void _onEnabledChange(bool enabled) {
    onEnabledChange(enabled);
  }

  static Future<void> onEnabledChange(bool enabled) async {
    if (Preferences.instance.getBool(Preferences.wakelock) ?? false) {
      if (!enabled) {
        await WakelockPartialAndroid.release();
      }
    }
  }

  static Future<void> onMotionChange(TrackedLocation location) async {
    AppLogger.info(
      'Motion: ${location.isMoving ? "MOVING" : "stationary"} '
      '(${(location.speed * 3.6).toStringAsFixed(0)} km/h)',
    );
    if (Preferences.instance.getBool(Preferences.wakelock) ?? false) {
      if (location.isMoving) {
        await WakelockPartialAndroid.acquire();
      } else {
        await WakelockPartialAndroid.release();
      }
    }
  }

  static Future<void> onHeartbeat() async {
    await engine.getCurrentPosition(
      samples: 1,
      persist: true,
      extras: {'heartbeat': true},
    );
  }

  static Future<void> onLocation(TrackedLocation location) async {
    if (_shouldDelete(location)) {
      try {
        await engine.destroyLocation(location.uuid);
      } catch (error) {
        developer.log('Failed to delete location', error: error);
      }
    } else {
      LocationCache.set(location);
      try {
        await engine.dispatchLocation(location);
      } catch (error) {
        developer.log('Failed to send location', error: error);
      }
    }
  }

  static bool _shouldDelete(TrackedLocation location) {
    if (!location.isMoving) return false;
    if (location.extras.isNotEmpty) return false;

    final lastLocation = LocationCache.get();
    if (lastLocation == null) return false;

    final isHighestAccuracy = Preferences.instance.getString(Preferences.accuracy) == 'highest';
    final duration =
        DateTime.parse(location.timestamp).difference(DateTime.parse(lastLocation.timestamp)).inSeconds;

    if (!isHighestAccuracy) {
      final fastestInterval = Preferences.instance.getInt(Preferences.fastestInterval);
      if (fastestInterval != null && duration < fastestInterval) return true;
    }

    final distance = _distance(lastLocation, location);

    final distanceFilter = Preferences.instance.getInt(Preferences.distance) ?? 0;
    if (distanceFilter > 0 && distance >= distanceFilter) return false;

    if (distanceFilter == 0 || isHighestAccuracy) {
      final intervalFilter = Preferences.instance.getInt(Preferences.interval) ?? 0;
      if (intervalFilter > 0 && duration >= intervalFilter) return false;
    }

    if (isHighestAccuracy && lastLocation.heading >= 0 && location.heading > 0) {
      final angle = (location.heading - lastLocation.heading).abs();
      final angleFilter = Preferences.instance.getInt(Preferences.angle) ?? 0;
      if (angleFilter > 0 && angle >= angleFilter) return false;
    }

    return true;
  }

  static double _distance(CachedLocation from, TrackedLocation to) {
    const earthRadius = 6371008.8; // meters
    final dLat = _degToRad(to.latitude - from.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);
    final sinLat = sin(dLat / 2);
    final sinLon = sin(dLon / 2);
    final a = sinLat * sinLat +
        cos(_degToRad(from.latitude)) * cos(_degToRad(to.latitude)) * sinLon * sinLon;
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double degree) => degree * pi / 180.0;
}

@pragma('vm:entry-point')
Future<void> headlessTask(HeadlessEvent event) async {
  await Preferences.init();
  switch (event.type) {
    case HeadlessEventType.enabledChange:
      await GeolocationService.onEnabledChange(event.payload as bool);
    case HeadlessEventType.motionChange:
      await GeolocationService.onMotionChange(event.payload as TrackedLocation);
    case HeadlessEventType.heartbeat:
      await GeolocationService.onHeartbeat();
    case HeadlessEventType.location:
      await GeolocationService.onLocation(event.payload as TrackedLocation);
    case HeadlessEventType.unknown:
      break;
  }
}
