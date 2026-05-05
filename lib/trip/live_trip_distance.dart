/// Live accumulator for the currently-active trip's driven distance.
/// Updates on every Tracelet location dispatch by adding the Haversine
/// distance between the previous and current point.
///
/// Exposed as a [ValueNotifier<double>] (kilometres) so the inline trip
/// editor on `MainScreen` can update the suggested `Tacho po` field in
/// real time as the driver moves — they only have to verify the number
/// at the end of the trip rather than typing it.
///
/// Replaces the previous start→end straight-line distance that
/// `TripController.stop` computed once, which under-counted curvy routes.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

class LiveTripDistance {
  /// Accumulated kilometres for the active trip. Reset to 0 on
  /// [resetForTripStart] and updated incrementally by [addPoint].
  static final ValueNotifier<double> kmNotifier = ValueNotifier<double>(0.0);

  static double? _lastLat;
  static double? _lastLng;

  static double get km => kmNotifier.value;

  /// Called from [TripController.start]. Drops the previous trip's last
  /// point so the very first location of the new trip is treated as the
  /// origin rather than chained onto the previous trip's end.
  static void resetForTripStart() {
    kmNotifier.value = 0.0;
    _lastLat = null;
    _lastLng = null;
  }

  /// Add a new GPS waypoint. Computes the Haversine delta from the
  /// previous point (if any) and adds it to [km]. Skips obviously bogus
  /// jumps (>10 km between points → likely GPS lock loss) so a brief
  /// fix-loss with massive accuracy doesn't inflate the running total.
  static void addPoint(double lat, double lng) {
    final prevLat = _lastLat;
    final prevLng = _lastLng;
    _lastLat = lat;
    _lastLng = lng;
    if (prevLat == null || prevLng == null) return;
    final delta = _haversineKm(prevLat, prevLng, lat, lng);
    if (delta > 10.0) return;
    kmNotifier.value = kmNotifier.value + delta;
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
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
