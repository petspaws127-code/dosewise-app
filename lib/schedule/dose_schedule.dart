import '../db/models.dart';

/// Pure scheduling logic — no I/O, fully unit-testable.
///
/// A "dose occurrence" = one medication × one time slot × one calendar day.
/// Identity key: (medId, date yyyy-MM-dd, original time HH:mm).
/// Snooze moves `scheduledAt` but keeps the identity (original slot time).

/// All occurrences scheduled for [day] (local), merged with existing logs.
/// [logs] maps "medId|date|time" -> DoseLog.
List<DoseOccurrence> occurrencesForDay({
  required List<Medication> meds,
  required DateTime day,
  required Map<String, DoseLog> logs,
}) {
  final date = dateKey(day);
  final out = <DoseOccurrence>[];
  for (final med in meds) {
    if (med.paused) continue;
    if (!med.days.contains(day.weekday)) continue;
    for (final t in med.times) {
      // No phantom past occurrences: a slot that predates the medication
      // itself (mid-day add) never becomes a pending row. Slot precision,
      // not day precision — tomorrow's slots of a med created today count.
      if (parseSlot(date, t).isBefore(med.createdAt)) continue;
      final key = '${med.id}|$date|$t';
      final log = logs[key];
      out.add(DoseOccurrence(
        med: med,
        date: date,
        time: t,
        scheduledAt: log?.scheduledAt ?? parseSlot(date, t),
        status: log?.status ?? DoseStatus.pending,
        snoozeCount: log?.snoozeCount ?? 0,
        logId: log?.id,
      ));
    }
  }
  out.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  return out;
}

/// A med counts for a day if it was created on/before that day (local).
/// Day precision — used for history/streak math, where slot precision
/// would wrongly erase the creation day's earlier doses from the past.
bool _activeOn(Medication med, DateTime day) {
  final created = DateTime(
      med.createdAt.year, med.createdAt.month, med.createdAt.day);
  final d = DateTime(day.year, day.month, day.day);
  return !created.isAfter(d);
}

/// True when every occurrence of the day is resolved (taken or skipped).
bool isDayComplete(List<DoseOccurrence> occ) =>
    occ.isNotEmpty &&
    occ.every((o) =>
        o.status == DoseStatus.taken || o.status == DoseStatus.skipped);

/// Streak rules (locked in spec §1.5):
/// a day counts if it had >=1 scheduled dose and ALL were taken or skipped.
/// Missed breaks. Days with no scheduled doses are skipped over (don't break).
/// Walk back from yesterday; cap at 370 iterations.
int computeStreak({
  required DateTime today,
  required List<Medication> meds,
  required Map<String, Map<String, DoseStatus>> statusesByDate,
  // date yyyy-MM-dd -> "medId|time" -> status
}) {
  var streak = 0;
  var day = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 1));
  for (var i = 0; i < 370; i++) {
    final date = dateKey(day);
    final keys = <String>{};
    for (final med in meds) {
      if (med.paused) continue;
      if (!_activeOn(med, day)) continue;
      if (!med.days.contains(day.weekday)) continue;
      for (final t in med.times) {
        keys.add('${med.id}|$t');
      }
    }
    if (keys.isEmpty) {
      day = day.subtract(const Duration(days: 1));
      continue; // no doses scheduled — doesn't break the streak
    }
    final dayStatuses = statusesByDate[date] ?? const {};
    final allResolved = keys.every((k) {
      final s = dayStatuses[k];
      return s == DoseStatus.taken || s == DoseStatus.skipped;
    });
    if (!allResolved) break;
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Estimated days of supply left, or null when refill tracking is off.
double? daysOfSupply(Medication med) {
  final pills = med.pillsRemaining;
  if (pills == null) return null;
  final perDay = med.times.length * (med.days.length / 7.0);
  if (perDay <= 0) return null;
  return pills / perDay;
}

/// Refill alert threshold: <= 7 days of supply (spec §2 edge 14).
bool needsRefill(Medication med) {
  final s = daysOfSupply(med);
  return s != null && s <= 7.0;
}

/// Weekly adherence % for the calendar week containing [today],
/// starting on [weekStart] (1=Mon..7=Sun, spec §1.5).
/// Days after today are not counted yet.
/// Returns 0..100, or null when there were no scheduled doses at all.
double? weeklyAdherence({
  required DateTime today,
  required List<Medication> meds,
  required Map<String, Map<String, DoseStatus>> statusesByDate,
  int weekStart = 1,
}) {
  final t = DateTime(today.year, today.month, today.day);
  // Walk back to the week's first day.
  var day = t;
  while (day.weekday != weekStart) {
    day = day.subtract(const Duration(days: 1));
  }
  var total = 0;
  var taken = 0;
  for (var i = 0; i < 7; i++) {
    if (day.isAfter(t)) break; // don't count the future
    final date = dateKey(day);
    for (final med in meds) {
      if (med.paused) continue;
      if (!_activeOn(med, day)) continue;
      if (!med.days.contains(day.weekday)) continue;
      for (final tm in med.times) {
        total++;
        final s = statusesByDate[date]?['${med.id}|$tm'];
        if (s == DoseStatus.taken) taken++;
      }
    }
    day = day.add(const Duration(days: 1));
  }
  if (total == 0) return null;
  return taken / total * 100.0;
}

/// Per-day taken/missed/total for the last 7 days (bar chart).
/// Bars are labeled by their actual weekday (never a fixed M..S strip).
List<DayAdherence> last7Days({
  required DateTime today,
  required List<Medication> meds,
  required Map<String, Map<String, DoseStatus>> statusesByDate,
}) {
  final out = <DayAdherence>[];
  for (var i = 6; i >= 0; i--) {
    final day =
        DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: i));
    final date = dateKey(day);
    var total = 0;
    var taken = 0;
    var missed = 0;
    for (final med in meds) {
      if (med.paused) continue;
      if (!_activeOn(med, day)) continue;
      if (!med.days.contains(day.weekday)) continue;
      for (final tm in med.times) {
        total++;
        final s = statusesByDate[date]?['${med.id}|$tm'];
        if (s == DoseStatus.taken) {
          taken++;
        } else if (s == DoseStatus.missed) {
          missed++;
        }
      }
    }
    out.add(DayAdherence(
        date: day, taken: taken, missed: missed, total: total));
  }
  return out;
}

class DayAdherence {
  final DateTime date;
  final int taken;
  final int missed;
  final int total;
  const DayAdherence({
    required this.date,
    required this.taken,
    required this.missed,
    required this.total,
  });
}
