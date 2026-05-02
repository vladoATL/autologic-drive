/// A paired Bluetooth device that the driver has labelled as a vehicle.
///
/// `bluetoothMac` is the device address (e.g. `00:11:22:33:44:55`).
/// `label` is a free-text vehicle name (e.g. "Škoda Octavia BA123AB").
/// `autoStartTrip` toggles whether trips auto-start when this device connects
/// (currently informational; auto-trigger is wired in 0.4.1).
library;

import 'dart:convert';

class Vehicle {
  final String bluetoothMac;
  final String? bluetoothName;
  final String label;
  final bool autoStartTrip;

  const Vehicle({
    required this.bluetoothMac,
    this.bluetoothName,
    required this.label,
    this.autoStartTrip = true,
  });

  Vehicle copyWith({String? label, bool? autoStartTrip, String? bluetoothName}) {
    return Vehicle(
      bluetoothMac: bluetoothMac,
      bluetoothName: bluetoothName ?? this.bluetoothName,
      label: label ?? this.label,
      autoStartTrip: autoStartTrip ?? this.autoStartTrip,
    );
  }

  Map<String, dynamic> toJson() => {
        'mac': bluetoothMac,
        'name': bluetoothName,
        'label': label,
        'autoStart': autoStartTrip,
      };

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        bluetoothMac: j['mac'] as String,
        bluetoothName: j['name'] as String?,
        label: j['label'] as String? ?? '',
        autoStartTrip: j['autoStart'] as bool? ?? true,
      );

  static String encodeList(List<Vehicle> list) =>
      jsonEncode(list.map((v) => v.toJson()).toList());

  static List<Vehicle> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => Vehicle.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }
}
