import 'package:dosewise/db/database.dart';
import 'package:dosewise/db/models.dart';
import 'package:dosewise/meds/medication_repository.dart';
import 'package:dosewise/schedule/dose_schedule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late AppDatabase db;
  late MedicationRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath);
    repo = MedicationRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Medication vitaminD() => Medication(
        name: 'Vitamin D',
        dose: '1 capsule',
        times: ['08:00'],
        days: [1, 2, 3, 4, 5, 6, 7],
        pillsRemaining: 30,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );

  group('MedicationRepository', () {
    test('add → load round-trips the medication', () async {
      final saved = await repo.add(vitaminD());
      expect(saved.id, isNotNull);
      await repo.load();
      expect(repo.meds.length, 1);
      expect(repo.meds.first.name, 'Vitamin D');
      expect(repo.meds.first.times, ['08:00']);
    });

    test('logTaken marks taken and decrements pills', () async {
      final saved = await repo.add(vitaminD());
      await repo.load();
      await repo.ensureUpcomingLogs(days: 1);

      final doses = await repo.todaysDoses();
      expect(doses, isNotEmpty);
      final occ = doses.firstWhere((d) => d.med.id == saved.id);

      expect(await repo.logTaken(occ), true);
      final log =
          await db.findLog(saved.id!, occ.date, occ.time);
      expect(log!.status, DoseStatus.taken);
      expect(log.loggedAt, isNotNull);

      final med = await db.medicationById(saved.id!);
      expect(med!.pillsRemaining, 29);

      // Double-tap is idempotent.
      expect(await repo.logTaken(occ), false);
    });

    test('undoTaken works within 10 minutes, locked after', () async {
      final saved = await repo.add(vitaminD());
      await repo.load();
      await repo.ensureUpcomingLogs(days: 1);
      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);
      await repo.logTaken(occ);

      // Within window → undo succeeds.
      expect(await repo.undoTaken(occ), true);
      var log = await db.findLog(saved.id!, occ.date, occ.time);
      expect(log!.status, DoseStatus.pending);

      // Simulate an old log → undo refused.
      await repo.logTaken(occ);
      log = await db.findLog(saved.id!, occ.date, occ.time);
      await db.updateLog(log!.copyWith(
        loggedAt:
            DateTime.now().subtract(const Duration(minutes: 11)),
      ));
      expect(await repo.undoTaken(occ), false);
    });

    test('sweepMissed marks doses past the 2h grace window', () async {
      final saved = await repo.add(vitaminD());
      await repo.load();
      await repo.ensureUpcomingLogs(days: 1);

      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);
      // Backdate the scheduled time 3h ago → past grace.
      final log = await db.findLog(saved.id!, occ.date, occ.time);
      await db.updateLog(log!.copyWith(
        scheduledAt:
            DateTime.now().subtract(const Duration(hours: 3)),
      ));

      await repo.sweepMissed();
      final after =
          await db.findLog(saved.id!, occ.date, occ.time);
      expect(after!.status, DoseStatus.missed);
    });

    test('sweepMissed leaves future doses pending', () async {
      // Time-independent: schedule the dose 3h in the future.
      final future =
          DateTime.now().add(const Duration(hours: 3));
      final hhmm =
          '${future.hour.toString().padLeft(2, '0')}:${future.minute.toString().padLeft(2, '0')}';
      final saved = await repo.add(Medication(
        name: 'Vitamin D',
        dose: '1 capsule',
        times: [hhmm],
        days: [1, 2, 3, 4, 5, 6, 7],
        createdAt:
            DateTime.now().subtract(const Duration(days: 1)),
      ));
      await repo.load();
      await repo.ensureUpcomingLogs(days: 1);
      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);

      await repo.sweepMissed();
      final after =
          await db.findLog(saved.id!, occ.date, occ.time);
      expect(after!.status, DoseStatus.pending);
    });

    test('delete keeps history but stops reminders data', () async {
      final saved = await repo.add(vitaminD());
      await repo.load();
      await repo.ensureUpcomingLogs(days: 1);
      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);
      await repo.logTaken(occ);

      await repo.delete(saved.id!);
      await repo.load();
      expect(repo.meds, isEmpty);

      // History retained for stats honesty (any row, not just the
      // latest — the window now holds future pending rows too).
      final logs = await db.logsForMed(saved.id!);
      expect(logs, isNotEmpty);
      expect(logs.any((l) => l.status == DoseStatus.taken), true);
    });

    test('interstitial cap flag round-trips via meta', () async {
      final today = dateKey(DateTime.now());
      await db.metaSet(
          AppDatabase.kInterstitialShownDate, today);
      expect(
          await db.metaGet(
              AppDatabase.kInterstitialShownDate),
          today);
    });

    test('isDayComplete requires taken-or-skipped for all', () {      final med = vitaminD();
      final occ = DoseOccurrence(
        med: med,
        date: '2026-10-16',
        time: '08:00',
        scheduledAt: DateTime(2026, 10, 16, 8, 0),
        status: DoseStatus.taken,
      );
      expect(isDayComplete([occ]), true);
      expect(
          isDayComplete([
            occ,
            DoseOccurrence(
              med: med,
              date: '2026-10-16',
              time: '20:00',
              scheduledAt: DateTime(2026, 10, 16, 20, 0),
              status: DoseStatus.pending,
            ),
          ]),
          false);
      expect(isDayComplete([]), false);
    });

    test('add creates log rows immediately — loggable without restart',
        () async {
      // Regression: add()/update() never called ensureUpcomingLogs(), so
      // Taken/Snooze/Skip silently did nothing until an app restart.
      final future =
          DateTime.now().add(const Duration(hours: 2));
      final hhmm =
          '${future.hour.toString().padLeft(2, '0')}:${future.minute.toString().padLeft(2, '0')}';
      final saved = await repo.add(Medication(
        name: 'Vitamin D',
        times: [hhmm],
        days: [1, 2, 3, 4, 5, 6, 7],
        createdAt: DateTime.now(),
      ));
      // No manual ensureUpcomingLogs / load dance here.
      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);
      expect(await repo.logTaken(occ), true);
      final log =
          await db.findLog(saved.id!, occ.date, occ.time);
      expect(log!.status, DoseStatus.taken);
    });

    test('mid-day add creates no phantom past occurrence', () async {
      // Regression: adding a med at 2pm with an 8:00 slot created a
      // pending 8:00 row → instantly "Missed" + streak break.
      final now = DateTime.now();
      final past =
          now.subtract(const Duration(hours: 3));
      final coming = now.add(const Duration(hours: 3));
      String hhmm(DateTime d) =>
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
      final saved = await repo.add(Medication(
        name: 'Vitamin D',
        times: [hhmm(past), hhmm(coming)],
        days: [1, 2, 3, 4, 5, 6, 7],
        createdAt: now,
      ));
      final date = dateKey(now);
      // No log row for the past slot today.
      expect(await db.findLog(saved.id!, date, hhmm(past)),
          isNull);
      // The future slot is loggable.
      expect(
          await db.findLog(saved.id!, date, hhmm(coming)),
          isNotNull);
      final occs = await repo.todaysDoses();
      expect(
          occs
              .where((o) =>
                  o.med.id == saved.id && o.time == hhmm(past)),
          isEmpty);
      // And sweep can never mark the phantom missed.
      await repo.sweepMissed();
      expect(await db.findLog(saved.id!, date, hhmm(past)),
          isNull);
    });

    test('snooze marks the dose snoozed with a future fire time',
        () async {
      final future =
          DateTime.now().add(const Duration(hours: 2));
      final hhmm =
          '${future.hour.toString().padLeft(2, '0')}:${future.minute.toString().padLeft(2, '0')}';
      final saved = await repo.add(Medication(
        name: 'Vitamin D',
        times: [hhmm],
        days: [1, 2, 3, 4, 5, 6, 7],
        createdAt: DateTime.now(),
      ));
      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);
      expect(await repo.snooze(occ, minutes: 15), true);
      final log =
          await db.findLog(saved.id!, occ.date, occ.time);
      expect(log!.status, DoseStatus.snoozed);
      expect(log.snoozeCount, 1);
      expect(log.scheduledAt.isAfter(DateTime.now()), true);
      // Cap: 3 snoozes max.
      await repo.snooze(occ, minutes: 15);
      await repo.snooze(occ, minutes: 15);
      expect(await repo.snooze(occ, minutes: 15), false);
    });

    test('sweepMissed clears pending rows older than yesterday', () async {
      // Regression: sweep covered only today+yesterday, so pending rows
      // stayed "pending" forever when the app was closed for days.
      final saved = await repo.add(vitaminD());
      final old = DateTime.now().subtract(const Duration(days: 5));
      final date = dateKey(old);
      await db.ensureLog(DoseLog(
        medId: saved.id!,
        date: date,
        time: '08:00',
        scheduledAt: DateTime(old.year, old.month, old.day, 8, 0),
      ));
      await repo.sweepMissed();
      final log = await db.findLog(saved.id!, date, '08:00');
      expect(log!.status, DoseStatus.missed);
    });

    test('update with a new time makes the new slot loggable', () async {
      final future =
          DateTime.now().add(const Duration(hours: 2));
      final hhmm =
          '${future.hour.toString().padLeft(2, '0')}:${future.minute.toString().padLeft(2, '0')}';
      final saved = await repo.add(Medication(
        name: 'Vitamin D',
        times: ['08:00'],
        days: [1, 2, 3, 4, 5, 6, 7],
        createdAt:
            DateTime.now().subtract(const Duration(days: 1)),
      ));
      await repo.update(saved.copyWith(times: ['08:00', hhmm]));
      final date = dateKey(DateTime.now());
      expect(
          await db.findLog(saved.id!, date, hhmm), isNotNull);
    });

    test('undoTaken restores pending and the slot fire time', () async {
      final saved = await repo.add(vitaminD());
      await repo.load();
      await repo.ensureUpcomingLogs(days: 1);
      final occ = (await repo.todaysDoses())
          .firstWhere((d) => d.med.id == saved.id);
      await repo.logTaken(occ);
      expect(await repo.undoTaken(occ), true);
      final log =
          await db.findLog(saved.id!, occ.date, occ.time);
      expect(log!.status, DoseStatus.pending);
      expect(log.scheduledAt, parseSlot(occ.date, occ.time));
    });
  });
}
