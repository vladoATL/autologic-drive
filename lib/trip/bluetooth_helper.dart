/// Thin wrapper around `flutter_blue_classic` for our use cases:
/// listing bonded (paired) devices and ensuring the right runtime
/// permissions are granted.
///
/// Auto-detect of A2DP/HFP connect events is **out of scope for 0.4.0** —
/// this layer only enumerates already-paired devices so the user can attach
/// labels in `VehiclesScreen`. 0.4.1 will add a native broadcast receiver.
library;

import 'package:flutter/services.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

import '../util/app_logger.dart';

class BluetoothHelper {
  static final FlutterBlueClassic _bt = FlutterBlueClassic();
  static const _methodsChannel =
      MethodChannel('net.starlogic.autologic.drive/bt_methods');

  /// Best-effort human-readable label for THIS phone (BT adapter name,
  /// system "device name", or `Build.MODEL`). Used as the initial Traccar
  /// device name so registrations show up as "Galaxy S24 Ultra" instead
  /// of "Drive · android". Returns null if the native side is unavailable.
  static Future<String?> deviceLabel() async {
    try {
      final label = await _methodsChannel.invokeMethod<String>('deviceLabel');
      AppLogger.info('BluetoothHelper.deviceLabel() = "${label ?? "null"}"');
      return label;
    } catch (e) {
      AppLogger.warn('BluetoothHelper.deviceLabel() threw: $e');
      return null;
    }
  }

  /// Re-trigger `MonitorService` start. Useful right after the user grants
  /// `BLUETOOTH_CONNECT` in onboarding — Android 14+ refuses the foreground
  /// promotion without it, so the service that auto-started at app launch
  /// likely bailed out. Calling this again now succeeds.
  static Future<void> startMonitorService() async {
    try {
      await _methodsChannel.invokeMethod<void>('startMonitorService');
    } catch (e) {
      AppLogger.warn('BluetoothHelper.startMonitorService() threw: $e');
    }
  }

  /// Stop the always-on `MonitorService` (and its persistent notification).
  /// Foreground BT detection from Dart still works while the app is open;
  /// this just disables the killed-app guarantee.
  static Future<void> stopMonitorService() async {
    try {
      await _methodsChannel.invokeMethod<void>('stopMonitorService');
    } catch (e) {
      AppLogger.warn('BluetoothHelper.stopMonitorService() threw: $e');
    }
  }

  /// Request the runtime permissions Android needs for Bluetooth on
  /// API 31+ (`BLUETOOTH_CONNECT`). On older devices these calls are no-ops.
  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    return statuses.values.every(
      (s) => s.isGranted || s.isLimited || s.isProvisional,
    );
  }

  static Future<bool> isAdapterOn() async {
    try {
      return await _bt.isEnabled;
    } catch (_) {
      return false;
    }
  }

  static Future<List<BluetoothDevice>> bondedDevices() async {
    try {
      return (await _bt.bondedDevices) ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
