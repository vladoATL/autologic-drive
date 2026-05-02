/// Global tracking engine singleton.
///
/// To swap engines (e.g. once `TraceletEngine` lands in 0.3.0):
///
/// ```dart
/// final TrackingEngine engine = TraceletEngine();
/// ```
///
/// All call sites (preferences/main_screen/settings_screen/quick_actions/
/// geolocation_service/status_screen/configuration_service/location_cache)
/// import this single symbol — no other change needed.
library;

import 'fbg_engine.dart';
import 'tracking_engine.dart';

const TrackingEngine engine = FbgEngine();
