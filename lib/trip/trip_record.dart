/// One row of the local trip log (kniha jázd).
///
/// Created on `TripController.start`, updated on `.stop`, edited via
/// `TripDetailScreen`, exported to CSV / synced to backend later.
library;

import 'trip_state.dart' show TripTriggerSource;

enum TripKind { business, private }

class TripRecord {
  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;

  final String? vehicleMac;
  final String? vehicleLabel;
  final String? driverName;
  final String purpose;
  final TripKind kind;

  final int? odometerStart;
  final int? odometerEnd;
  final String? odometerStartPhotoPath;
  final String? odometerEndPhotoPath;

  final TripTriggerSource source;

  final double? startLat, startLng, endLat, endLng;
  final double? distanceKm;

  final bool synced;

  const TripRecord({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.vehicleMac,
    this.vehicleLabel,
    this.driverName,
    this.purpose = '',
    this.kind = TripKind.business,
    this.odometerStart,
    this.odometerEnd,
    this.odometerStartPhotoPath,
    this.odometerEndPhotoPath,
    required this.source,
    this.startLat,
    this.startLng,
    this.endLat,
    this.endLng,
    this.distanceKm,
    this.synced = false,
  });

  bool get isActive => endedAt == null;

  /// Whether the trip has all the legally-required fields filled in.
  bool get isComplete =>
      endedAt != null &&
      driverName != null &&
      driverName!.trim().isNotEmpty &&
      purpose.trim().isNotEmpty &&
      odometerStart != null &&
      odometerEnd != null;

  TripRecord copyWith({
    DateTime? endedAt,
    String? vehicleMac,
    String? vehicleLabel,
    String? driverName,
    String? purpose,
    TripKind? kind,
    int? odometerStart,
    int? odometerEnd,
    String? odometerStartPhotoPath,
    String? odometerEndPhotoPath,
    double? startLat,
    double? startLng,
    double? endLat,
    double? endLng,
    double? distanceKm,
    bool? synced,
  }) {
    return TripRecord(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      vehicleMac: vehicleMac ?? this.vehicleMac,
      vehicleLabel: vehicleLabel ?? this.vehicleLabel,
      driverName: driverName ?? this.driverName,
      purpose: purpose ?? this.purpose,
      kind: kind ?? this.kind,
      odometerStart: odometerStart ?? this.odometerStart,
      odometerEnd: odometerEnd ?? this.odometerEnd,
      odometerStartPhotoPath:
          odometerStartPhotoPath ?? this.odometerStartPhotoPath,
      odometerEndPhotoPath:
          odometerEndPhotoPath ?? this.odometerEndPhotoPath,
      source: source,
      startLat: startLat ?? this.startLat,
      startLng: startLng ?? this.startLng,
      endLat: endLat ?? this.endLat,
      endLng: endLng ?? this.endLng,
      distanceKm: distanceKm ?? this.distanceKm,
      synced: synced ?? this.synced,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'started_at': startedAt.millisecondsSinceEpoch,
        'ended_at': endedAt?.millisecondsSinceEpoch,
        'vehicle_mac': vehicleMac,
        'vehicle_label': vehicleLabel,
        'driver_name': driverName,
        'purpose': purpose,
        'kind': kind.name,
        'odometer_start': odometerStart,
        'odometer_end': odometerEnd,
        'odo_start_photo': odometerStartPhotoPath,
        'odo_end_photo': odometerEndPhotoPath,
        'source': source.name,
        'start_lat': startLat,
        'start_lng': startLng,
        'end_lat': endLat,
        'end_lng': endLng,
        'distance_km': distanceKm,
        'synced': synced ? 1 : 0,
      };

  factory TripRecord.fromMap(Map<String, Object?> m) => TripRecord(
        id: m['id'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        endedAt: m['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['ended_at'] as int),
        vehicleMac: m['vehicle_mac'] as String?,
        vehicleLabel: m['vehicle_label'] as String?,
        driverName: m['driver_name'] as String?,
        purpose: (m['purpose'] as String?) ?? '',
        kind: TripKind.values.firstWhere(
          (e) => e.name == m['kind'],
          orElse: () => TripKind.business,
        ),
        odometerStart: m['odometer_start'] as int?,
        odometerEnd: m['odometer_end'] as int?,
        odometerStartPhotoPath: m['odo_start_photo'] as String?,
        odometerEndPhotoPath: m['odo_end_photo'] as String?,
        source: TripTriggerSource.values.firstWhere(
          (e) => e.name == m['source'],
          orElse: () => TripTriggerSource.manual,
        ),
        startLat: m['start_lat'] as double?,
        startLng: m['start_lng'] as double?,
        endLat: m['end_lat'] as double?,
        endLng: m['end_lng'] as double?,
        distanceKm: m['distance_km'] as double?,
        synced: (m['synced'] as int? ?? 0) == 1,
      );
}
