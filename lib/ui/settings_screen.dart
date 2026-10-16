import 'dart:io';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../ads/ad_service.dart';
import '../db/database.dart';
import '../db/models.dart';
import '../meds/medication_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/system_settings.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'widgets.dart';

/// Settings (spec §1.6): reminders, display, battery guidance, privacy,
/// disclaimer, about, danger zone. No premium row exists — by design.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.db,
    required this.repo,
    required this.settings,
  });
  final AppDatabase db;
  final MedicationRepository repo;
  final SettingsStore settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;
  bool _exactAlarmDenied = false;

  @override
  void initState() {
    super.initState();
    _checkExactAlarm();
  }

  Future<void> _checkExactAlarm() async {
    final ok =
        await NotificationService.instance.canScheduleExactAlarms();
    if (mounted) setState(() => _exactAlarmDenied = !ok);
  }

  Future<void> _rateApp() async {
    try {
      final r = InAppReview.instance;
      if (await r.isAvailable()) {
        await r.requestReview();
      }
    } catch (_) {
      // Review API unavailable — silent.
    }
  }

  Future<void> _exportCsv() => _doExport();

  Future<void> _doExport() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Export my data (CSV)'),
        content: const Text(
            'Watch a short ad to export your history — optional, the app stays free.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(true),
              child: const Text('Watch ad')),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _exporting = true);
    try {
      await AdService.instance.showRewardedOrElse(() async {
        final buf = StringBuffer('medication,dose,date,time,status\n');
        for (final med in widget.repo.meds) {
          if (med.id == null) continue;
          final logs = await widget.repo.logsForMed(med.id!);
          for (final l in logs) {
            buf.write(
                '"${med.name}","${med.dose}",${l.date},${l.time},${l.status.name}\n');
          }
        }
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/dosewise-export-${dateKey(DateTime.now())}.csv');
        await file.writeAsString(buf.toString());
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path)],
          text: 'My DoseWise history',
        ));
      });
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteAll() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all my data?'),
        content: const Text(
            'This removes every medication, every log, and cancels all reminders. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(false),
              child: const Text('Keep my data')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: DoseWiseColors.red),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Are you really sure?'),
        content: const Text(
            'Last chance — everything will be gone.'),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(false),
              child: const Text('Keep my data')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
                backgroundColor: DoseWiseColors.red),
            child: const Text('Yes, delete everything'),
          ),
        ],
      ),
    );
    if (second == true) {
      await NotificationService.instance.cancelAll();
      await widget.db.wipeAll();
      await widget.repo.load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('All data deleted. Fresh start.')));
      }
    }
  }

  void _disclaimer() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'This app is a reminder tool only. It does not provide medical '
          'advice, diagnosis, or treatment. Always follow your doctor\'s '
          'instructions. If you miss a dose, ask your doctor or pharmacist '
          'what to do — don\'t guess.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: s,
          builder: (_, __) => ListView(
            padding:
                const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const SectionLabel('Reminders'),
              if (_exactAlarmDenied)
                _tapRow(
                  'Reminders may be late — tap to fix',
                  '',
                  () => SystemSettings.requestExactAlarmPermission(),
                ),
              _switchRow(
                'Sound',
                s.soundOn,
                (v) => s.setSound(v),
              ),
              _switchRow(
                'Vibration',
                s.vibrationOn,
                (v) => s.setVibration(v),
              ),
              _tapRow(
                'Snooze length',
                '${s.snoozeMinutes} min',
                () => _pickSnooze(),
              ),
              _tapRow(
                'Battery optimization',
                'Keep reminders reliable',
                () => _batteryGuide(),
              ),
              const SectionLabel('Display'),
              _tapRow(
                'Time format',
                _timeFormatLabel(s.timeFormat),
                () => _pickTimeFormat(),
              ),
              _tapRow(
                'First day of week',
                s.firstDayOfWeek == 7 ? 'Sunday' : 'Monday',
                () => _pickFirstDay(),
              ),
              const SectionLabel('Privacy'),
              DepthCard(
                soft: true,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Your data never leaves this phone. No account, no cloud, no analytics.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
              const SectionLabel('Data'),
              _tapRow(
                'Export my data (CSV)',
                _exporting ? 'Working…' : 'Optional short ad',
                _exporting ? () {} : _exportCsv,
              ),
              const SectionLabel('About'),
              DepthCard(
                soft: true,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Free forever. No premium, no paywall.',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DoseWiseColors.tealDark),
                  ),
                ),
              ),
              _tapRow('Medical disclaimer', '', _disclaimer),
              _tapRow('Rate the app', '', _rateApp),
              _tapRow('Version', '1.0.0+1', () {}),
              const SectionLabel('Danger zone'),
              DepthCard(
                soft: true,
                onTap: _deleteAll,
                child: const Text(
                  'Delete all my data',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DoseWiseColors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchRow(
      String title, bool value, ValueChanged<bool> onChanged) {
    return DepthCard(
      soft: true,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SwitchListTile(
        title: Text(title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
        value: value,
        activeThumbColor: DoseWiseColors.teal,
        onChanged: onChanged,
      ),
    );
  }

  Widget _tapRow(String title, String trailing, VoidCallback onTap) {
    return DepthCard(
      soft: true,
      onTap: onTap,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
              if (trailing.isNotEmpty)
                Flexible(
                  child: Text(trailing,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          color: DoseWiseColors.muted)),
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: DoseWiseColors.faint),
            ],
          ),
    );
  }

  String _timeFormatLabel(String v) => switch (v) {
        '12' => '12-hour',
        '24' => '24-hour',
        _ => 'System default',
      };

  Future<void> _pickSnooze() async {
    final v = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Snooze length'),
        children: [
          for (final m in [15, 30, 60])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text('$m minutes'),
            ),
        ],
      ),
    );
    if (v != null) widget.settings.setSnoozeMinutes(v);
  }

  Future<void> _pickTimeFormat() async {
    final v = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Time format'),
        children: [
          for (final e in [
            ('system', 'System default'),
            ('12', '12-hour'),
            ('24', '24-hour'),
          ])
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(context).pop(e.$1),
              child: Text(e.$2),
            ),
        ],
      ),
    );
    if (v != null) widget.settings.setTimeFormat(v);
  }

  Future<void> _pickFirstDay() async {
    final v = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('First day of week'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(7),
            child: const Text('Sunday'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(1),
            child: const Text('Monday'),
          ),
        ],
      ),
    );
    if (v != null) widget.settings.setFirstDayOfWeek(v);
  }

  void _batteryGuide() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Keep reminders reliable',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text(
                'Some phones pause apps in the background. These 3 steps keep your reminders on time:\n\n'
                '1. Open Settings → Apps → DoseWise → Battery\n'
                '2. Choose "Unrestricted"\n'
                '3. Done — your alarms will ring even when the app is closed.',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  SystemSettings.openAppInfo();
                },
                child: const Text('Open app settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
