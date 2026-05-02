/// JSON-list-in-SharedPreferences CRUD for `Vehicle`.
library;

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
  }

  static Future<void> remove(String mac) async {
    final list = all().where((v) => v.bluetoothMac != mac).toList();
    await Preferences.instance.setString(_prefsKey, Vehicle.encodeList(list));
  }
}
