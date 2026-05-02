/// HTTP layer that ships positions to a Traccar OsmAnd-protocol endpoint.
///
/// The server (`/?id=…&lat=…&lon=…&timestamp=…`) on port 5055 expects
/// query-string parameters, not JSON. Tracelet's built-in HttpConfig posts
/// JSON, so we bypass it: `geolocation_service.onLocation` calls
/// `OsmAndSender.send` directly.
///
/// Failed sends are queued in `SharedPreferences` (FIFO, max 200 entries) and
/// retried on the next successful send.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../util/app_logger.dart';
import 'tracking_engine.dart';

class OsmAndSender {
  static const _queueKey = 'osmand_outbox';
  static const _maxQueueSize = 200;
  static const _httpTimeout = Duration(seconds: 30);

  static Future<bool> send({
    required String url,
    required String deviceId,
    required TrackedLocation loc,
  }) async {
    final ok = await _send(url, deviceId, loc);
    if (ok) {
      await _flushQueue();
    } else {
      await _enqueue(url, deviceId, loc);
    }
    return ok;
  }

  static Future<bool> _send(String url, String deviceId, TrackedLocation loc) async {
    try {
      final uri = _buildUri(url, deviceId, loc);
      // Traccar's OsmAnd protocol decoder expects an HTTP GET with query
      // parameters; POSTing with empty body returns HTTP 400.
      final resp = await http.get(uri).timeout(_httpTimeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        AppLogger.info(
          'Sent ${loc.latitude.toStringAsFixed(5)},${loc.longitude.toStringAsFixed(5)} '
          '(±${loc.accuracy.toStringAsFixed(0)}m, ${(loc.speed * 3.6).toStringAsFixed(0)} km/h) → HTTP ${resp.statusCode}',
        );
        return true;
      }
      AppLogger.warn('Send rejected: HTTP ${resp.statusCode}: ${resp.body}');
      return false;
    } catch (error) {
      AppLogger.error('Send failed: $error');
      return false;
    }
  }

  static Uri _buildUri(String url, String deviceId, TrackedLocation loc) {
    final base = Uri.parse(url);
    final params = <String, String>{
      'id': deviceId,
      'lat': loc.latitude.toString(),
      'lon': loc.longitude.toString(),
      'timestamp': (DateTime.parse(loc.timestamp).millisecondsSinceEpoch ~/ 1000).toString(),
      'speed': loc.speed.toString(),
      'bearing': loc.heading.toString(),
      'altitude': loc.altitude.toString(),
      'accuracy': loc.accuracy.toString(),
      if (loc.batteryLevel != null && loc.batteryLevel! >= 0)
        'batt': (loc.batteryLevel! * 100).toStringAsFixed(0),
      if (loc.batteryCharging == true) 'charge': 'true',
    };
    return base.replace(queryParameters: {...base.queryParameters, ...params});
  }

  static Future<void> _enqueue(String url, String deviceId, TrackedLocation loc) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? <String>[];
    queue.add(jsonEncode({
      'url': url,
      'deviceId': deviceId,
      'uri': _buildUri(url, deviceId, loc).toString(),
    }));
    while (queue.length > _maxQueueSize) {
      queue.removeAt(0);
    }
    await prefs.setStringList(_queueKey, queue);
    AppLogger.warn('Queued offline (pending=${queue.length})');
  }

  static Future<void> _flushQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? <String>[];
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (final entry in queue) {
      try {
        final decoded = jsonDecode(entry) as Map<String, dynamic>;
        final uri = Uri.parse(decoded['uri'] as String);
        final resp = await http.get(uri).timeout(_httpTimeout);
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          remaining.add(entry);
        }
      } catch (error) {
        AppLogger.error('Queue flush entry failed: $error');
        remaining.add(entry);
      }
    }
    await prefs.setStringList(_queueKey, remaining);
    final flushed = queue.length - remaining.length;
    if (flushed > 0) {
      AppLogger.info('Flushed $flushed queued (pending=${remaining.length})');
    }
  }
}
