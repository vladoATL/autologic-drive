/// Single source of truth for trip lifecycle.
///
/// `start()` flips trip on, persists the state, and tells the tracking engine
/// to start recording. `stop()` does the inverse. The tracking engine therefore
/// only burns GPS / battery while a trip is active.
library;

import 'dart:math' as math;

import '../location_cache.dart';
import '../preferences.dart';
import '../sync/position_sender.dart';
import '../sync/trip_sync.dart';
import '../tracking/engine.dart';
import '../util/app_logger.dart';
import '../util/notifications.dart';
import 'live_trip_distance.dart';
import 'trip_record.dart';
import 'trip_repository.dart';
import 'trip_state.dart';
import 'vehicle.dart';
import 'vehicle_repository.dart';

class TripController {
  static const _kActive = 'trip_active';
  static const _kVehicleMac = 'trip_vehicle_mac';
  static const _kStartedAt = 'trip_started_at';
  static const _kSource = 'trip_source';
  static const _kRecordId = 'trip_record_id';

  /// ID of the active TripRecord row. Notifications and the UI use this to
  /// deep-link into TripDetailScreen for the trip just started/stopped.
  static String? activeRecordId;

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

    activeRecordId = Preferences.instance.getString(_kRecordId);
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

  /// Reentry guard. BluetoothWatcher emits both broadcast events and
  /// foreground polls in quick succession; without this, two concurrent
  /// callers can race past the `tripState.active` check and create
  /// duplicate trip records (observed in the 2026-05-05 test drive).
  static bool _starting = false;

  static Future<void> start({
    Vehicle? vehicle,
    TripTriggerSource source = TripTriggerSource.manual,
  }) async {
    if (tripState.value.active || _starting) {
      AppLogger.info('Trip start ignored — already active or starting');
      return;
    }
    _starting = true;
    LiveTripDistance.resetForTripStart();
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
      _starting = false;
      rethrow;
    }
    final now = DateTime.now();
    final cached = LocationCache.get();
    final recordId = TripRepository.newId();
    final record = TripRecord(
      id: recordId,
      startedAt: now,
      vehicleMac: vehicle?.bluetoothMac,
      vehicleLabel: vehicle?.label,
      driverName: Preferences.instance.getString(Preferences.driverName),
      source: source,
      startLat: cached?.latitude,
      startLng: cached?.longitude,
    );
    await TripRepository.insert(record);
    activeRecordId = recordId;

    await Preferences.instance.setBool(_kActive, true);
    await Preferences.instance.setString(_kVehicleMac, vehicle?.bluetoothMac ?? '');
    await Preferences.instance.setInt(_kStartedAt, now.millisecondsSinceEpoch);
    await Preferences.instance.setString(_kSource, source.name);
    await Preferences.instance.setString(_kRecordId, recordId);
    tripState.value = TripSnapshot(
      active: true,
      vehicleMac: vehicle?.bluetoothMac,
      vehicleLabel: vehicle?.label,
      startedAt: now,
      source: source,
    );
    AppLogger.info('Trip started');
    AppNotifications.showTripStarted(
      vehicleLabel: vehicle?.label,
      tripId: recordId,
    );
    _starting = false;
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
    final endLocation = LocationCache.get();
    final recordId = activeRecordId;
    await engine.stop();

    bool dropped = false;
    if (recordId != null) {
      final existing = await TripRepository.findById(recordId);
      if (existing != null) {
        final straightLineKm = _straightLineKm(
          existing.startLat,
          existing.startLng,
          endLocation?.latitude,
          endLocation?.longitude,
        );
        final thresholdM = Preferences.instance.getInt(
              Preferences.minTripDistanceMeters,
            ) ??
            Preferences.defaultMinTripDistanceMeters;
        // Two drop paths:
        //   1. Distance was measurable AND below threshold (the obvious case)
        //   2. Distance was NOT measurable (no startLat — Tracelet hadn't
        //      produced a fix yet) AND the trip was very short. This catches
        //      BT-flapping ghost trips where the user never actually moved.
        final shortNoFixDrop = thresholdM > 0 &&
            straightLineKm == null &&
            duration != null &&
            duration.inSeconds < 90;
        final shortMeasuredDrop = thresholdM > 0 &&
            straightLineKm != null &&
            straightLineKm * 1000 < thresholdM;
        if (shortMeasuredDrop || shortNoFixDrop) {
          AppLogger.info(
            'Trip dropped: '
            '${straightLineKm == null ? "no GPS fix, duration=${duration?.inSeconds}s" : "${(straightLineKm * 1000).toStringAsFixed(0)} m"} '
            '< threshold $thresholdM m',
          );
          await TripRepository.delete(recordId);
          dropped = true;
        } else {
          // Prefer the live (Haversine-summed-per-leg) distance over the
          // start→end straight-line one — handles curvy routes correctly.
          // Fall back to straight-line only if Tracelet never produced a
          // fix during the trip (live === 0 with no points).
          final liveKm = LiveTripDistance.km;
          final finalKm = liveKm > 0 ? liveKm : straightLineKm;
          await TripRepository.update(existing.copyWith(
            endedAt: DateTime.now(),
            endLat: endLocation?.latitude,
            endLng: endLocation?.longitude,
            distanceKm: finalKm,
          ));
        }
      }
    }
    final stoppedRecordId = recordId;
    activeRecordId = null;
    await Preferences.instance.setBool(_kActive, false);
    await Preferences.instance.setString(_kVehicleMac, '');
    await Preferences.instance.setString(_kSource, '');
    await Preferences.instance.setString(_kRecordId, '');
    tripState.value = TripSnapshot.idle;
    if (!dropped) {
      AppNotifications.showTripStopped(
        vehicleLabel: stoppedLabel,
        duration: duration,
        tripId: stoppedRecordId,
      );
      // Best-effort flush of GPS waypoints buffered for this trip — the
      // Web Admin's polyline depends on these. Continues even if it fails.
      if (stoppedRecordId != null) {
        PositionSender.flushTrip(stoppedRecordId).catchError((e) {
          AppLogger.warn('PositionSender flush on stop failed: $e');
          return 0;
        });
      }
      // Best-effort push to backend. Failures stay queued (synced=0) and the
      // app-start hook in main.dart will retry on next launch.
      TripSync.pushPending().catchError((e) {
        AppLogger.warn('TripSync post-stop push failed: $e');
        return const TripSyncReport(sent: 0, acknowledged: 0, rejected: 0);
      });
    }
  }

  /// Great-circle distance between two coords in km, or null if either is
  /// missing. Used both for the min-trip-distance gate and to populate
  /// `distanceKm` on the saved record (good enough for the odometer-end
  /// auto-fill in TripDetailScreen).
  static double? _straightLineKm(
    double? lat1,
    double? lng1,
    double? lat2,
    double? lng2,
  ) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return null;
    }
    const earthKm = 6371.0;
    double rad(double d) => d * math.pi / 180.0;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthKm * c;
  }
}
