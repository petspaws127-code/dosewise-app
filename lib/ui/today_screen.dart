import 'dart:math';

import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

import '../ads/ad_service.dart';
import '../db/database.dart';
import '../db/models.dart';
import '../meds/medication_repository.dart';
import '../notifications/system_settings.dart';
import '../schedule/dose_schedule.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'add_medication_screen.dart';
import 'medication_detail_screen.dart';
import 'time_fmt.dart';
import 'widgets.dart';

/// Today tab (spec §1.2): header + next-dose hero + timeline + banner.
/// Banner lives here ONLY. Interstitial fires once after the all-done card.
class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.onOpenStats,
    required this.notifPermissionOk,
    required this.exactAlarmOk,
    required this.onOpenSystemSettings,
    required this.onDismissNotifBanner,
    required this.notifBannerDismissed,
  });
  final MedicationRepository repo;
  final SettingsStore settings;
  final VoidCallback onOpenStats;
  final bool notifPermissionOk;
  final bool exactAlarmOk;
  final VoidCallback onOpenSystemSettings;
  final VoidCallback onDismissNotifBanner;
  final bool notifBannerDismissed;

  @override
  State<TodayScreen> createState() => TodayScreenState();
}

class TodayScreenState extends State<TodayScreen> {
  List<DoseOccurrence> _doses = [];
  int _streak = 0;
  bool _loading = true;
  bool _loadError = false;
  bool _interstitialAttempted = false;
  bool _bannerVisible = true;
  bool _exactBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Public: HomeScreen calls this when the tab is re-selected so Today
  /// never shows a stale list after adding from the Meds tab.
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    try {
      final doses = await widget.repo.todaysDoses();
      final streak = await widget.repo.currentStreak();
      if (!mounted) return;
      final firstLoad = _loading;
      final wasComplete = _doses.isNotEmpty && isDayComplete(_doses);
      final isComplete = isDayComplete(doses);
      setState(() {
        _doses = doses;
        _streak = streak;
        _loading = false;
        _loadError = false;
      });
      // Interstitial: only on a genuine in-session transition to
      // all-done — NEVER on app open (spec §5). The confetti burst
      // (mounted while `complete`) plays once per transition.
      if (isComplete &&
          !firstLoad &&
          !wasComplete &&
          !_interstitialAttempted) {
        _interstitialAttempted = true;
        // Post-frame so the celebration card paints first.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            AdService.instance
                .maybeShowInterstitial(InterstitialTrigger.allDone);
          }
        });
      }
      _maybePromptReview(streak);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  /// 7-day streak → one in-app review prompt, ever.
  Future<void> _maybePromptReview(int streak) async {
    if (streak < 7 || !mounted) return;
    final prompted =
        await widget.repo.dbMeta(AppDatabase.kReviewPrompted);
    if (prompted == '1') return;
    await widget.repo.dbMetaSet(AppDatabase.kReviewPrompted, '1');
    try {
      final r = InAppReview.instance;
      if (await r.isAvailable()) await r.requestReview();
    } catch (_) {
      // Review API unavailable — silent.
    }
  }

  Future<void> _openAdd() async {
    setState(() => _bannerVisible = false);
    final med = await Navigator.of(context).push<Medication>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          settings: widget.settings,
          onSaved: (m) => widget.repo.add(m),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _bannerVisible = true);
    if (med != null) {
      if (med.times.isNotEmpty) {
        final t = med.times.first.split(':');
        final formatted = formatTimeOfDay(
          TimeOfDay(hour: int.parse(t[0]), minute: int.parse(t[1])),
          widget.settings,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reminder set for $formatted')),
        );
      }
      _alarmErrorSnack();
      // Positive moment #2 for the interstitial (spec §5): right after the
      // user saves a newly added medication.
      AdService.instance
          .maybeShowInterstitial(InterstitialTrigger.medAdded);
      _refresh();
    }
  }

  /// Spec §1.3: an alarm-scheduling failure must tell the user, with Retry.
  void _alarmErrorSnack() {
    if (widget.repo.alarmError == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Couldn't set the reminder — try again"),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () async {
            final ok = await widget.repo.retryAlarms();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok
                    ? 'Reminders are set.'
                    : "Still couldn't set the reminder"),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Optimistic update: the row reacts instantly, the DB follows.
  void _optimistic(DoseOccurrence occ, DoseOccurrence Function(DoseOccurrence) f) {
    final i = _doses.indexWhere(
        (d) => d.med.id == occ.med.id && d.date == occ.date && d.time == occ.time);
    if (i < 0) return;
    setState(() => _doses[i] = f(_doses[i]));
  }

  Future<void> _take(DoseOccurrence occ) async {
    _optimistic(occ, (o) => o.copyWith(status: DoseStatus.taken));
    await widget.repo.logTaken(occ);
    _refresh();
  }

  Future<void> _skip(DoseOccurrence occ) async {
    _optimistic(occ, (o) => o.copyWith(status: DoseStatus.skipped));
    await widget.repo.logSkipped(occ);
    _refresh();
  }

  Future<void> _snooze(DoseOccurrence occ) async {
    if (occ.snoozeCount >= 3) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Snooze limit reached for this dose.')),
      );
      return;
    }
    final fireAt = DateTime.now()
        .add(Duration(minutes: widget.settings.snoozeMinutes));
    _optimistic(
        occ,
        (o) => o.copyWith(
            status: DoseStatus.snoozed,
            scheduledAt: fireAt,
            snoozeCount: o.snoozeCount + 1));
    await widget.repo.snooze(occ, minutes: widget.settings.snoozeMinutes);
    _refresh();
  }

  void _doseSheet(DoseOccurrence occ) {
    setState(() => _bannerVisible = false);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DoseWiseColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(occ.med.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              Text(
                '${occ.med.dose.isEmpty ? '' : '${occ.med.dose} · '}${formatTime(occ.scheduledAt, widget.settings)}',
                style: const TextStyle(
                    fontSize: 14, color: DoseWiseColors.muted),
              ),
              const SizedBox(height: 16),
              if (occ.status == DoseStatus.pending ||
                  occ.status == DoseStatus.snoozed) ...[
                GradientButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _take(occ);
                  },
                  child: const Text('Taken'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _snooze(occ);
                        },
                        child: Text(
                            'Snooze ${widget.settings.snoozeMinutes} min'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _skip(occ);
                        },
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MedicationDetailScreen(
                          repo: widget.repo,
                          settings: widget.settings,
                          medId: occ.med.id!,
                        ),
                      ),
                    );
                  },
                  child: const Text('Details'),
                ),
              ] else if (occ.status == DoseStatus.taken) ...[
                OutlinedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final ok = await widget.repo.undoTaken(occ);
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Too late to undo — history is locked after 10 minutes.'),
                        ),
                      );
                    }
                    _refresh();
                  },
                  child: const Text('Undo (within 10 min)'),
                ),
              ] else ...[
                Text(
                  occ.status == DoseStatus.missed
                      ? 'Missed — it happens. Tomorrow is a new day.'
                      : 'This dose was ${occ.status.name}.',
                  style: const TextStyle(
                      fontSize: 14, color: DoseWiseColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _bannerVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today'),
            Text(
              formatDayHeader(now),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: DoseWiseColors.muted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child:
                StreakChip(streak: _streak, onTap: widget.onOpenStats),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.notifPermissionOk && !widget.notifBannerDismissed)
              _warnBanner(
                'Reminders are off — tap to enable',
                SystemSettings.openNotificationSettings,
                onDismiss: widget.onDismissNotifBanner,
              ),
            if (widget.notifPermissionOk &&
                !widget.exactAlarmOk &&
                !_exactBannerDismissed)
              _warnBanner(
                'Reminders may be late — tap to fix',
                SystemSettings.requestExactAlarmPermission,
                onDismiss: () =>
                    setState(() => _exactBannerDismissed = true),
              ),
            Expanded(child: _body()),
            // Banner: Today tab only, hidden when there is nothing
            // to monetize yet (empty state) and behind sheets/dialogs.
            if (widget.repo.meds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: DoseWiseBanner(visible: _bannerVisible),
              ),
          ],
        ),
      ),
      floatingActionButton: widget.repo.meds.isNotEmpty
          ? FloatingActionButton(
              onPressed: _openAdd,
              backgroundColor: DoseWiseColors.teal,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _warnBanner(String text, Future<void> Function() onTap,
      {required VoidCallback onDismiss}) {
    return GestureDetector(
      onTap: () async {
        widget.onOpenSystemSettings();
        await onTap();
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: DoseWiseColors.amberSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 18, color: DoseWiseColors.amberDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DoseWiseColors.amberDark)),
            ),
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(16),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 16, color: DoseWiseColors.amberDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const _SkeletonList();
    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Something went wrong loading your doses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: DoseWiseColors.muted)),
              const SizedBox(height: 12),
              GradientButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _loadError = false;
                  });
                  _refresh();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (widget.repo.meds.isEmpty) {
      return EmptyState(
        message:
            'Add your first medication or vitamin — it takes 30 seconds.',
        ctaLabel: 'Add your first medication',
        onCta: _openAdd,
      );
    }
    final complete = isDayComplete(_doses);
    final next = _doses.where((d) =>
        (d.status == DoseStatus.pending ||
            d.status == DoseStatus.snoozed) &&
        d.scheduledAt.isAfter(
            DateTime.now().subtract(const Duration(minutes: 1))));
    final nextDose = next.isEmpty ? null : next.first;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (complete)
                _doneCard()
              else if (nextDose != null)
                _heroCard(nextDose),
              const SizedBox(height: 4),
              const SectionLabel("Today's doses"),
              for (final d in _doses) _doseRow(d),
            ],
          ),
        ),
        // Confetti mounts on the transition to complete, plays its
        // 1.4s burst once, then sits invisible (alpha 0 at t=1).
        if (complete)
          const Positioned.fill(
            child: IgnorePointer(child: _ConfettiBurst()),
          ),
      ],
    );
  }

  Widget _doneCard() {
    return DepthCard(
      child: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          const Text('All done for today',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$_streak-day streak — keep it going',
              style: const TextStyle(
                  fontSize: 13, color: DoseWiseColors.muted)),
        ],
      ),
    );
  }

  /// Teal-gradient hero (mockup v3 .card-hero): diagonal #13A184 → #08463E,
  /// deep glow, white Taken button, ghost Snooze, muted Skip.
  Widget _heroCard(DoseOccurrence occ) {
    // All meds sharing this exact slot (spec: "med name(s)").
    final slotMates = _doses
        .where((d) =>
            d.date == occ.date &&
            d.time == occ.time &&
            (d.status == DoseStatus.pending ||
                d.status == DoseStatus.snoozed))
        .map((d) => d.med.name)
        .toSet()
        .join(', ');
    final radius = BorderRadius.circular(16);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13A184), Color(0xFF08463E)],
        ),
        boxShadow: const [
          // .card-hero: 0 20px 42px rgba(14,124,107,.45)
          BoxShadow(
            color: Color(0x730E7C6B),
            blurRadius: 42,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            const _HeroTopHighlight(),
            const _HeroBottomShade(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEXT DOSE · ${countdownCopy(occ.scheduledAt, widget.settings).toUpperCase()}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Color(0xFFBDE8DB)),
                  ),
                  const SizedBox(height: 6),
                  Text(slotMates,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(
                    '${occ.med.dose.isEmpty ? '' : '${occ.med.dose} · '}${formatTime(occ.scheduledAt, widget.settings)}',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFFD8F0E8)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroTakenButton(
                          onPressed: () => _take(occ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _HeroGhostButton(
                          onPressed: () => _snooze(occ),
                          label: 'Snooze',
                        ),
                      ),
                      TextButton(
                        onPressed: () => _skip(occ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFD8F0E8),
                        ),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doseRow(DoseOccurrence occ) {
    return DepthCard(
      soft: true,
      onTap: () => _doseSheet(occ),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 64),
                  child: Text(
                    formatTime(occ.scheduledAt, widget.settings),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DoseWiseColors.muted),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(occ.med.name,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    if (occ.med.dose.isNotEmpty)
                      Text(occ.med.dose,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: DoseWiseColors.muted)),
                  ],
                ),
              ),
              StatusPill(status: occ.status),
            ],
          ),
    );
  }
}

/// Skeleton placeholder rows while Today loads (spec: ≤300ms skeleton).
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (var i = 0; i < 4; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 14,
                    decoration: BoxDecoration(
                      color: DoseWiseColors.line,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 15,
                          width: 140,
                          decoration: BoxDecoration(
                            color: DoseWiseColors.line,
                            borderRadius:
                                BorderRadius.circular(7),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: 90,
                          decoration: BoxDecoration(
                            color: DoseWiseColors.line,
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Subtle confetti burst (≤1.5s) over the all-done card (spec §1.2).
class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();

  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _parts;

  @override
  void initState() {
    super.initState();
    final rnd = Random(42);
    const colors = [
      DoseWiseColors.teal,
      DoseWiseColors.amber,
      DoseWiseColors.tealDark,
      Color(0xFFE8836B),
    ];
    _parts = List.generate(
      42,
      (_) => _Particle(
        x: rnd.nextDouble(),
        y: rnd.nextDouble() * 0.4,
        vx: (rnd.nextDouble() - 0.5) * 0.35,
        vy: 0.45 + rnd.nextDouble() * 0.5,
        size: 4 + rnd.nextDouble() * 5,
        color: colors[rnd.nextInt(colors.length)],
        rot: rnd.nextDouble() * 6.28,
      ),
    );
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _ConfettiPainter(_parts, _ctrl.value),
      ),
    );
  }
}

class _Particle {
  double x, y, vx, vy, size, rot;
  final Color color;
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rot,
  });
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.parts, this.t);
  final List<_Particle> parts;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      final x = (p.x + p.vx * t) * size.width;
      final y = (p.y + p.vy * t) * size.height;
      final paint = Paint()
        ..color = p.color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + t * 6);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.6),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.t != t;
}

/// Hero top light-catch: `inset 0 1px 0 rgba(255,255,255,.3)`.
class _HeroTopHighlight extends StatelessWidget {
  const _HeroTopHighlight();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 14,
      right: 14,
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Hero bottom inner shade: `inset 0 -2px 6px rgba(0,0,0,.12)`.
class _HeroBottomShade extends StatelessWidget {
  const _HeroBottomShade();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 12,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.12),
            ],
          ),
        ),
      ),
    );
  }
}

/// White Taken button on the teal hero (mockup .btn-take).
class _HeroTakenButton extends StatelessWidget {
  const _HeroTakenButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000), // rgba(0,0,0,.18)
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: const Center(
            child: Text('Taken',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0A5C51))),
          ),
        ),
      ),
    );
  }
}

/// Ghost Snooze button on the teal hero.
class _HeroGhostButton extends StatelessWidget {
  const _HeroGhostButton(
      {required this.onPressed, required this.label});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
