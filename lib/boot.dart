import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'db/database.dart';
import 'meds/medication_repository.dart';
import 'notifications/notification_service.dart';
import 'settings_store.dart';

/// Background reschedule logic shared by the boot receiver and the
/// time/timezone-change receiver (native side invokes [rescheduleOnBoot]
/// from main.dart in a background FlutterEngine).
///
/// Design (spec §4): no silent 00:05 job. Alarms are registered up to
/// [kScheduleWindowDays] ahead, so they survive app-kill and Doze. Only a
/// reboot clears them — the native BootReceiver re-runs this. Every app
/// launch also tops the window back up. Streaks are computed on demand.
Future<void> bootReschedule() async {
  WidgetsFlutterBinding.ensureInitialized();
  final svc = NotificationService.instance;
  final settings = SettingsStore();
  final db = await AppDatabase.open();
  try {
    await settings.load();
    await svc.initForBackground(db: db, settings: settings);
    final repo = MedicationRepository(db);
    await repo.load();
    // Log rows must exist before alarms reference them.
    await repo.ensureUpcomingLogs();
    await repo.sweepMissed();
    final meds = await db.allMedications();
    await svc.rescheduleAll(db, meds);
  } finally {
    await db.close();
  }
  // Tell the native receiver we're done so it can destroy the engine.
  // A watchdog on the native side destroys it anyway after a timeout.
  try {
    await const MethodChannel('com.dosewise.app/boot')
        .invokeMethod('bootDone');
  } catch (_) {
    // Native side may already be gone; harmless.
  }
}
