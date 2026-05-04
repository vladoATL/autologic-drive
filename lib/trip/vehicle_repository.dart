/// JSON-list-in-SharedPreferences CRUD for `Vehicle`.
library;

import '../auth/traccar_api.dart';
import '../preferences.dart';
import 'vehicle.dart';

class VehicleRepository {
  static const _prefsKey = 'vehicles';

  static List<Vehicle> all() {
    final raw = Preferences.instance.getString(_prefsKey);
    return Vehicle.decodeList(raw);
  }

  static Vehicle? findByMac(String mac) {
    for (final v in all()) {
      if (v.bluetoothMac == mac) return v;
    }
    return null;
  }

  static Future<void> upsert(Vehicle vehicle) async {
    final list = all().toList();
    final idx = list.indexWhere((v) => v.bluetoothMac == vehicle.bluetoothMac);
    if (idx >= 0) {
      list[idx] = vehicle;
    } else {
      list.add(vehicle);
    }
    await Preferences.instance.setString(_prefsKey, Vehicle.encodeList(list));
    await _syncTraccarDeviceName();
  }

  /// Promote one paired BT device to be the single auto-start trigger.
  /// Every other vehicle has `autoStartTrip` cleared so we don't get
  /// trip-flapping from a SmartBox/OBD reader competing with the head-unit.
  /// Pass an empty string to clear all auto-start flags.
  static Future<void> setPrimaryAutoStart(String mac) async {
    final list = all().toList();
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      final v = list[i];
      final shouldBeOn = v.bluetoothMac == mac;
      if (v.autoStartTrip != shouldBeOn) {
        list[i] = v.copyWith(autoStartTrip: shouldBeOn);
        changed = true;
      }
    }
    if (!changed) return;
    await Preferences.instance.setString(_prefsKey, Vehicle.encodeList(list));
    await _syncTraccarDeviceName();
  }

  static Future<void> remove(String mac) async {
    final list = all().where((v) => v.bluetoothMac != mac).toList();
    await Preferences.instance.setString(_prefsKey, Vehicle.encodeList(list));
    await _syncTraccarDeviceName();
  }

  /// Push the current "primary" vehicle label to Traccar so the fleet manager
  /// sees something useful in the Devices list (e.g. "Škoda Octavia BA123AB"
  /// instead of "Drive · android"). The primary vehicle is the first one
  /// flagged `autoStartTrip` (typically the headunit). When no trip-eligible
  /// vehicle is paired, the device name is left alone.
  static Future<void> _syncTraccarDeviceName() async {
    final uniqueId = Preferences.instance.getString(Preferences.id);
    if (uniqueId == null || uniqueId.isEmpty) return;
    final primary = all().where((v) => v.autoStartTrip).firstOrNull;
    if (primary == null) return;
    await TraccarApi.renameDevice(
      uniqueId: uniqueId,
      newName: primary.label,
    );
  }

  /// Pull the device name from Traccar and copy it onto the primary vehicle's
  /// label if they diverged — covers the case where the fleet admin renamed
  /// the device in the Traccar web UI. Server is the source of truth.
  ///
  /// Called on app resume / login. No-op when not logged in, when the device
  /// isn't registered yet, or when there's no primary vehicle to update.
  static Future<void> pullDeviceNameFromServer() async {
    final uniqueId = Preferences.instance.getString(Preferences.id);
    if (uniqueId == null || uniqueId.isEmpty) return;
    final serverName = await TraccarApi.fetchDeviceName(uniqueId);
    if (serverName == null || serverName.isEmpty) return;
    final list = all().toList();
    final idx = list.indexWhere((v) => v.autoStartTrip);
    if (idx < 0) return;
    final primary = list[idx];
    if (primary.label == serverName) return;
    list[idx] = primary.copyWith(label: serverName);
    await Preferences.instance.setString(_prefsKey, Vehicle.encodeList(list));
    // Don't call _syncTraccarDeviceName here — that would cause a rename
    // ping-pong if the user is mid-edit on both sides.
  }
}
