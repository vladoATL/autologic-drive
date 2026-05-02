/// Generate a CSV from a list of trip records and hand it to the OS share
/// sheet. Format follows what Slovak / Czech accountants expect for kniha
/// jázd: semicolon-separated, UTF-8 with BOM (Excel sniffs the BOM and
/// reads diacritics correctly).
library;

import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../trip/trip_record.dart';

class TripCsvExporter {
  static const _utf8Bom = '﻿';

  static String _escape(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final v = raw.replaceAll('"', '""');
    if (v.contains(';') || v.contains('"') || v.contains('\n')) {
      return '"$v"';
    }
    return v;
  }

  static String build(List<TripRecord> trips) {
    final dateFmt = DateFormat('d.M.yyyy');
    final timeFmt = DateFormat('HH:mm');
    final buf = StringBuffer(_utf8Bom);
    buf.writeln(
      'Dátum;Čas štart;Čas cieľ;Vozidlo;Vodič;Účel;Typ;KM;Tacho pred;Tacho po;Štart súradnice;Cieľ súradnice',
    );
    for (final t in trips) {
      final fields = [
        dateFmt.format(t.startedAt),
        timeFmt.format(t.startedAt),
        t.endedAt != null ? timeFmt.format(t.endedAt!) : '',
        _escape(t.vehicleLabel),
        _escape(t.driverName),
        _escape(t.purpose),
        t.kind == TripKind.business ? 'Služobná' : 'Súkromná',
        t.distanceKm != null ? t.distanceKm!.toStringAsFixed(1) : '',
        t.odometerStart?.toString() ?? '',
        t.odometerEnd?.toString() ?? '',
        t.startLat != null && t.startLng != null
            ? '${t.startLat!.toStringAsFixed(5)},${t.startLng!.toStringAsFixed(5)}'
            : '',
        t.endLat != null && t.endLng != null
            ? '${t.endLat!.toStringAsFixed(5)},${t.endLng!.toStringAsFixed(5)}'
            : '',
      ];
      buf.writeln(fields.join(';'));
    }
    return buf.toString();
  }

  /// Build CSV, write to a temp file, and trigger the OS share sheet.
  static Future<void> shareCsv(
    List<TripRecord> trips, {
    required String monthLabel,
  }) async {
    final csv = build(trips);
    final dir = await getTemporaryDirectory();
    final filename = 'kniha-jazd_$monthLabel.csv';
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: filename)],
      subject: 'AutoLogic Drive — kniha jázd $monthLabel',
    );
  }
}
