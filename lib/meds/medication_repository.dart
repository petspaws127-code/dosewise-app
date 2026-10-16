import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../db/models.dart';
import '../notifications/notification_service.dart';
import '../schedule/dose_schedule.dart';

/// Grace window after the scheduled time before a pending dose becomes
/// "missed" (spec §2 edge 4).
const Duration kMissedGrace = Duration(hours: 2);

/// Undo window for a "Taken" tap (spec §2 edge 13).
const Duration kUndoWindow = Duration(minutes: 10);

/// Coordinates DB writes with alarm (re)scheduling. Single place where
/// medication mutations happen, so alarms can never drift out of sync.
class MedicationRepository extends ChangeNotifier {
  MedicationRepository(this._db);
  final AppDatabase _db;

  List<Medication> _meds = [];
  List<Medication> get meds => _meds;

  /// Non-null when the last alarm (re)schedule failed — the UI surfaces
  /// "Couldn't set the reminder — try again" + Retry from this.
  String? alarmError;

  Future<void> load() async {
    _meds = await _db.allMedications();
    notifyListeners();
  }

  Future<Medication> add(Medication med) async {
    final id = await _db.insertMedication(med);
    final saved = med.copyWith(id: id);
    await load();
    // New meds must be loggable immediately — no restart required.
    await ensureUpcomingLogs();
    await _reschedule();
    return saved;
  }

  Future<void> update(Medication med) async {
    await _db.updateMedication(med);
    await load();
    // New slots from an edit count from now — never instant "Missed".
    await ensureUpcomingLogs(slotsNotBefore: DateTime.now());
    await _reschedule();
  }

  /// Delete the medication but KEEP its history (spec §1.4 — stats honesty).
  Future<void> delete(int medId) async {
    await _db.deleteMedication(medId);
    await _reschedule();
    await load();
  }

  Future<void> setPaused(int medId, bool paused) async {
    final med = await _db.medicationById(medId);
    if (med == null) return;
    await _db.updateMedication(med.copyWith(paused: paused));
    await _reschedule();
    await load();
  }

  Future<void> markRefilled(int medId, int pills) async {
    final med = await _db.medicationById(medId);
    if (med == null) return;
    await _db.updateMedication(med.copyWith(pillsRemaining: pills));
    await _reschedule();
    await load();
  }

  /// Re-run alarm scheduling (Retry path for the UI). Returns success.
  Future<bool> retryAlarms() => _reschedule();

  /// Best-effort alarm sync: the DB is the source of truth and the full
  /// window is rebuilt on every launch / boot / time change. A scheduling
  /// failure must never break the medication write itself — but it IS
  /// surfaced via [alarmError] so the UI can tell the user.
  Future<bool> _reschedule() async {
    try {
      final meds = await _db.allMedications();
      final ok =
          await NotificationService.instance.rescheduleAll(_db, meds);
      alarmError = ok ? null : 'alarm';
      return ok;
    } catch (e) {
      debugPrint('alarm reschedule failed (will retry on launch): $e');
      alarmError = 'alarm';
      return false;
    }
  }

  // ---------- dose logging ----------

  /// Ensure occurrence rows exist for the next [days] days (idempotent).
  /// Skips slots that predate the medication (mid-day add → no phantom
  /// past "Missed"), and — for edits — slots before [slotsNotBefore].
  Future<void> ensureUpcomingLogs(
      {int days = 14, DateTime? slotsNotBefore}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (var d = 0; d < days; d++) {
      final day = today.add(Duration(days: d));
      final date = dateKey(day);
      for (final med in _meds) {
        if (med.paused || med.id == null) continue;
        if (!med.days.contains(day.weekday)) continue;
        for (final t in med.times) {
          final slotAt = parseSlot(date, t);
          if (slotAt.isBefore(med.createdAt)) continue;
          if (slotsNotBefore != null &&
              slotAt.isBefore(slotsNotBefore)) {
            continue;
          }
          await _db.ensureLog(DoseLog(
            medId: med.id!,
            date: date,
            time: t,
            scheduledAt: slotAt,
          ));
        }
      }
    }
  }

  Future<List<DoseOccurrence>> todaysDoses() async {
    await sweepMissed();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return dosesForDate(today);
  }

  /// Occurrences for any date (no sweep — used by Stats day detail).
  Future<List<DoseOccurrence>> dosesForDate(DateTime day) async {
    final date = dateKey(day);
    final logs = await _db.logsForDate(date);
    final byKey = {for (final l in logs) '${l.medId}|$date|${l.time}': l};
    return occurrencesForDay(meds: _meds, day: day, logs: byKey);
  }

  /// Mark unresolved doses whose grace window has passed as missed —
  /// across ALL dates, not just today/yesterday (a dose left pending for
  /// days while the app was closed must not stay "pending" forever).
  /// Runs on launch and whenever Today builds (spec §2 edge 4).
  Future<void> sweepMissed() async {
    final now = DateTime.now();
    final logs = await _db.unresolvedLogs();
    for (final log in logs) {
      if (now.isAfter(log.scheduledAt.add(kMissedGrace))) {
        await _db.updateLog(log.copyWith(
          status: DoseStatus.missed,
          loggedAt: now,
        ));
      }
    }
  }

  Future<bool> logTaken(DoseOccurrence occ) async {
    final log = await _findOrCreateLog(occ);
    if (log == null || log.status == DoseStatus.taken) return false;
    await _db.updateLog(log.copyWith(
      status: DoseStatus.taken,
      loggedAt: DateTime.now(),
    ));
    await _decrementPills(occ.med);
    // The taken dose's alarm must go away even for future doses
    // (diff-based reschedule cancels it).
    await _reschedule();
    await load();
    notifyListeners();
    return true;
  }

  Future<bool> logSkipped(DoseOccurrence occ) async {
    final log = await _findOrCreateLog(occ);
    if (log == null || log.status == DoseStatus.skipped) return false;
    await _db.updateLog(log.copyWith(
      status: DoseStatus.skipped,
      loggedAt: DateTime.now(),
    ));
    await _reschedule();
    notifyListeners();
    return true;
  }

  /// Snooze: the log keeps its identity but becomes a distinct "snoozed"
  /// occurrence with its own one-shot alarm (rescheduleAll picks it up).
  /// Returns false when the log is missing or the 3-snooze cap is hit.
  Future<bool> snooze(DoseOccurrence occ, {int? minutes}) async {
    final log = await _findOrCreateLog(occ);
    if (log == null || log.snoozeCount >= 3) return false;
    // Snooze length comes from Settings (default 15).
    final mins = minutes ?? 15;
    final fireAt = DateTime.now().add(Duration(minutes: mins));
    await _db.updateLog(log.copyWith(
      scheduledAt: fireAt,
      status: DoseStatus.snoozed,
      snoozeCount: log.snoozeCount + 1,
    ));
    await _reschedule();
    notifyListeners();
    return true;
  }

  /// Undo a "Taken" within the 10-minute window (spec §2 edge 13).
  /// Restores the pending state AND its alarm (via reschedule).
  Future<bool> undoTaken(DoseOccurrence occ) async {
    final log = await _db.findLog(occ.med.id!, occ.date, occ.time);
    if (log == null ||
        log.status != DoseStatus.taken ||
        log.loggedAt == null) {
      return false;
    }
    if (DateTime.now().difference(log.loggedAt!) > kUndoWindow) return false;
    await _db.updateLog(log.copyWith(
      status: DoseStatus.pending,
      scheduledAt: parseSlot(log.date, log.time),
      loggedAt: null,
    ));
    await _reschedule();
    notifyListeners();
    return true;
  }

  /// Find the log row, creating it when the occurrence was synthesized
  /// (e.g. a slot added by an edit before ensureUpcomingLogs ran).
  /// A missing row must never make a tap silently do nothing.
  Future<DoseLog?> _findOrCreateLog(DoseOccurrence occ) async {
    final medId = occ.med.id;
    if (medId == null) return null;
    final existing = await _db.findLog(medId, occ.date, occ.time);
    if (existing != null) return existing;
    final log = DoseLog(
      medId: medId,
      date: occ.date,
      time: occ.time,
      scheduledAt: parseSlot(occ.date, occ.time),
    );
    await _db.ensureLog(log);
    return _db.findLog(medId, occ.date, occ.time);
  }

  Future<void> _decrementPills(Medication med) async {
    if (med.pillsRemaining == null || med.id == null) return;
    final fresh = await _db.medicationById(med.id!);
    if (fresh == null || fresh.pillsRemaining == null) return;
    final left = (fresh.pillsRemaining! - 1).clamp(0, 1 << 30);
    await _db.updateMedication(fresh.copyWith(pillsRemaining: left));
    // Refill state may have changed → the daily 9 AM refill reminder
    // is added/removed by the reschedule in the caller.
  }

  Future<List<DoseLog>> logsForMed(int medId, {int limit = 500}) =>
      _db.logsForMed(medId, limit: limit);

  /// Meta flag access for UI-level one-shot prompts (review prompt).
  Future<String?> dbMeta(String key) => _db.metaGet(key);
  Future<void> dbMetaSet(String key, String value) =>
      _db.metaSet(key, value);

  // ---------- stats ----------

  /// Statuses for the last [days] days: date -> "medId|time" -> status.
  /// Kept for deleted meds too (history retained — stats honesty).
  /// One range query, not hundreds of sequential per-day queries.
  Future<Map<String, Map<String, DoseStatus>>> statusHistory(
      {int days = 370}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = dateKey(today.subtract(Duration(days: days)));
    final end = dateKey(today);
    final logs = await _db.logsForDateRange(start, end);
    final out = <String, Map<String, DoseStatus>>{};
    for (final l in logs) {
      (out[l.date] ??= {})['${l.medId}|${l.time}'] = l.status;
    }
    return out;
  }

  Future<int> currentStreak() async {
    final history = await statusHistory();
    return computeStreak(
      today: DateTime.now(),
      meds: _meds,
      statusesByDate: history,
    );
  }

  Future<double?> weekAdherence({int weekStart = 1}) async {
    final history = await statusHistory(days: 8);
    return weeklyAdherence(
      today: DateTime.now(),
      meds: _meds,
      statusesByDate: history,
      weekStart: weekStart,
    );
  }

  Future<List<DayAdherence>> weekBars() async {
    final history = await statusHistory(days: 8);
    return last7Days(
      today: DateTime.now(),
      meds: _meds,
      statusesByDate: history,
    );
  }

  /// 7-day adherence % for one medication (mini-ring on the Meds tab).
  Future<double?> medAdherence7(int medId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final history = await statusHistory(days: 8);
    var total = 0;
    var taken = 0;
    final med =
        _meds.where((m) => m.id == medId).firstOrNull;
    if (med == null) return null;
    for (var d = 0; d < 7; d++) {
      final day = today.subtract(Duration(days: d));
      final date = dateKey(day);
      if (!med.days.contains(day.weekday)) continue;
      for (final t in med.times) {
        total++;
        if (history[date]?['$medId|$t'] == DoseStatus.taken) taken++;
      }
    }
    if (total == 0) return null;
    return taken / total * 100;
  }

  /// 30-day adherence % per medication, worst-first (spec §1.5).
  Future<List<MedAdherence>> medAdherence30() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final history = await statusHistory(days: 31);
    final out = <MedAdherence>[];
    for (final med in _meds) {
      if (med.id == null) continue;
      var total = 0;
      var taken = 0;
      for (var d = 0; d < 30; d++) {
        final day = today.subtract(Duration(days: d));
        final date = dateKey(day);
        if (!med.days.contains(day.weekday)) continue;
        for (final t in med.times) {
          total++;
          if (history[date]?['${med.id}|$t'] == DoseStatus.taken) taken++;
        }
      }
      if (total > 0) {
        out.add(MedAdherence(
            med: med, percent: taken / total * 100, doses: total));
      }
    }
    out.sort((a, b) => a.percent.compareTo(b.percent));
    return out;
  }
}

class MedAdherence {
  final Medication med;
  final double percent;
  final int doses;
  const MedAdherence(
      {required this.med, required this.percent, required this.doses});
}
