/// Trip state — what's currently being recorded, if anything.
///
/// Wraps a `ChangeNotifier` so the UI can rebuild on changes. `TripController`
/// is the only writer; the rest of the app reads.
library;

import 'package:flutter/foundation.dart';

enum TripTriggerSource { manual, bluetooth }

class TripSnapshot {
  final bool active;
  final String? vehicleMac;
  final String? vehicleLabel;
  final DateTime? startedAt;
  final TripTriggerSource? source;

  const TripSnapshot({
    required this.active,
    this.vehicleMac,
    this.vehicleLabel,
    this.startedAt,
    this.source,
  });

  static const idle = TripSnapshot(active: false);
}

class TripState extends ValueNotifier<TripSnapshot> {
  TripState() : super(TripSnapshot.idle);
}

final TripState tripState = TripState();
