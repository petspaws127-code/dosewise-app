import 'package:dosewise/db/models.dart';
import 'package:dosewise/schedule/dose_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

Medication _med({
  int? id = 1,
  List<String> times = const ['08:00', '20:00'],
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  bool paused = false,
  DateTime? createdAt,
}) =>
    Medication(
      id: id,
      name: 'Vitamin D',
      dose: '1 capsule',
      times: times,
      days: days,
      paused: paused,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );

void main() {
  group('occurrencesForDay', () {
    test('emits one occurrence per time slot on scheduled weekdays', () {
      final monday = DateTime(2026, 10, 19); // a Monday
      final occ = occurrencesForDay(
        meds: [_med()],
        day: monday,
        logs: {},
      );
      expect(occ.length, 2);
      expect(occ[0].scheduledAt.hour, 8);
      expect(occ[1].scheduledAt.hour, 20);
      expect(occ[0].status, DoseStatus.pending);
    });

    test('skips days not in the schedule', () {
      final monday = DateTime(2026, 10, 19);
      final occ = occurrencesForDay(
        meds: [_med(days: [6, 7])], // weekends only
        day: monday,
        logs: {},
      );
      expect(occ, isEmpty);
    });

    test('skips paused medications', () {
      final monday = DateTime(2026, 10, 19);
      final occ = occurrencesForDay(
        meds: [_med(paused: true)],
        day: monday,
        logs: {},
      );
      expect(occ, isEmpty);
    });

    test('merges existing log state and snooze-shifted fire time', () {
      final monday = DateTime(2026, 10, 19);
      final date = dateKey(monday);
      final logs = {
        '1|$date|08:00': DoseLog(
          medId: 1,
          date: date,
          time: '08:00',
          scheduledAt: DateTime(2026, 10, 19, 8, 15), // snoozed
          status: DoseStatus.pending,
          snoozeCount: 1,
        ),
      };
      final occ = occurrencesForDay(
        meds: [_med()],
        day: monday,
        logs: logs,
      );
      expect(occ.length, 2);
      final morning = occ.firstWhere((o) => o.time == '08:00');
      expect(morning.scheduledAt,
          DateTime(2026, 10, 19, 8, 15)); // snooze-shifted
      expect(morning.time, '08:00'); // identity kept
      expect(morning.snoozeCount, 1);
    });

    test('med created after the day does not count for it', () {
      final monday = DateTime(2026, 10, 19);
      final occ = occurrencesForDay(
        meds: [_med(createdAt: DateTime(2026, 10, 20))],
        day: monday,
        logs: {},
      );
      expect(occ, isEmpty);
    });
  });

  group('computeStreak', () {
    // Helper: all-taken history for the last [days] days.
    Map<String, Map<String, DoseStatus>> takenHistory(
        int days, DateTime today) {
      final out = <String, Map<String, DoseStatus>>{};
      for (var d = 1; d <= days; d++) {
        final day = DateTime(today.year, today.month, today.day)
            .subtract(Duration(days: d));
        final date = dateKey(day);
        out[date] = {
          for (final t in ['08:00', '20:00']) '1|$t': DoseStatus.taken,
        };
      }
      return out;
    }

    test('counts consecutive all-taken days', () {
      final today = DateTime(2026, 10, 20);
      final streak = computeStreak(
        today: today,
        meds: [_med()],
        statusesByDate: takenHistory(10, today),
      );
      expect(streak, 10);
    });

    test('skipped counts as resolved, missed breaks', () {
      final today = DateTime(2026, 10, 20);
      final history = takenHistory(10, today);
      final yesterday = dateKey(today.subtract(const Duration(days: 1)));
      history[yesterday]!['1|08:00'] = DoseStatus.skipped;
      expect(
        computeStreak(
            today: today, meds: [_med()], statusesByDate: history),
        10,
      );

      final twoDaysAgo =
          dateKey(today.subtract(const Duration(days: 2)));
      history[twoDaysAgo]!['1|20:00'] = DoseStatus.missed;
      expect(
        computeStreak(
            today: today, meds: [_med()], statusesByDate: history),
        1, // only yesterday counts; the missed day breaks
      );
    });

    test('pending yesterday breaks the streak', () {
      final today = DateTime(2026, 10, 20);
      final history = takenHistory(10, today);
      final yesterday = dateKey(today.subtract(const Duration(days: 1)));
      history[yesterday]!['1|08:00'] = DoseStatus.pending;
      expect(
        computeStreak(
            today: today, meds: [_med()], statusesByDate: history),
        0,
      );
    });

    test('days with no scheduled doses are skipped, not breaking', () {
      // Med only on Mondays; check a Wednesday with full Monday history.
      final wednesday = DateTime(2026, 10, 21);
      final monday = dateKey(DateTime(2026, 10, 19));
      final prevMonday = dateKey(DateTime(2026, 10, 12));
      final history = {
        monday: {'1|08:00': DoseStatus.taken},
        prevMonday: {'1|08:00': DoseStatus.taken},
      };
      final streak = computeStreak(
        today: wednesday,
        meds: [_med(times: ['08:00'], days: [1])],
        statusesByDate: history,
      );
      expect(streak, 2); // Tue skipped over, both Mondays count
    });
  });

  group('refill math', () {
    test('daysOfSupply divides pills by daily usage', () {
      final med = _med().copyWith(pillsRemaining: 30);
      // 2 doses/day × 7/7 days = 2/day → 15 days
      expect(daysOfSupply(med), closeTo(15.0, 0.01));
    });

    test('needsRefill at <= 7 days of supply', () {
      expect(
          needsRefill(_med().copyWith(pillsRemaining: 14)), true);
      expect(
          needsRefill(_med().copyWith(pillsRemaining: 16)), false);
      expect(needsRefill(_med()), false); // tracking off
    });

    test('weekday-only schedules scale daily usage', () {
      // 1 dose/day × 5/7 → 30 pills = 42 days
      final med = _med(
        times: ['08:00'],
        days: [1, 2, 3, 4, 5],
      ).copyWith(pillsRemaining: 30);
      expect(daysOfSupply(med), closeTo(42.0, 0.01));
    });
  });

  group('weeklyAdherence', () {
    test('null when nothing scheduled', () {
      expect(
        weeklyAdherence(
          today: DateTime(2026, 10, 20),
          meds: [],
          statusesByDate: {},
        ),
        isNull,
      );
    });

    test('computes taken ratio over the Mon-Sun week so far', () {
      final today = DateTime(2026, 10, 20); // Tuesday
      final history = <String, Map<String, DoseStatus>>{};
      // 7 days × 2 doses = 14; mark 7 taken.
      for (var d = 0; d < 7; d++) {
        final day = DateTime(2026, 10, 20).subtract(Duration(days: d));
        final date = dateKey(day);
        history[date] = {
          '1|08:00': DoseStatus.taken,
          '1|20:00':
              d.isEven ? DoseStatus.taken : DoseStatus.missed,
        };
      }
      final pct = weeklyAdherence(
        today: today,
        meds: [_med()],
        statusesByDate: history,
      );
      // Week so far = Mon Oct 19 (d=1: 1/2) + Tue Oct 20 (d=0: 2/2)
      // → 3/4. Future days of the week are not counted.
      expect(pct, closeTo(75.0, 0.01));
    });
  });
}
