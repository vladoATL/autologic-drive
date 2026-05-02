/// Single source of truth for trip lifecycle.
///
/// `start()` flips trip on, persists the state, and tells the tracking engine
/// to start recording. `stop()` does the inverse. The tracking engine therefore
/// only burns GPS / battery while a trip is active.
library;

import '../preferences.dart';
import '../tracking/engine.dart';
import '../util/app_logger.dart';
import '../util/notifications.dart';
import 'trip_state.dart';
import 'vehicle.dart';
import 'vehicle_repository.dart';

class TripController {
  static const _kActive = 'trip_active';
  static const _kVehicleMac = 'trip_vehicle_mac';
  static const _kStartedAt = 'trip_started_at';
  static const _kSource = 'trip_source';

  /// Restore last known trip state from `SharedPreferences`. Call once on app
  /// startup, after `Preferences.init()`. If a trip was active when the app
  /// died, we keep the engine running.
  static Future<void> restore() async {
    final active = Preferences.instance.getBool(_kActive) ?? false;
    if (!active) {
      tripState.value = TripSnapshot.idle;
      return;
    }
    final mac = Preferences.instance.getString(_kVehicleMac);
    final startedAt = Preferences.instance.getInt(_kStartedAt);
    final sourceName = Preferences.instance.getString(_kSource);
    Vehicle? vehicle;
    if (mac != null) vehicle = VehicleRepository.findByMac(mac);

    tripState.value = TripSnapshot(
      active: true,
      vehicleMac: mac,
      vehicleLabel: vehicle?.label,
      startedAt: startedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(startedAt)
          : null,
      source: TripTriggerSource.values.firstWhere(
        (s) => s.name == sourceName,
        orElse: () => TripTriggerSource.manual,
      ),
    );
    // The engine config persists across app restarts, but tracking itself
    // does not — re-arm it when restoring an active trip.
    final engineState = await engine.getState();
    if (!engineState.enabled) {
      await engine.start();
    }
  }

  static Future<void> start({
    Vehicle? vehicle,
    TripTriggerSource source = TripTriggerSource.manual,
  }) async {
    if (tripState.value.active) return;
    AppLogger.info(
      'Trip start requested (source=${source.name}, vehicle=${vehicle?.label ?? "none"})',
    );
    // Bring up the engine FIRST. If it fails (most often: location permission
    // refused), we never flip the trip state on, so the UI stays consistent
    // and the caller can surface the error.
    try {
      await engine.start();
    } catch (error) {
      AppLogger.error('Engine start failed: $error');
      rethrow;
    }
    final now = DateTime.now();
    await Preferences.instance.setBool(_kActive, true);
    await Preferences.instance.setString(_kVehicleMac, vehicle?.bluetoothMac ?? '');
    await Preferences.instance.setInt(_kStartedAt, now.millisecondsSinceEpoch);
    await Preferences.instance.setString(_kSource, source.name);
    tripState.value = TripSnapshot(
      active: true,
      vehicleMac: vehicle?.bluetoothMac,
      vehicleLabel: vehicle?.label,
      startedAt: now,
      source: source,
    );
    AppLogger.info('Trip started');
    AppNotifications.showTripStarted(vehicleLabel: vehicle?.label);
  }

  static Future<void> stop() async {
    if (!tripState.value.active) return;
    final duration = tripState.value.startedAt != null
        ? DateTime.now().difference(tripState.value.startedAt!)
        : null;
    AppLogger.info(
      'Trip stop (vehicle=${tripState.value.vehicleLabel ?? "none"}'
      '${duration != null ? ", duration=${duration.inSeconds}s" : ""})',
    );
    final stoppedLabel = tripState.value.vehicleLabel;
    await engine.stop();
    await Preferences.instance.setBool(_kActive, false);
    await Preferences.instance.setString(_kVehicleMac, '');
    await Preferences.instance.setString(_kSource, '');
    tripState.value = TripSnapshot.idle;
    AppNotifications.showTripStopped(
      vehicleLabel: stoppedLabel,
      duration: duration,
    );
  }
}
