/// Reverse-geocodes trip start/end coordinates into human-readable addresses
/// (street + city) and persists them onto the trip record. Cached values in
/// `start_address` / `end_address` mean we only hit the platform Geocoder
/// once per trip — repeat opens of the detail screen are instant and the CSV
/// export works offline once a trip has been viewed online.
library;

import 'package:geocoding/geocoding.dart';

import '../trip/trip_record.dart';
import '../trip/trip_repository.dart';
import 'app_logger.dart';

class AddressResolver {
  /// Format a placemark as `"<street> <number>, <locality>"` with sensible
  /// fallbacks. Returns null if there's nothing usable.
  static String? _format(Placemark p) {
    final streetParts = <String>[
      if ((p.thoroughfare ?? '').isNotEmpty) p.thoroughfare!,
      if ((p.subThoroughfare ?? '').isNotEmpty) p.subThoroughfare!,
    ];
    final street = streetParts.join(' ').trim();
    final city = (p.locality?.isNotEmpty ?? false)
        ? p.locality!
        : (p.subAdministrativeArea?.isNotEmpty ?? false)
            ? p.subAdministrativeArea!
            : (p.administrativeArea ?? '');

    if (street.isEmpty && city.isEmpty) return null;
    if (street.isEmpty) return city;
    if (city.isEmpty) return street;
    return '$street, $city';
  }

  /// Resolve a single coordinate. Returns null on any error or empty result.
  static Future<String?> resolve(double lat, double lng) async {
    try {
      await setLocaleIdentifier('sk_SK');
      final marks = await placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      return _format(marks.first);
    } catch (e) {
      AppLogger.warn('AddressResolver: failed for $lat,$lng — $e');
      return null;
    }
  }

  /// Resolve any missing addresses on the trip and persist the update.
  /// Returns the (possibly updated) record. Cheap no-op if both addresses
  /// are already cached or coords are missing.
  static Future<TripRecord> resolveAndPersist(TripRecord t) async {
    final needStart =
        t.startAddress == null && t.startLat != null && t.startLng != null;
    final needEnd = t.endAddress == null && t.endLat != null && t.endLng != null;
    if (!needStart && !needEnd) return t;

    final results = await Future.wait<String?>([
      needStart ? resolve(t.startLat!, t.startLng!) : Future.value(null),
      needEnd ? resolve(t.endLat!, t.endLng!) : Future.value(null),
    ]);

    final updated = t.copyWith(
      startAddress: needStart ? results[0] : t.startAddress,
      endAddress: needEnd ? results[1] : t.endAddress,
    );

    if (updated.startAddress != t.startAddress ||
        updated.endAddress != t.endAddress) {
      await TripRepository.update(updated);
      AppLogger.info(
        'AddressResolver: cached addresses for trip ${t.id}',
      );
    }
    return updated;
  }
}
