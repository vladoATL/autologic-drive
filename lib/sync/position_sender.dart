/// In-memory buffer + sender for GPS waypoints to AutoLogic Backend
/// (`POST /api/v1/positions`, added in `ab` v0.11.0).
///
/// Drive's primary GPS sink remains Traccar (OsmAndSender) — this is a
/// parallel sink that lets the Web Admin draw the real driven polyline on
/// the trip detail map. Positions are buffered per active tripId and
/// pushed in batches every [_flushInterval] or on demand (e.g. when the
/// trip stops).
///
/// **Lossy by design:** the buffer is NOT persisted to SQLite. If the app
/// crashes mid-trip the in-flight waypoints since the last flush are lost
/// — Traccar still has them via the OsmAnd sink. Persistent storage may
/// land in 0.13.x if real-world usage proves loss is meaningful.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../auth/backend_api.dart';
import '../preferences.dart';
import '../tracking/tracking_engine.dart';
import '../util/app_logger.dart';

class _PositionEntry {
  final String id;
  final DateTime timestamp;
  final double lat;
  final double lng;
  final double? speedKmh;
  final double? accuracyM;
  const _PositionEntry({
    required this.id,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.speedKmh,
    required this.accuracyM,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'lat': lat,
        'lng': lng,
        if (speedKmh != null) 'speedKmh': speedKmh,
        if (accuracyM != null) 'accuracyM': accuracyM,
      };
}

class PositionSender {
  static const _uuid = Uuid();
  static const _flushInterval = Duration(seconds: 30);
  static const _httpTimeout = Duration(seconds: 20);
  static const _maxBatchSize = 500;

  static final Map<String, List<_PositionEntry>> _buffers = {};
  static Timer? _timer;
  static bool _flushInFlight = false;

  /// Start the periodic flush timer. Idempotent — repeated calls reuse the
  /// existing timer.
  static void start() {
    _timer ??= Timer.periodic(_flushInterval, (_) => flushAll());
  }

  /// Stop the periodic flush. Pending buffers are kept; call [flushAll]
  /// before stopping if you want them sent.
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Enqueue one waypoint for [tripId]. No-op when [tripId] is empty.
  static void enqueue(String tripId, TrackedLocation loc) {
    if (tripId.isEmpty) return;
    final ts = DateTime.tryParse(loc.timestamp);
    if (ts == null) return;
    final list = _buffers.putIfAbsent(tripId, () => <_PositionEntry>[]);
    list.add(_PositionEntry(
      id: _uuid.v4(),
      timestamp: ts,
      lat: loc.latitude,
      lng: loc.longitude,
      speedKmh: loc.speed * 3.6,
      accuracyM: loc.accuracy >= 0 ? loc.accuracy : null,
    ));
  }

  /// Flush every buffered tripId in sequence. Returns the number of
  /// positions successfully POSTed across all trips.
  static Future<int> flushAll() async {
    if (_flushInFlight) return 0;
    _flushInFlight = true;
    try {
      var total = 0;
      for (final tripId in _buffers.keys.toList()) {
        total += await _flush(tripId);
      }
      return total;
    } finally {
      _flushInFlight = false;
    }
  }

  /// Flush the buffer for one trip immediately (e.g. when the trip stops).
  static Future<int> flushTrip(String tripId) async {
    return _flush(tripId);
  }

  static Future<int> _flush(String tripId) async {
    final buf = _buffers[tripId];
    if (buf == null || buf.isEmpty) return 0;
    if (!BackendApi.isPaired) return 0;

    final base = Preferences.instance.getString(Preferences.backendApiUrl);
    final token = Preferences.instance.getString(Preferences.backendAccessToken);
    if (base == null || base.isEmpty || token == null || token.isEmpty) {
      return 0;
    }

    // Snapshot the batch we're sending so concurrent enqueues during the
    // POST don't get accidentally dropped on success.
    final batch = buf.length <= _maxBatchSize ? buf.toList() : buf.sublist(0, _maxBatchSize);
    final body = jsonEncode({
      'tripId': tripId,
      'positions': batch.map((e) => e.toJson()).toList(),
    });

    try {
      final resp = await http
          .post(
            Uri.parse('$base/api/v1/positions'),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            body: body,
          )
          .timeout(_httpTimeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // Remove the snapshot from the head of the buffer; anything that
        // arrived during the POST stays for the next flush.
        buf.removeRange(0, batch.length);
        if (buf.isEmpty) _buffers.remove(tripId);
        AppLogger.info(
          'Positions: pushed ${batch.length} → trip $tripId (HTTP ${resp.statusCode})',
        );
        return batch.length;
      }
      AppLogger.warn(
        'Positions: rejected ${batch.length} → trip $tripId (HTTP ${resp.statusCode}: ${resp.body})',
      );
      return 0;
    } catch (error) {
      AppLogger.error('Positions: flush failed for $tripId: $error');
      return 0;
    }
  }
}
