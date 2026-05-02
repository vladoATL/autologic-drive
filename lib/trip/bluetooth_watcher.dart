/// Listens to Bluetooth A2DP / Headset connection events and auto-starts /
/// auto-stops trips for paired vehicles flagged `autoStartTrip`.
///
/// Two complementary mechanisms feed this watcher:
///
/// 1. **Broadcast events** from a `BroadcastReceiver` registered in
///    `MainActivity.kt`, delivered via the `bt_connections` `EventChannel`.
/// 2. **Foreground polls** via the `bt_methods` `MethodChannel.connectedDevices`,
///    invoked when the app starts or comes back to foreground (some Android
///    OEMs/versions occasionally drop the broadcast — the poll backstops it).
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../preferences.dart';
import '../util/app_logger.dart';
import 'trip_controller.dart';
import 'trip_state.dart';
import 'vehicle.dart';
import 'vehicle_repository.dart';

class BluetoothWatcher {
  static const _eventsChannel =
      EventChannel('net.starlogic.autologic.drive/bt_connections');
  static const _methodsChannel =
      MethodChannel('net.starlogic.autologic.drive/bt_methods');

  static StreamSubscription<dynamic>? _sub;
  static Timer? _disconnectGraceTimer;
  // Real-world car BT (A2DP + headset) tends to drop both profiles within a
  // few seconds of motor-off; a longer grace just delays the "trip stopped"
  // banner without rescuing real disconnect bounces. 15 s is enough to
  // tolerate a one-second profile flap while still feeling responsive.
  static const _disconnectGrace = Duration(seconds: 15);

  static void start() {
    _sub ??= _eventsChannel.receiveBroadcastStream().listen(_onEvent);
    // Best-effort fallback — covers cases where the broadcast was missed
    // (app launched after the BT connection was already established).
    pollNow();
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Ask the platform layer for the current set of connected paired devices
  /// and treat each one as a synthetic "connected" event. Safe to call any
  /// number of times.
  static Future<void> pollNow() async {
    try {
      final raw = await _methodsChannel.invokeMethod<List<dynamic>>('connectedDevices');
      final addresses = (raw ?? const []).cast<String>();
      // Only mention auto-trip-eligible devices in the summary so the log
      // doesn't fill up with smartBox / headphones / random pairings.
      final relevant = addresses
          .where((a) => VehicleRepository.findByMac(a)?.autoStartTrip == true)
          .toList();
      if (relevant.isNotEmpty) {
        AppLogger.info('BT poll: ${relevant.length} relevant connected — $relevant');
      }
      for (final address in addresses) {
        await _handle(address: address, state: 'connected');
      }
    } catch (error) {
      AppLogger.error('BT poll failed: $error');
    }
  }

  static Future<void> _onEvent(dynamic raw) async {
    if (raw is! Map) return;
    final address = raw['address'] as String?;
    final state = raw['state'] as String?;
    final profile = raw['profile'] as String?;
    if (address == null || state == null) return;
    final vehicle = VehicleRepository.findByMac(address);
    // Suppress log noise for devices that aren't trip-eligible — unpaired
    // BT (random headphones), or paired-but-autoStart-off (smartBox-style
    // accessories). Trip dispatch logic in `_handle` runs unconditionally.
    if (vehicle != null && vehicle.autoStartTrip) {
      AppLogger.info('BT event: ${vehicle.label} [$address] $state profile=$profile');
    }
    await _handle(address: address, state: state);
  }

  static Future<void> _handle({
    required String address,
    required String state,
  }) async {
    final vehicle = VehicleRepository.findByMac(address);
    if (vehicle == null) return;

    final autoDetect =
        Preferences.instance.getBool(Preferences.autoDetect) ?? false;

    if (state == 'connected') {
      // Auto-start respects both the global toggle and per-vehicle flag.
      if (!autoDetect || !vehicle.autoStartTrip) return;
      await _onConnect(vehicle);
    } else if (state == 'disconnected') {
      // Auto-stop fires for trips we auto-started, regardless of the toggle.
      // Otherwise turning auto-detect off mid-trip would strand the engine
      // running for the rest of the day.
      await _onDisconnect(vehicle);
    }
  }

  static Future<void> _onConnect(Vehicle vehicle) async {
    // A reconnect inside the grace window cancels the pending stop —
    // the car is still here, just bouncing.
    if (_disconnectGraceTimer?.isActive ?? false) {
      _disconnectGraceTimer?.cancel();
      _disconnectGraceTimer = null;
      AppLogger.info('BT reconnect within grace: ${vehicle.label} — keeping trip');
      return;
    }
    if (tripState.value.active) {
      AppLogger.info('BT connect: ${vehicle.label} — trip already active, skip auto-start');
      return;
    }
    AppLogger.info('BT auto-start: ${vehicle.label}');
    await TripController.start(
      vehicle: vehicle,
      source: TripTriggerSource.bluetooth,
    );
  }

  static Future<void> _onDisconnect(Vehicle vehicle) async {
    final current = tripState.value;
    if (!current.active) return;
    if (current.source != TripTriggerSource.bluetooth) {
      AppLogger.info('BT disconnect: ${vehicle.label} — trip is manual, leave running');
      return;
    }
    // Don't stop immediately. Cars often have multiple BT devices (headunit
    // + OBD adapter + handsfree dock) that disconnect a few seconds apart.
    // Wait, then re-poll — only stop if no known vehicle is still connected.
    AppLogger.info(
      'BT disconnect: ${vehicle.label} — waiting ${_disconnectGrace.inSeconds}s '
      'before stopping trip',
    );
    _disconnectGraceTimer?.cancel();
    _disconnectGraceTimer = Timer(_disconnectGrace, () async {
      _disconnectGraceTimer = null;
      try {
        final raw = await _methodsChannel
            .invokeMethod<List<dynamic>>('connectedDevices');
        final addresses = (raw ?? const []).cast<String>().toSet();
        final stillConnectedKnown = addresses
            .map(VehicleRepository.findByMac)
            .whereType<Vehicle>()
            .toList();
        if (stillConnectedKnown.isNotEmpty) {
          AppLogger.info(
            'Grace expired but still connected: '
            '${stillConnectedKnown.map((v) => v.label).join(", ")} — keep trip',
          );
          return;
        }
      } catch (error) {
        AppLogger.warn('Grace re-poll failed, stopping anyway: $error');
      }
      if (!tripState.value.active) return;
      if (tripState.value.source != TripTriggerSource.bluetooth) return;
      AppLogger.info('BT auto-stop after grace: ${vehicle.label}');
      await TripController.stop();
    });
  }
}
