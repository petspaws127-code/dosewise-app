import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../ads/ad_service.dart';
import '../db/models.dart';
import '../meds/medication_repository.dart';
import '../reports/doctor_report.dart';
import '../schedule/dose_schedule.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'time_fmt.dart';
import 'widgets.dart';

/// Stats tab (spec §1.5): streak hero, weekly ring, 7-day bars,
/// per-med adherence, and the rewarded opt-ins (doctor PDF, insights).
class StatsScreen extends StatefulWidget {
  const StatsScreen(
      {super.key, required this.repo, required this.settings});
  final MedicationRepository repo;
  final SettingsStore settings;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _streak = 0;
  double? _week;
  List<DayAdherence> _bars = [];
  List<MedAdherence> _meds = [];
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final streak = await widget.repo.currentStreak();
    final week = await widget.repo
        .weekAdherence(weekStart: widget.settings.firstDayOfWeek);
    final bars = await widget.repo.weekBars();
    final meds = await widget.repo.medAdherence30();
    if (!mounted) return;
    setState(() {
      _streak = streak;
      _week = week;
      _bars = bars;
      _meds = meds;
      _loading = false;
    });
  }

  /// Rewarded opt-in dialog. The report generates even if the ad fails
  /// or is dismissed — never punish the user (spec §5). The busy flag
  /// always resets via try/finally, even if generation throws.
  Future<void> _rewardedAction({
    required String title,
    required Future<void> Function() generate,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text(
            'Watch a short ad to generate — optional, the app stays free.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Watch ad')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _generating = true);
    try {
      await AdService.instance.showRewardedOrElse(() async {
        await generate();
      });
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _doctorReport() => _rewardedAction(
        title: 'Doctor report',
        generate: () async {
          final pdf = await DoctorReport.build(
            meds: widget.repo.meds,
            adherence30: _meds,
            streak: _streak,
            weekPercent: _week,
          );
          final dir = await getTemporaryDirectory();
          final file = File(
              '${dir.path}/dosewise-report-${dateKey(DateTime.now())}.pdf');
          await file.writeAsBytes(pdf);
          await SharePlus.instance.share(ShareParams(
            files: [XFile(file.path)],
            text: 'My DoseWise adherence report',
          ));
        },
      );

  Future<void> _monthlyInsights() => _rewardedAction(
        title: 'Monthly insights',
        generate: () async {
          final history =
              await widget.repo.statusHistory(days: 31);
          final text = _insightsText(history);
          if (!mounted) return;
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Your month'),
              content: Text(text,
                  style: const TextStyle(height: 1.5)),
              actions: [
                FilledButton(
                    onPressed: () =>
                        Navigator.of(context).pop(),
                    child: const Text('Done')),
              ],
            ),
          );
        },
      );

  String _insightsText(
      Map<String, Map<String, DoseStatus>> history) {
    final byWeekday = <int, List<int>>{}; // weekday -> [taken, total]
    String? bestDay;
    double best = -1;
    String? worstDay;
    double worst = 101;
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (var d = 0; d < 30; d++) {
      final day = DateTime.now().subtract(Duration(days: d));
      final date = dateKey(
          DateTime(day.year, day.month, day.day));
      final st = history[date] ?? {};
      var taken = 0;
      var total = 0;
      for (final s in st.values) {
        total++;
        if (s == DoseStatus.taken) taken++;
      }
      if (total == 0) continue;
      final e = byWeekday.putIfAbsent(day.weekday, () => [0, 0]);
      e[0] += taken;
      e[1] += total;
    }
    for (final wd in byWeekday.keys) {
      final e = byWeekday[wd]!;
      final pct = e[1] == 0 ? 0.0 : e[0] / e[1] * 100;
      if (pct > best) {
        best = pct;
        bestDay = names[wd - 1];
      }
      if (pct < worst) {
        worst = pct;
        worstDay = names[wd - 1];
      }
    }
    final buf = StringBuffer();
    if (bestDay != null) {
      buf.writeln(
          'Your strongest day: $bestDay (${best.toStringAsFixed(0)}% taken).');
      buf.writeln(
          'Your toughest day: $worstDay (${worst.toStringAsFixed(0)}% taken).');
      buf.writeln();
    }
    if (_meds.isNotEmpty) {
      final w = _meds.first;
      buf.writeln(
          'Needs the most love: ${w.med.name} (${w.percent.toStringAsFixed(0)}% over 30 days).');
      buf.writeln();
    }
    buf.write(
        'Small tip: doses tied to an existing habit (morning coffee, brushing teeth) get missed the least.');
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your progress')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _streakCard(),
                    const SizedBox(height: 12),
                    _weekCard(),
                    const SizedBox(height: 12),
                    _medList(),
                    const SizedBox(height: 12),
                    _reportButtons(),
                    if (_generating)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(
                            child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _streakCard() {
    return DepthCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const FlameGlyph(size: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_streak-day streak',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  const Text(
                    'Days with every dose taken or skipped on purpose.',
                    style: TextStyle(
                        fontSize: 12,
                        color: DoseWiseColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekCard() {
    final pct = _week;
    final maxBar = _bars.isEmpty
        ? 1
        : _bars.map((b) => b.total).fold<int>(1, (a, b) => a > b ? a : b);
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return DepthCard(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('This week'),
            Row(
              children: [
                _ring(pct),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(
                    pct == null
                        ? 'No doses scheduled yet — your progress will appear here.'
                        : '${pct.toStringAsFixed(0)}% of doses taken this week.',
                    style: const TextStyle(
                        fontSize: 14,
                        color: DoseWiseColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in _bars)
                  GestureDetector(
                    onTap: () => _dayDetail(b.date),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 90,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Stacked: taken (teal) + missed (red).
                              if (b.missed > 0)
                                Container(
                                  width: 26,
                                  height: 90 *
                                      (b.missed /
                                          maxBar.clamp(1, 1 << 30)),
                                  decoration: const BoxDecoration(
                                    color: DoseWiseColors.red,
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(6)),
                                  ),
                                ),
                              Container(
                                width: 26,
                                height: 90 *
                                    (b.total == 0
                                        ? 0.06
                                        : b.taken /
                                            maxBar.clamp(1, 1 << 30)),
                                decoration: BoxDecoration(
                                  color: b.total == 0
                                      ? DoseWiseColors.line
                                      : DoseWiseColors.teal,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(6),
                                    bottom: Radius.circular(
                                        b.missed > 0 ? 0 : 6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(dayNames[b.date.weekday - 1],
                            style: const TextStyle(
                                fontSize: 10,
                                color: DoseWiseColors.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Day detail bottom sheet (spec §1.5): every dose of the tapped day.
  Future<void> _dayDetail(DateTime day) async {
    final doses = await widget.repo.dosesForDate(day);
    if (!mounted) return;
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
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(formatDayHeader(day),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (doses.isEmpty)
                      const Text('No doses scheduled.',
                          style: TextStyle(
                              color: DoseWiseColors.muted)),
                    for (final d in doses)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(d.med.name,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                    formatTime(d.scheduledAt,
                                        widget.settings),
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color:
                                            DoseWiseColors.muted),
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(status: d.status),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ring(double? pct) {
    return SizedBox(
      width: 96,
      height: 96,
      child: CustomPaint(
        painter: _RingPainter(pct == null ? 0 : pct / 100),
        child: Center(
          child: Text(
            pct == null ? '—' : '${pct.toStringAsFixed(0)}%',
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _medList() {
    if (_meds.isEmpty) {
      return const DepthCard(
        soft: true,
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            'Your progress will appear here after your first day.',
            style: TextStyle(color: DoseWiseColors.muted),
          ),
        ),
      );
    }
    return DepthCard(
      soft: true,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('30-day adherence'),
            for (final m in _meds)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(m.med.name,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: m.percent / 100,
                              minHeight: 8,
                              backgroundColor:
                                  DoseWiseColors.line,
                              valueColor:
                                  const AlwaysStoppedAnimation(
                                      DoseWiseColors.teal),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        '${m.percent.toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reportButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _generating ? null : _doctorReport,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Adherence report (PDF) for your doctor'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _generating ? null : _monthlyInsights,
          icon: const Icon(Icons.insights_outlined),
          label: const Text('Monthly insights'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Optional: a short ad supports this free app.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: DoseWiseColors.faint),
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = DoseWiseColors.line
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..color = DoseWiseColors.teal
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    canvas.drawCircle(c, r, bg);
    // Soft drop shadow under the progress arc (mockup v3 depth).
    final shadow = Paint()
      ..color = DoseWiseColors.teal.withValues(alpha: 0.35)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final arcRect = Rect.fromCircle(center: c, radius: r);
    const start = -3.14159 / 2;
    final sweep = 2 * 3.14159 * frac.clamp(0.0, 1.0);
    if (sweep > 0) {
      canvas.save();
      canvas.translate(0, 3);
      canvas.drawArc(arcRect, start, sweep, false, shadow);
      canvas.restore();
    }
    canvas.drawArc(arcRect, start, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.frac != frac;
}
