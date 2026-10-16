import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
import '../db/models.dart';
import '../settings_store.dart';
import '../ui/time_fmt.dart';
import 'system_settings.dart';

/// Notification channel IDs.
const String kDoseChannelId = 'dose_reminders';
const String kRefillChannelId = 'refill_reminders';

/// Action IDs on dose notifications.
const String kActionTaken = 'taken';
const String kActionSnooze = 'snooze';
const String kActionSkip = 'skip';
const String kActionTakeAll = 'take_all';
const String kActionOpen = 'open';

/// How far ahead dose alarms are registered (spec §4).
const int kScheduleWindowDays = 14;

/// Max snoozes per dose (spec §2 edge 11).
const int kMaxSnoozes = 3;

/// Refill alert threshold in days of supply (spec §2 edge 14).
const double kRefillThresholdDays = 7.0;

// ---------------------------------------------------------------------------
// Payload helpers (pure, unit-testable)
// ---------------------------------------------------------------------------

String dosePayload(int medId, String date, String time) =>
    jsonEncode({'kind': 'dose', 'medId': medId, 'date': date, 'time': time});

String groupPayload(String date, String time, List<int> medIds) => jsonEncode(
    {'kind': 'group', 'date': date, 'time': time, 'medIds': medIds});

/// Defensive decode: corrupt payloads return null instead of throwing
/// (a throw in a notification callback is a silent drop).
Map<String, dynamic>? decodePayload(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final m = jsonDecode(raw);
    return m is Map<String, dynamic> ? m : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Notification IDs — FNV-1a, stable across process runs.
//
// rescheduleAll() diffs the desired set against the OS's pending list, so
// IDs MUST be deterministic across restarts (Dart's Object.hash is only
// documented as stable within a run).
// ---------------------------------------------------------------------------

int _fnv1a(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// One dose occurrence: (med, date, original slot time).
int doseNotificationId(int medId, String date, String time) =>
    _fnv1a('dose|$medId|$date|$time');

/// Grouped slot summary: (date, slot time).
int groupNotificationId(String date, String time) =>
    _fnv1a('group|$date|$time');

/// A snoozed dose gets its own ID keyed by the log row, so the snooze
/// alarm and the original slot alarm never collide.
int snoozeNotificationId(int logId) => _fnv1a('snooze|$logId');

/// Refill reminder: one per med per day-offset in the window.
int refillNotificationId(int medId, int dayOffset) =>
    _fnv1a('refill|$medId|$dayOffset');

// ---------------------------------------------------------------------------
// NotificationService
// ---------------------------------------------------------------------------

typedef DoseActionCallback = void Function();

/// Foreground action taps (Taken / Snooze / Skip / Take all / Open app) all
/// arrive here in the UI isolate — every action is built with
/// `showsUserInterface: true`, so taps launch/route to the app instead of a
/// plugin-less background engine. The background isolate path is therefore
/// used only by the boot/time-change receiver (which registers plugins
/// properly via GeneratedPluginRegistrant).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  DoseActionCallback? onDoseAction;
  AppDatabase? _db;
  SettingsStore? _settings;

  /// Full init for the UI isolate. Reuses the app's DB handle — no second
  /// connection, no SQLITE_BUSY on rapid taps.
  Future<void> init({
    required AppDatabase db,
    required SettingsStore settings,
    DoseActionCallback? onDoseAction,
  }) async {
    _db = db;
    _settings = settings;
    this.onDoseAction = onDoseAction;
    tzdata.initializeTimeZones();
    await _setLocalTz();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onResponse,
    );
    await _createChannels();
  }

  /// Minimal init for background isolates (boot receiver). Plugins ARE
  /// registered there by the native BootReceiver.
  Future<void> initForBackground({
    required AppDatabase db,
    required SettingsStore settings,
  }) async {
    _db = db;
    _settings = settings;
    tzdata.initializeTimeZones();
    await _setLocalTz();
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await plugin.initialize(initSettings);
    await _createChannels();
  }

  /// Resolve the real IANA zone. Falls back gracefully: flutter_timezone →
  /// DateTime time-zone name → UTC. Never silently wrong without trying.
  Future<void> _setLocalTz() async {
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
      return;
    } catch (_) {
      // fall through to legacy lookup
    }
    try {
      tz.setLocalLocation(tz.getLocation(DateTime.now().timeZoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  Future<void> _createChannels() async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(const AndroidNotificationChannel(
      kDoseChannelId,
      'Dose reminders',
      description: 'Reminders to take your medications and vitamins',
      importance: Importance.high,
    ));
    await android.createNotificationChannel(const AndroidNotificationChannel(
      kRefillChannelId,
      'Refill reminders',
      description: 'Reminders to refill low medications',
      importance: Importance.defaultImportance,
    ));
  }

  // ---------- foreground action handling ----------

  Future<void> _onResponse(NotificationResponse response) async {
    final db = _db;
    if (db == null) return;
    final payload = decodePayload(response.payload);
    if (payload == null) return;
    try {
      final changed = await _applyAction(
        db: db,
        actionId: response.actionId ?? '',
        payload: payload,
      );
      if (changed) {
        // Keep alarms in sync, then let the UI reload.
        await rescheduleAll(db, await db.allMedications());
        onDoseAction?.call();
      }
    } catch (e) {
      debugPrint('notification action failed: $e');
    }
  }

  /// Applies a notification action to the DB. Returns true when the UI
  /// should refresh. All defensive: bad payloads / missing logs → false.
  Future<bool> _applyAction({
    required AppDatabase db,
    required String actionId,
    required Map<String, dynamic> payload,
  }) async {
    final kind = payload['kind'] as String?;
    if (kind == 'dose') {
      final medId = (payload['medId'] as num?)?.toInt();
      final date = payload['date'] as String?;
      final time = payload['time'] as String?;
      if (medId == null || date == null || time == null) return false;
      return _applySingle(db, actionId, medId, date, time);
    } else if (kind == 'group') {
      final date = payload['date'] as String?;
      final time = payload['time'] as String?;
      final medIds = (payload['medIds'] as List?)
          ?.map((e) => (e as num?)?.toInt())
          .whereType<int>()
          .toList();
      if (date == null || time == null || medIds == null) return false;
      if (actionId == kActionTakeAll) {
        var changed = false;
        for (final id in medIds) {
          changed |= await _applySingle(db, kActionTaken, id, date, time);
        }
        return changed;
      }
      // 'open' or body tap: nothing to write; the app is already open.
      return false;
    }
    return false;
  }

  Future<bool> _applySingle(
    AppDatabase db,
    String actionId,
    int medId,
    String date,
    String time,
  ) async {
    final log = await db.findLog(medId, date, time);
    if (log == null) return false;
    final prefs = await SharedPreferences.getInstance();

    switch (actionId) {
      case kActionTaken:
        if (log.status == DoseStatus.taken) return false;
        await db.updateLog(log.copyWith(
          status: DoseStatus.taken,
          loggedAt: DateTime.now(),
        ));
        await _decrementPills(db, medId);
        return true;

      case kActionSkip:
        if (log.status == DoseStatus.skipped) return false;
        await db.updateLog(log.copyWith(
          status: DoseStatus.skipped,
          loggedAt: DateTime.now(),
        ));
        return true;

      case kActionSnooze:
        if (log.snoozeCount >= kMaxSnoozes) return false;
        final minutes = prefs.getInt('snooze_minutes') ?? 15;
        final fireAt = DateTime.now().add(Duration(minutes: minutes));
        await db.updateLog(log.copyWith(
          scheduledAt: fireAt,
          status: DoseStatus.snoozed,
          snoozeCount: log.snoozeCount + 1,
        ));
        return true;

      default:
        return false;
    }
  }

  Future<void> _decrementPills(AppDatabase db, int medId) async {
    final med = await db.medicationById(medId);
    if (med == null || med.pillsRemaining == null) return;
    final left = (med.pillsRemaining! - 1).clamp(0, 1 << 30);
    await db.updateMedication(med.copyWith(pillsRemaining: left));
  }

  // ---------- permissions ----------

  Future<bool> requestNotificationPermission() async {
    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<bool> canScheduleExactAlarms() async {
    try {
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestExactAlarmPermission() =>
      SystemSettings.requestExactAlarmPermission();

  // ---------- scheduling ----------

  /// Rebuild the alarm window as a DIFF against what the OS has pending:
  /// cancel stale IDs, schedule missing ones. Never a cancelAll() window
  /// where zero alarms exist (a process kill in that window = lost
  /// reminders). Log-status-aware: taken/skipped/missed occurrences get no
  /// alarm; snoozed occurrences get their own one-shot alarm.
  ///
  /// Returns true when scheduling completed. Never throws — callers treat
  /// false as "show the couldn't-schedule error".
  Future<bool> rescheduleAll(
    AppDatabase db,
    List<Medication> meds, {
    int windowDays = kScheduleWindowDays,
  }) async {
    try {
      return await _rescheduleUnsafe(db, meds, windowDays: windowDays);
    } catch (e) {
      debugPrint('rescheduleAll failed: $e');
      return false;
    }
  }

  Future<bool> _rescheduleUnsafe(
    AppDatabase db,
    List<Medication> meds, {
    int windowDays = kScheduleWindowDays,
  }) async {
    // One-time migration: old Object.hash IDs → FNV-1a. Clears any alarms
    // scheduled by the pre-release scheme.
    if (await db.metaGet('notif_id_scheme') != 'fnv1a') {
      try {
        await plugin.cancelAll();
      } catch (_) {}
      await db.metaSet('notif_id_scheme', 'fnv1a');
    }

    final prefs = await SharedPreferences.getInstance();
    final sound = prefs.getBool('sound_on') ?? true;
    final vibration = prefs.getBool('vibration_on') ?? true;
    final snoozeMinutes = prefs.getInt('snooze_minutes') ?? 15;
    final exactOk = await canScheduleExactAlarms();
    await prefs.setBool('exact_alarm_denied', !exactOk);
    final mode = exactOk
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Logs for the whole window (one query per day).
    final logsByKey = <String, DoseLog>{};
    for (var d = 0; d < windowDays; d++) {
      final date = dateKey(today.add(Duration(days: d)));
      for (final l in await db.logsForDate(date)) {
        logsByKey['${l.medId}|${l.date}|${l.time}'] = l;
      }
    }

    final jobs = <_Job>[];

    // Pending slots grouped by (date, time) for grouped alerts.
    final slots = <String, List<_SlotDose>>{};
    for (var d = 0; d < windowDays; d++) {
      final day = today.add(Duration(days: d));
      final date = dateKey(day);
      for (final med in meds) {
        if (med.id == null || med.paused) continue;
        if (!med.days.contains(day.weekday)) continue;
        for (final t in med.times) {
          final slotAt = parseSlot(date, t);
          // No phantom past occurrences (mid-day add).
          if (slotAt.isBefore(med.createdAt)) continue;
          final log = logsByKey['${med.id}|$date|$t'];
          final status = log?.status ?? DoseStatus.pending;
          if (status == DoseStatus.taken ||
              status == DoseStatus.skipped ||
              status == DoseStatus.missed) {
            continue; // resolved → no alarm (diff cancels any stale one)
          }
          if (status == DoseStatus.snoozed) {
            if (log != null &&
                log.id != null &&
                log.scheduledAt.isAfter(now)) {
              jobs.add(_snoozeJob(
                log: log,
                med: med,
                snoozeMinutes: snoozeMinutes,
                sound: sound,
                vibration: vibration,
              ));
            }
            continue;
          }
          // Pending: only future slots.
          if (!slotAt.isAfter(now)) continue;
          slots.putIfAbsent('$date|$t', () => []).add(
            _SlotDose(med: med, date: date, time: t, at: slotAt),
          );
        }
      }
    }

    final snoozeLabel = 'Snooze $snoozeMinutes min';
    for (final entry in slots.entries) {
      final parts = entry.key.split('|');
      final date = parts[0];
      final time = parts[1];
      final doses = entry.value;
      if (doses.length == 1) {
        jobs.add(_singleJob(doses.first,
            snoozeLabel: snoozeLabel, sound: sound, vibration: vibration));
      } else {
        jobs.add(_groupJob(
            date: date,
            time: time,
            at: doses.first.at,
            doses: doses,
            sound: sound,
            vibration: vibration));
      }
    }

    // Refill reminders: one daily 9:00 AM alarm per low med.
    for (final med in meds) {
      if (med.id == null || med.paused) continue;
      if (med.pillsRemaining == null) continue;
      final perDay = med.times.length * (med.days.length / 7.0);
      if (perDay <= 0) continue;
      if (med.pillsRemaining! / perDay > kRefillThresholdDays) continue;
      for (var d = 0; d < windowDays; d++) {
        final day = today.add(Duration(days: d));
        final at = DateTime(day.year, day.month, day.day, 9, 0);
        if (!at.isAfter(now)) continue;
        jobs.add(_Job(
          id: refillNotificationId(med.id!, d),
          title: 'Time to refill ${med.name}',
          body:
              'About ${med.pillsRemaining} left — refill before you run out.',
          at: at,
          payload: jsonEncode({'kind': 'refill', 'medId': med.id}),
          details: const NotificationDetails(
            android: AndroidNotificationDetails(
              kRefillChannelId,
              'Refill reminders',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
        ));
      }
    }

    // Diff against the OS pending list.
    Set<int> pendingIds;
    try {
      pendingIds = (await plugin.pendingNotificationRequests())
          .map((e) => e.id)
          .toSet();
    } catch (_) {
      pendingIds = <int>{};
    }
    final desiredIds = jobs.map((j) => j.id).toSet();
    for (final id in pendingIds) {
      if (!desiredIds.contains(id)) {
        try {
          await plugin.cancel(id);
        } catch (_) {}
      }
    }
    for (final job in jobs) {
      if (pendingIds.contains(job.id)) continue;
      await _scheduleJob(job, mode, prefs);
    }
    return true;
  }

  /// Schedule one alarm. Never throws: an exact-alarm denial mid-flight
  /// retries once as inexact; anything else is logged and skipped.
  Future<void> _scheduleJob(
      _Job job, AndroidScheduleMode mode, SharedPreferences prefs) async {
    AndroidScheduleMode useMode = mode;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await plugin.zonedSchedule(
          job.id,
          job.title,
          job.body,
          tz.TZDateTime.from(job.at, tz.local),
          job.details,
          androidScheduleMode: useMode,
          payload: job.payload,
        );
        return;
      } catch (e) {
        if (attempt == 0 &&
            useMode == AndroidScheduleMode.exactAllowWhileIdle) {
          // Exact denied between check and schedule → inexact fallback
          // (spec §2 edge 10) instead of a crash.
          useMode = AndroidScheduleMode.inexactAllowWhileIdle;
          await prefs.setBool('exact_alarm_denied', true);
          continue;
        }
        debugPrint('schedule failed for ${job.id}: $e');
        return;
      }
    }
  }

  String _fmt(DateTime at) {
    final s = _settings;
    return s == null
        ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
        : formatTime(at, s);
  }

  _Job _singleJob(
    _SlotDose d, {
    required String snoozeLabel,
    required bool sound,
    required bool vibration,
  }) {
    return _Job(
      id: doseNotificationId(d.med.id!, d.date, d.time),
      title: 'Time for ${d.med.name}',
      body:
          '${d.med.dose.isEmpty ? '' : '${d.med.dose} · '}${_fmt(d.at)}',
      at: d.at,
      payload: dosePayload(d.med.id!, d.date, d.time),
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          kDoseChannelId,
          'Dose reminders',
          importance: Importance.high,
          priority: Priority.high,
          playSound: sound,
          enableVibration: vibration,
          actions: [
            const AndroidNotificationAction(kActionTaken, 'Taken',
                showsUserInterface: true),
            AndroidNotificationAction(kActionSnooze, snoozeLabel,
                showsUserInterface: true),
            const AndroidNotificationAction(kActionSkip, 'Skip',
                showsUserInterface: true),
          ],
        ),
      ),
    );
  }

  _Job _groupJob({
    required String date,
    required String time,
    required DateTime at,
    required List<_SlotDose> doses,
    required bool sound,
    required bool vibration,
  }) {
    final lines = doses
        .map((d) =>
            '${d.med.name}${d.med.dose.isEmpty ? '' : ' — ${d.med.dose}'}')
        .toList();
    return _Job(
      id: groupNotificationId(date, time),
      title: 'Time for ${doses.length} medications',
      body: lines.join(', '),
      at: at,
      payload:
          groupPayload(date, time, doses.map((d) => d.med.id!).toList()),
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          kDoseChannelId,
          'Dose reminders',
          importance: Importance.high,
          priority: Priority.high,
          playSound: sound,
          enableVibration: vibration,
          styleInformation: InboxStyleInformation(
            lines,
            contentTitle: 'Time for ${doses.length} medications',
            summaryText: _fmt(at),
          ),
          actions: const [
            AndroidNotificationAction(kActionTakeAll, 'Take all',
                showsUserInterface: true),
            AndroidNotificationAction(kActionOpen, 'Open app',
                showsUserInterface: true),
          ],
        ),
      ),
    );
  }

  _Job _snoozeJob({
    required DoseLog log,
    required Medication med,
    required int snoozeMinutes,
    required bool sound,
    required bool vibration,
  }) {
    return _Job(
      id: snoozeNotificationId(log.id!),
      title: med.name,
      body:
          '${med.dose.isEmpty ? '' : '${med.dose} · '}snoozed $snoozeMinutes min — due now',
      at: log.scheduledAt,
      payload: dosePayload(med.id!, log.date, log.time),
      details: NotificationDetails(
        android: AndroidNotificationDetails(
          kDoseChannelId,
          'Dose reminders',
          importance: Importance.high,
          priority: Priority.high,
          playSound: sound,
          enableVibration: vibration,
          actions: const [
            AndroidNotificationAction(kActionTaken, 'Taken',
                showsUserInterface: true),
            AndroidNotificationAction(kActionSkip, 'Skip',
                showsUserInterface: true),
          ],
        ),
      ),
    );
  }

  /// Cancel every scheduled notification (used before wipe).
  Future<void> cancelAll() async {
    try {
      await plugin.cancelAll();
    } catch (_) {}
  }
}

/// One alarm to be scheduled.
class _Job {
  final int id;
  final String title;
  final String body;
  final DateTime at;
  final String? payload;
  final NotificationDetails details;
  _Job({
    required this.id,
    required this.title,
    required this.body,
    required this.at,
    required this.payload,
    required this.details,
  });
}

class _SlotDose {
  final Medication med;
  final String date;
  final String time;
  final DateTime at;
  _SlotDose(
      {required this.med,
      required this.date,
      required this.time,
      required this.at});
}
