import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local-first SQLite store. No login, no backend, no analytics.
/// Tables: medications, dose_logs, meta (key/value flags).
class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;

  static const _name = 'dosewise.db';
  static const _version = 1;

  /// Meta keys.
  static const kOnboardingDone = 'onboarding_done';
  static const kInterstitialShownDate = 'interstitial_shown_date';
  static const kStreakCount = 'streak_count';
  static const kStreakComputedFor = 'streak_computed_for'; // yyyy-MM-dd
  static const kReviewPrompted = 'review_prompted';

  static Future<AppDatabase> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), _name);
    final db = await openDatabase(
      dbPath,
      version: _version,
      onCreate: (d, v) async {
        await d.execute('''
          CREATE TABLE medications(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            dose TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT 'medication',
            times TEXT NOT NULL,
            days TEXT NOT NULL,
            pills_remaining INTEGER,
            paused INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )''');
        await d.execute('''
          CREATE TABLE dose_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            med_id INTEGER NOT NULL,
            date TEXT NOT NULL,
            time TEXT NOT NULL,
            scheduled_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            snooze_count INTEGER NOT NULL DEFAULT 0,
            logged_at TEXT,
            UNIQUE(med_id, date, time)
          )''');
        await d.execute(
            'CREATE INDEX idx_dose_logs_day ON dose_logs(date, status)');
        await d.execute(
            'CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    );
    return AppDatabase._(db);
  }

  Future<void> close() => _db.close();

  // ---------- medications ----------

  Future<int> insertMedication(Medication m) =>
      _db.insert('medications', m.toMap());

  Future<int> updateMedication(Medication m) => _db.update(
        'medications',
        m.toMap(),
        where: 'id = ?',
        whereArgs: [m.id],
      );

  Future<int> deleteMedication(int id) =>
      _db.delete('medications', where: 'id = ?', whereArgs: [id]);

  Future<List<Medication>> allMedications() async {
    final rows =
        await _db.query('medications', orderBy: 'created_at ASC, id ASC');
    return rows.map(Medication.fromMap).toList();
  }

  Future<List<Medication>> activeMedications() async {
    final rows = await _db.query('medications',
        where: 'paused = 0', orderBy: 'created_at ASC, id ASC');
    return rows.map(Medication.fromMap).toList();
  }

  Future<Medication?> medicationById(int id) async {
    final rows =
        await _db.query('medications', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Medication.fromMap(rows.first);
  }

  // ---------- dose logs ----------

  /// Insert-or-ignore: an occurrence row for (med, date, time).
  Future<void> ensureLog(DoseLog log) async {
    await _db.insert('dose_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<DoseLog?> findLog(int medId, String date, String time) async {
    final rows = await _db.query('dose_logs',
        where: 'med_id = ? AND date = ? AND time = ?',
        whereArgs: [medId, date, time]);
    return rows.isEmpty ? null : DoseLog.fromMap(rows.first);
  }

  Future<List<DoseLog>> logsForDate(String date) async {
    final rows = await _db
        .query('dose_logs', where: 'date = ?', whereArgs: [date]);
    return rows.map(DoseLog.fromMap).toList();
  }

  /// All logs in an inclusive date range, one query (stats fast path —
  /// avoids hundreds of sequential per-day queries).
  Future<List<DoseLog>> logsForDateRange(
      String startDate, String endDate) async {
    final rows = await _db.query('dose_logs',
        where: 'date >= ? AND date <= ?',
        whereArgs: [startDate, endDate]);
    return rows.map(DoseLog.fromMap).toList();
  }

  /// Every unresolved log (pending or snoozed), any date — the sweep set.
  Future<List<DoseLog>> unresolvedLogs() async {
    final rows = await _db.query('dose_logs',
        where: "status IN ('pending','snoozed')");
    return rows.map(DoseLog.fromMap).toList();
  }

  Future<List<DoseLog>> logsForMed(int medId, {int limit = 500}) async {
    final rows = await _db.query('dose_logs',
        where: 'med_id = ?', whereArgs: [medId], orderBy: 'date DESC, time DESC', limit: limit);
    return rows.map(DoseLog.fromMap).toList();
  }

  Future<int> updateLog(DoseLog log) => _db.update(
        'dose_logs',
        log.toMap(),
        where: 'id = ?',
        whereArgs: [log.id],
      );

  Future<int> deleteLogsForMed(int medId) =>
      _db.delete('dose_logs', where: 'med_id = ?', whereArgs: [medId]);

  // ---------- meta ----------

  Future<String?> metaGet(String key) async {
    final rows =
        await _db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> metaSet(String key, String value) async {
    await _db.insert(
        'meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------- danger zone ----------

  Future<void> wipeAll() async {
    await _db.delete('dose_logs');
    await _db.delete('medications');
    await _db.delete('meta');
  }
}
