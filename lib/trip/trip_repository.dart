/// SQLite-backed log of all trips (kniha jázd).
///
/// Schema is created lazily on first access and migrated via `onUpgrade`.
/// All public methods are async; the repo doesn't keep an in-memory cache —
/// callers should fold results into `ValueNotifier`s / `setState` if they
/// need reactivity.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../util/app_logger.dart';
import 'trip_record.dart';

class TripRepository {
  static const _dbName = 'autologic_trips.db';
  static const _table = 'trips';
  static const _schemaVersion = 2;
  static const _uuid = Uuid();

  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _dbName);
    _db = await openDatabase(
      path,
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_table (
        id              TEXT PRIMARY KEY,
        started_at      INTEGER NOT NULL,
        ended_at        INTEGER,
        vehicle_mac     TEXT,
        vehicle_label   TEXT,
        driver_name     TEXT,
        purpose         TEXT NOT NULL DEFAULT '',
        kind            TEXT NOT NULL DEFAULT 'business',
        odometer_start  INTEGER,
        odometer_end    INTEGER,
        odo_start_photo TEXT,
        odo_end_photo   TEXT,
        source          TEXT NOT NULL,
        start_lat       REAL,
        start_lng       REAL,
        end_lat         REAL,
        end_lng         REAL,
        start_address   TEXT,
        end_address     TEXT,
        distance_km     REAL,
        synced          INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX trips_started_at ON $_table(started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX trips_synced ON $_table(synced) WHERE synced = 0',
    );
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    if (oldV < 2) {
      await db.execute('ALTER TABLE $_table ADD COLUMN start_address TEXT');
      await db.execute('ALTER TABLE $_table ADD COLUMN end_address TEXT');
    }
  }

  static String newId() => _uuid.v4();

  static Future<void> insert(TripRecord trip) async {
    final db = await _open();
    await db.insert(
      _table,
      trip.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    AppLogger.info('Trip log: insert ${trip.id} (${trip.vehicleLabel ?? "no vehicle"})');
  }

  static Future<void> update(TripRecord trip) async {
    final db = await _open();
    await db.update(
      _table,
      trip.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
  }

  static Future<TripRecord?> findById(String id) async {
    final db = await _open();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return TripRecord.fromMap(rows.first);
  }

  static Future<TripRecord?> findActive() async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'ended_at IS NULL',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TripRecord.fromMap(rows.first);
  }

  /// Newest-first list of trips. Pass `incompleteOnly: true` to filter to
  /// trips missing legally-required fields.
  static Future<List<TripRecord>> list({
    bool incompleteOnly = false,
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _open();
    final clauses = <String>[];
    final args = <Object?>[];
    if (from != null) {
      clauses.add('started_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (to != null) {
      clauses.add('started_at < ?');
      args.add(to.millisecondsSinceEpoch);
    }
    final where = clauses.isEmpty ? null : clauses.join(' AND ');
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'started_at DESC',
    );
    final all = rows.map(TripRecord.fromMap).toList();
    if (!incompleteOnly) return all;
    return all.where((t) => !t.isComplete).toList();
  }

  static Future<int> countIncomplete() async {
    final list = await TripRepository.list(incompleteOnly: true);
    return list.length;
  }

  /// Most recent completed trip for the given vehicle MAC that has a
  /// non-null `odometer_end`. Used by `TripDetailScreen` to pre-fill the
  /// next trip's `Tacho pred` from the previous trip's `Tacho po`.
  static Future<TripRecord?> lastCompletedWithOdoForVehicle(
    String vehicleMac, {
    String? excludeId,
  }) async {
    final db = await _open();
    final args = <Object?>[vehicleMac];
    var where =
        'vehicle_mac = ? AND ended_at IS NOT NULL AND odometer_end IS NOT NULL';
    if (excludeId != null) {
      where += ' AND id != ?';
      args.add(excludeId);
    }
    final rows = await db.query(
      _table,
      where: where,
      whereArgs: args,
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TripRecord.fromMap(rows.first);
  }

  /// Names that have ever been used as `driver_name` on a trip — for the
  /// driver autocomplete in `TripDetailScreen`. Excludes nulls and empty
  /// strings; returns alphabetised list.
  static Future<List<String>> distinctDriverNames() async {
    final db = await _open();
    final rows = await db.rawQuery(
      "SELECT DISTINCT driver_name FROM $_table "
      "WHERE driver_name IS NOT NULL AND driver_name != '' "
      "ORDER BY driver_name COLLATE NOCASE",
    );
    return rows.map((r) => r['driver_name'] as String).toList();
  }

  static Future<void> delete(String id) async {
    final db = await _open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    AppLogger.info('Trip log: delete $id');
  }

  /// Delete completed trips older than [retentionDays]. Active trips
  /// (`ended_at IS NULL`) are always kept. Pass a non-positive value to
  /// disable retention (no-op).
  static Future<int> purgeOlderThan(int retentionDays) async {
    if (retentionDays <= 0) return 0;
    final db = await _open();
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;
    final removed = await db.delete(
      _table,
      where: 'ended_at IS NOT NULL AND started_at < ?',
      whereArgs: [cutoff],
    );
    if (removed > 0) {
      AppLogger.info('Trip log: purged $removed trips older than $retentionDays days');
    }
    return removed;
  }
}
