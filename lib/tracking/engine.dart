/// Global tracking engine singleton.
///
/// 0.3.0 default: `TraceletEngine` (Apache 2.0). Tracelet provides the GPS
/// lifecycle, `OsmAndSender` (in `osmand_sender.dart`) ships positions to
/// Traccar's OsmAnd protocol on port 5055.
///
/// To roll back to the commercial `flutter_background_geolocation` engine
/// (e.g. if Tracelet misbehaves on a specific OEM): `git revert` the 0.3.0
/// commit, or restore `lib/tracking/fbg_engine.dart` from `git show
/// v0.2.0:lib/tracking/fbg_engine.dart` and flip the constant below.
library;

import 'tracelet_engine.dart';
import 'tracking_engine.dart';

const TrackingEngine engine = TraceletEngine();
