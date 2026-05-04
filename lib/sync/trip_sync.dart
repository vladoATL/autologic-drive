/// Push completed trips to AutoLogic Backend (`POST /api/v1/trips/sync`).
///
/// Drive trips live in a local SQLite log (`autologic_trips.db`); the
/// `synced` flag flips to `true` once the backend acknowledges the row.
/// Re-sync is idempotent (the server keys on our client-generated UUID),
/// so failures are safely retried on the next app start.
///
/// See `C:\Projects\autologic-backend\docs\drive-integration-status.md`
/// section 3 for the wire contract and acceptance criteria.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/backend_api.dart';
import '../preferences.dart';
import '../trip/trip_record.dart';
import '../trip/trip_repository.dart';
import '../util/app_logger.dart';

/// Outcome of one batched sync round-trip.
class TripSyncReport {
  final int sent;
  final int acknowledged;
  final int rejected;
  final String? error;
  const TripSyncReport({
    required this.sent,
    required this.acknowledged,
    required this.rejected,
    this.error,
  });
  bool get ok => error == null;
}

class TripSync {
  static const _maxBatchSize = 200;

  /// Push every completed-but-unsynced trip in the local log to the backend.
  /// Marks acknowledged trips as `synced=true`. No-op when there is nothing
  /// to send, when the user is not paired, or when sync is disabled in
  /// preferences.
  static Future<TripSyncReport> pushPending() async {
    final enabled =
        Preferences.instance.getBool(Preferences.backendSyncEnabled) ?? true;
    if (!enabled) {
      return const TripSyncReport(sent: 0, acknowledged: 0, rejected: 0);
    }
    if (!BackendApi.isPaired) {
      return const TripSyncReport(sent: 0, acknowledged: 0, rejected: 0);
    }

    final all = await TripRepository.list();
    final pending = all
        .where((t) => !t.synced && t.endedAt != null)
        .take(_maxBatchSize)
        .toList();
    if (pending.isEmpty) {
      return const TripSyncReport(sent: 0, acknowledged: 0, rejected: 0);
    }

    if (BackendApi.isSessionDead) {
      return const TripSyncReport(sent: 0, acknowledged: 0, rejected: 0);
    }

    final url = Uri.parse(
      '${Preferences.instance.getString(Preferences.backendApiUrl) ?? ''}/api/v1/trips/sync',
    );
    final body = jsonEncode({
      'trips': pending.map(_toDto).toList(),
    });
    var accessToken = await BackendApi.getValidAccessToken();
    if (accessToken == null) {
      return const TripSyncReport(sent: 0, acknowledged: 0, rejected: 0);
    }

    Future<http.Response> doPost(String t) => http.post(
          url,
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer $t',
          },
          body: body,
        );

    http.Response resp;
    try {
      resp = await doPost(accessToken);
      if (resp.statusCode == 401) {
        final fresh = await BackendApi.refreshAfterUnauthorized();
        if (fresh == null) {
          return TripSyncReport(
            sent: pending.length,
            acknowledged: 0,
            rejected: 0,
            error: 'session_dead',
          );
        }
        accessToken = fresh;
        resp = await doPost(accessToken);
      }
    } catch (e) {
      AppLogger.warn('TripSync push failed (network): $e');
      return TripSyncReport(
        sent: pending.length,
        acknowledged: 0,
        rejected: 0,
        error: e.toString(),
      );
    }

    if (resp.statusCode == 401) {
      AppLogger.warn('TripSync: 401 even after refresh — session dead');
      return TripSyncReport(
        sent: pending.length,
        acknowledged: 0,
        rejected: 0,
        error: 'unauthorized',
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      AppLogger.warn(
        'TripSync push HTTP ${resp.statusCode}: ${resp.body}',
      );
      return TripSyncReport(
        sent: pending.length,
        acknowledged: 0,
        rejected: 0,
        error: 'http_${resp.statusCode}',
      );
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final acked =
        (decoded['acknowledged'] as List? ?? const []).cast<dynamic>();
    final rejected =
        (decoded['rejected'] as List? ?? const []).cast<dynamic>();

    final ackedIds = <String>{
      for (final a in acked) (a as Map<String, dynamic>)['id'] as String,
    };

    var ackCount = 0;
    for (final t in pending) {
      if (ackedIds.contains(t.id)) {
        await TripRepository.update(t.copyWith(synced: true));
        ackCount++;
      }
    }
    if (rejected.isNotEmpty) {
      AppLogger.warn(
        'TripSync rejected ${rejected.length} trips: '
        '${rejected.map((r) => "${(r as Map)['id']}=${r['reason']}").join(', ')}',
      );
    }
    AppLogger.info(
      'TripSync push: sent=${pending.length}, acked=$ackCount, rejected=${rejected.length}',
    );
    return TripSyncReport(
      sent: pending.length,
      acknowledged: ackCount,
      rejected: rejected.length,
    );
  }

  /// Push a single trip immediately. Convenience wrapper for the
  /// post-stop hook in `TripController`. On failure the trip stays
  /// `synced=false` and gets retried by [pushPending] on next app start.
  static Future<bool> pushOne(TripRecord trip) async {
    if (trip.synced || trip.endedAt == null) return false;
    final enabled =
        Preferences.instance.getBool(Preferences.backendSyncEnabled) ?? true;
    if (!enabled || !BackendApi.isPaired) return false;
    final report = await pushPending();
    return report.acknowledged > 0;
  }

  static Map<String, dynamic> _toDto(TripRecord t) => {
        'id': t.id,
        'startedAt': t.startedAt.toUtc().toIso8601String(),
        'endedAt': t.endedAt?.toUtc().toIso8601String(),
        'vehicleMac': t.vehicleMac,
        'vehicleLabel': t.vehicleLabel,
        'driverName': t.driverName,
        'purpose': t.purpose,
        'kind': t.kind.name,
        'odometerStart': t.odometerStart,
        'odometerEnd': t.odometerEnd,
        'source': t.source.name,
        'startLat': t.startLat,
        'startLng': t.startLng,
        'endLat': t.endLat,
        'endLng': t.endLng,
        'startAddress': t.startAddress,
        'endAddress': t.endAddress,
        'distanceKm': t.distanceKm,
      };
}
