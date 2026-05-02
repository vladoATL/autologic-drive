/// Thin wrapper around `flutter_blue_classic` for our use cases:
/// listing bonded (paired) devices and ensuring the right runtime
/// permissions are granted.
///
/// Auto-detect of A2DP/HFP connect events is **out of scope for 0.4.0** —
/// this layer only enumerates already-paired devices so the user can attach
/// labels in `VehiclesScreen`. 0.4.1 will add a native broadcast receiver.
library;

import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothHelper {
  static final FlutterBlueClassic _bt = FlutterBlueClassic();

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
