import 'dart:convert';

/// Dose status for one scheduled occurrence.
enum DoseStatus { pending, taken, skipped, snoozed, missed }

DoseStatus doseStatusFromString(String s) =>
    DoseStatus.values.firstWhere((e) => e.name == s,
        orElse: () => DoseStatus.pending);

/// Medication vs vitamin/supplement (friendlier copy for the slice strategy).
enum MedType { medication, vitamin }

MedType medTypeFromString(String s) =>
    s == 'vitamin' ? MedType.vitamin : MedType.medication;

/// One medication / vitamin row.
class Medication {
  final int? id;
  final String name;
  final String dose; // free text: "1 capsule", "500mg"
  final MedType type;
  final List<String> times; // ["08:00","20:00"] — 24h HH:mm, max 6
  final List<int> days; // 1=Mon .. 7=Sun
  final int? pillsRemaining; // null = refill tracking off
  final bool paused;
  final DateTime createdAt;

  const Medication({
    this.id,
    required this.name,
    this.dose = '',
    this.type = MedType.medication,
    required this.times,
    required this.days,
    this.pillsRemaining,
    this.paused = false,
    required this.createdAt,
  });

  /// Doses scheduled per calendar day for this med.
  int get dosesPerDay => times.length;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'dose': dose,
        'type': type.name,
        'times': jsonEncode(times),
        'days': jsonEncode(days),
        'pills_remaining': pillsRemaining,
        'paused': paused ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
      };

  static Medication fromMap(Map<String, Object?> m) => Medication(
        id: m['id'] as int?,
        name: m['name'] as String,
        dose: (m['dose'] as String?) ?? '',
        type: medTypeFromString((m['type'] as String?) ?? 'medication'),
        times: (jsonDecode(m['times'] as String) as List)
            .map((e) => e.toString())
            .toList(),
        days: (jsonDecode(m['days'] as String) as List)
            .map((e) => (e as num).toInt())
            .toList(),
        pillsRemaining: m['pills_remaining'] as int?,
        paused: (m['paused'] as int? ?? 0) == 1,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Medication copyWith({
    int? id,
    String? name,
    String? dose,
    MedType? type,
    List<String>? times,
    List<int>? days,
    int? pillsRemaining,
    bool clearPillsRemaining = false,
    bool? paused,
    DateTime? createdAt,
  }) =>
      Medication(
        id: id ?? this.id,
        name: name ?? this.name,
        dose: dose ?? this.dose,
        type: type ?? this.type,
        times: times ?? this.times,
        days: days ?? this.days,
        pillsRemaining: clearPillsRemaining
            ? null
            : (pillsRemaining ?? this.pillsRemaining),
        paused: paused ?? this.paused,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// One row in dose_logs — a single scheduled occurrence on a day.
class DoseLog {
  final int? id;
  final int medId;
  final String date; // yyyy-MM-dd, scheduled day (local)
  final String time; // HH:mm, ORIGINAL slot (identity), not snooze-shifted
  final DateTime scheduledAt; // current fire time (moves with snooze)
  final DoseStatus status;
  final int snoozeCount;
  final DateTime? loggedAt;

  const DoseLog({
    this.id,
    required this.medId,
    required this.date,
    required this.time,
    required this.scheduledAt,
    this.status = DoseStatus.pending,
    this.snoozeCount = 0,
    this.loggedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'med_id': medId,
        'date': date,
        'time': time,
        'scheduled_at': scheduledAt.toIso8601String(),
        'status': status.name,
        'snooze_count': snoozeCount,
        'logged_at': loggedAt?.toIso8601String(),
      };

  static DoseLog fromMap(Map<String, Object?> m) => DoseLog(
        id: m['id'] as int?,
        medId: m['med_id'] as int,
        date: m['date'] as String,
        time: m['time'] as String,
        scheduledAt: DateTime.parse(m['scheduled_at'] as String),
        status: doseStatusFromString((m['status'] as String?) ?? 'pending'),
        snoozeCount: (m['snooze_count'] as int?) ?? 0,
        loggedAt: m['logged_at'] == null
            ? null
            : DateTime.parse(m['logged_at'] as String),
      );

  DoseLog copyWith({
    int? id,
    DateTime? scheduledAt,
    DoseStatus? status,
    int? snoozeCount,
    DateTime? loggedAt,
  }) =>
      DoseLog(
        id: id ?? this.id,
        medId: medId,
        date: date,
        time: time,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        status: status ?? this.status,
        snoozeCount: snoozeCount ?? this.snoozeCount,
        loggedAt: loggedAt ?? this.loggedAt,
      );
}

/// A scheduled dose for display — occurrence + its current log state.
/// Identity = (med.id, [date], [time]) — the ORIGINAL slot. [scheduledAt]
/// is the current fire time and moves with snooze; identity never does.
class DoseOccurrence {
  final Medication med;
  final String date; // yyyy-MM-dd, original scheduled day
  final String time; // HH:mm, original slot (identity)
  final DateTime scheduledAt; // current fire time (snooze shifts this)
  final DoseStatus status;
  final int snoozeCount;
  final int? logId;

  const DoseOccurrence({
    required this.med,
    required this.date,
    required this.time,
    required this.scheduledAt,
    this.status = DoseStatus.pending,
    this.snoozeCount = 0,
    this.logId,
  });

  /// Display time for the current fire time.
  String get displayTime =>
      '${scheduledAt.hour.toString().padLeft(2, '0')}:${scheduledAt.minute.toString().padLeft(2, '0')}';

  DoseOccurrence copyWith({
    Medication? med,
    String? date,
    String? time,
    DateTime? scheduledAt,
    DoseStatus? status,
    int? snoozeCount,
    int? logId,
  }) =>
      DoseOccurrence(
        med: med ?? this.med,
        date: date ?? this.date,
        time: time ?? this.time,
        scheduledAt: scheduledAt ?? this.scheduledAt,
        status: status ?? this.status,
        snoozeCount: snoozeCount ?? this.snoozeCount,
        logId: logId ?? this.logId,
      );
}

/// yyyy-MM-dd for a local date.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "HH:mm" for a local time.
String timeKey(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

DateTime parseSlot(String dateStr, String hhmm) {
  final parts = dateStr.split('-').map(int.parse).toList();
  final tp = hhmm.split(':').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2], tp[0], tp[1]);
}
