import 'package:flutter/widgets.dart';

import 'ads/ad_service.dart';
import 'app.dart';
import 'boot.dart';
import 'db/database.dart';
import 'meds/medication_repository.dart';
import 'notifications/notification_service.dart';
import 'settings_store.dart';

/// Background entry-point for the native BootReceiver / time-change
/// receiver. Runs in a background FlutterEngine (no UI).
/// MUST stay top-level in this library (DartExecutor looks it up here).
@pragma('vm:entry-point')
Future<void> rescheduleOnBoot() => bootReschedule();

/// Launch order is defensive: the first frame must never be blocked by
/// alarms, ads, or anything that can throw on a real phone.
/// - Before runApp: DB, settings, notification init, repo load, sweep,
///   log rows — all local and fast.
/// - After first frame (best-effort, guarded): AdMob init + alarm top-up.
/// Nothing here may throw out of main(): a denied exact-alarm permission
/// once froze the app on the splash — never again.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await AppDatabase.open();
  final settings = SettingsStore();
  await settings.load();
  final repo = MedicationRepository(db);

  try {
    await NotificationService.instance.init(
      db: db,
      settings: settings,
      onDoseAction: () => repo.load(),
    );
  } catch (e) {
    debugPrint('notification init failed (reminders degraded): $e');
  }

  await repo.load();
  try {
    // Mark anything whose grace window passed while we were away.
    await repo.sweepMissed();
    // Idempotent occurrence rows for the next 14 days.
    await repo.ensureUpcomingLogs();
  } catch (e) {
    debugPrint('launch log prep failed: $e');
  }

  runApp(DoseWiseApp(db: db, repo: repo, settings: settings));

  // Post-first-frame: ads + alarm top-up (covers DST/travel/reboot gaps).
  // Fire-and-forget with guards — the UI is already up.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await AdService.init(db);
    } catch (e) {
      debugPrint('AdMob init failed (ads off): $e');
    }
    try {
      final meds = await db.allMedications();
      await NotificationService.instance.rescheduleAll(db, meds);
    } catch (e) {
      debugPrint('launch alarm top-up failed: $e');
    }
  });
}
