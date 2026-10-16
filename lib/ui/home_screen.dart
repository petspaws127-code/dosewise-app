import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../meds/medication_repository.dart';
import '../notifications/notification_service.dart';
import '../settings_store.dart';
import 'medications_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'today_screen.dart';

/// Bottom nav shell: Today | Medications | Stats | Settings.
///
/// Permission UX (no dialog ambushes): notification permission is requested
/// once in onboarding and the result stored. The "Reminders are off" banner
/// opens system Settings; only when the user returns FROM system settings do
/// we re-request (already-granted returns silently, no dialog).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.repo,
    required this.settings,
  });
  final AppDatabase db;
  final MedicationRepository repo;
  final SettingsStore settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  bool _notifOk = true;
  bool _exactOk = true;
  bool _openedSystemSettings = false;
  bool _notifBannerDismissed = false;
  final _todayKey = GlobalKey<TodayScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    widget.repo.addListener(_onRepoChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_openedSystemSettings) {
      _openedSystemSettings = false;
      _rerequestAfterSettings();
    } else {
      _checkPermissions();
    }
  }

  /// Passive checks only — never prompts.
  Future<void> _checkPermissions() async {
    final exact =
        await NotificationService.instance.canScheduleExactAlarms();
    final p = await SharedPreferences.getInstance();
    final notifGranted = p.getBool('notif_granted') ?? true;
    if (!mounted) return;
    setState(() {
      _exactOk = exact;
      _notifOk = notifGranted;
    });
  }

  /// Called after the user returns from system Settings: a re-request is
  /// safe here (granted → returns true silently; permanently-denied →
  /// returns false with no dialog).
  Future<void> _rerequestAfterSettings() async {
    final granted = await NotificationService.instance
        .requestNotificationPermission();
    final p = await SharedPreferences.getInstance();
    await p.setBool('notif_granted', granted);
    await _checkPermissions();
  }

  void _markOpenedSettings() => _openedSystemSettings = true;

  void _onTab(int i) {
    setState(() => _tab = i);
    // Today must never show a stale list (e.g. after adding from Meds).
    if (i == 0) _todayKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          TodayScreen(
            key: _todayKey,
            repo: widget.repo,
            settings: widget.settings,
            onOpenStats: () => setState(() => _tab = 2),
            notifPermissionOk: _notifOk,
            exactAlarmOk: _exactOk,
            onOpenSystemSettings: _markOpenedSettings,
            notifBannerDismissed: _notifBannerDismissed,
            onDismissNotifBanner: () =>
                setState(() => _notifBannerDismissed = true),
          ),
          MedicationsScreen(
              repo: widget.repo, settings: widget.settings),
          StatsScreen(repo: widget.repo, settings: widget.settings),
          SettingsScreen(
            db: widget.db,
            repo: widget.repo,
            settings: widget.settings,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: _onTab,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Today'),
          BottomNavigationBarItem(
              icon: Icon(Icons.medication_outlined),
              activeIcon: Icon(Icons.medication),
              label: 'Meds'),
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: 'Stats'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
