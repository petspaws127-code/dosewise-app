import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import '../db/models.dart';
import '../meds/medication_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/system_settings.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'add_medication_screen.dart';
import 'widgets.dart';

/// First-launch flow (spec §1.1, §3):
/// welcome → notification rationale → exact-alarm rationale → add first med.
/// Never a dead end on denial.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.db,
    required this.repo,
    required this.settings,
    required this.onDone,
  });
  final AppDatabase db;
  final MedicationRepository repo;
  final SettingsStore settings;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  Future<void> _finish() async {
    await widget.db.metaSet(AppDatabase.kOnboardingDone, '1');
    widget.onDone();
  }

  Future<void> _askNotifications() async {
    final granted = await NotificationService.instance
        .requestNotificationPermission();
    (await SharedPreferences.getInstance())
        .setBool('notif_granted', granted);
    setState(() => _step = 2);
  }

  /// Skip stores an explicit denial — the "Reminders are off" banner must
  /// show (a missing key must never read as "granted").
  Future<void> _skipNotifications() async {
    (await SharedPreferences.getInstance())
        .setBool('notif_granted', false);
    setState(() => _step = 2);
  }

  Future<void> _askExactAlarm() async {
    final ok =
        await NotificationService.instance.canScheduleExactAlarms();
    if (!ok) {
      await SystemSettings.requestExactAlarmPermission();
    }
    // Proceed regardless; a persistent banner covers denial (spec §1.1).
    setState(() => _step = 3);
  }

  Future<void> _saveFirstMed(Medication med) async {
    await widget.repo.add(med);
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_step) {
            0 => _welcome(),
            1 => _rationale(
                  title: 'We need notifications',
                  body:
                      'We need notifications to remind you — that\'s the whole app.',
                  cta: 'Allow notifications',
                  onCta: _askNotifications,
                  onSkip: _skipNotifications,
                ),
            2 => _rationale(
                  title: 'Ring exactly on time',
                  body:
                      'Your phone may delay alarms to save battery. Allow exact alarms so reminders ring on time.',
                  cta: 'Allow exact alarms',
                  onCta: _askExactAlarm,
                  onSkip: () => setState(() => _step = 3),
                ),
            _ => AddMedicationScreen(
                settings: widget.settings,
                autofocusName: true,
                onSaved: _saveFirstMed,
                // In onboarding the X means "skip for now" → enter the
                // app, not pop the route (which would exit to nothing).
                onClose: _finish,
              ),
          },
        ),
      ),
    );
  }

  /// Scroll-safe: at 200% font scale on a small phone the content
  /// scrolls instead of overflowing and pushing the CTA out of reach.
  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }

  Widget _welcome() {
    return _scrollable(
      Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Spacer(),
          const DoseWiseLogo(size: 88),
          const SizedBox(height: 20),
          const Text(
            'DoseWise',
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: DoseWiseColors.ink,
                letterSpacing: -0.4),
          ),
          const SizedBox(height: 8),
          const Text(
            'Free forever. Reminders that never miss.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: DoseWiseColors.teal),
          ),
          const SizedBox(height: 20),
          _check('100% free — no premium, no paywall, ever'),
          _check('Alarms that ring on time, every time'),
          _check('Your data never leaves your phone'),
          const Spacer(),
          GradientButton(
            onPressed: () => setState(() => _step = 1),
            child: const Text('Get started'),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => _disclaimerSheet(),
            child: const Text(
              'Reminder tool only — not medical advice. Learn more',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11.5, color: DoseWiseColors.muted),
            ),
          ),
          const SizedBox(height: 4),
          const Text('No account needed',
              style:
                  TextStyle(fontSize: 11.5, color: DoseWiseColors.faint)),
        ],
      ),
      ),
    );
  }

  Widget _check(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.check_circle,
              size: 18, color: DoseWiseColors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14, color: DoseWiseColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _rationale({
    required String title,
    required String body,
    required String cta,
    required VoidCallback onCta,
    required VoidCallback onSkip,
  }) {
    return _scrollable(
      Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Spacer(),
            const Icon(Icons.notifications_active,
                size: 56, color: DoseWiseColors.teal),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: DoseWiseColors.ink)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: DoseWiseColors.muted)),
            const Spacer(),
            GradientButton(onPressed: onCta, child: Text(cta)),
            const SizedBox(height: 8),
            TextButton(
                onPressed: onSkip,
                child: const Text('Skip for now')),
          ],
        ),
      ),
    );
  }

  void _disclaimerSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
}
