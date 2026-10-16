import 'package:flutter/material.dart';

import '../ads/ad_service.dart';
import '../db/models.dart';
import '../meds/medication_repository.dart';
import '../schedule/dose_schedule.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'add_medication_screen.dart';
import 'medication_detail_screen.dart';
import 'time_fmt.dart';
import 'widgets.dart';

/// Medications tab (spec §1.4): cabinet list with refill badges.
/// Gestures: swipe right → log dose now; swipe left → edit/delete;
/// long-press → same menu (accessibility).
class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen(
      {super.key, required this.repo, required this.settings});
  final MedicationRepository repo;
  final SettingsStore settings;

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  String _query = '';

  Future<void> _openAdd() async {
    final med = await Navigator.of(context).push<Medication>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          settings: widget.settings,
          onSaved: (m) => widget.repo.add(m),
        ),
      ),
    );
    if (med != null && mounted) {
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
      if (widget.repo.alarmError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                const Text("Couldn't set the reminder — try again"),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => widget.repo.retryAlarms(),
            ),
          ),
        );
      }
      // Positive moment #2 for the interstitial (spec §5) — same as
      // Today's add flow.
      AdService.instance
          .maybeShowInterstitial(InterstitialTrigger.medAdded);
    }
  }

  Future<void> _openDetail(Medication med) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MedicationDetailScreen(
          repo: widget.repo,
          settings: widget.settings,
          medId: med.id!,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openEdit(Medication med) async {
    await Navigator.of(context).push<Medication>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          settings: widget.settings,
          existing: med,
          onSaved: (m) => widget.repo.update(m),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  /// Swipe right → log the next pending dose now (spec §1.4).
  Future<void> _logDoseNow(Medication med) async {
    final doses = await widget.repo.todaysDoses();
    final pending = doses.where((d) =>
        d.med.id == med.id &&
        (d.status == DoseStatus.pending ||
            d.status == DoseStatus.snoozed));
    if (pending.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No pending dose for ${med.name} today.')),
      );
      return;
    }
    final occ = pending.first;
    final ok = await widget.repo.logTaken(occ);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? '${med.name} logged.'
              : '${med.name} was already logged.')),
    );
    setState(() {});
  }

  /// Swipe left / long-press → Edit / Delete menu.
  Future<void> _editDeleteSheet(Medication med) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Edit ${med.name}'),
              onTap: () => Navigator.of(context).pop('edit'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: DoseWiseColors.red),
              title: const Text('Delete',
                  style: TextStyle(color: DoseWiseColors.red)),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'edit' && mounted) {
      await _openEdit(med);
    } else if (action == 'delete' && mounted) {
      if (await _confirmDelete(med) && mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final meds = widget.repo.meds;
    final filtered = _query.isEmpty
        ? meds
        : meds
            .where((m) =>
                m.name.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openAdd,
            tooltip: 'Add medication',
          ),
        ],
      ),
      body: SafeArea(
        child: meds.isEmpty
            ? EmptyState(
                message: 'Your cabinet is empty.',
                ctaLabel: 'Add your first medication',
                onCta: _openAdd,
              )
            : Column(
                children: [
                  if (meds.length > 5)
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search medications',
                          prefixIcon:
                              const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: DoseWiseColors.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: DoseWiseColors.line),
                          ),
                        ),
                        onChanged: (v) =>
                            setState(() => _query = v),
                      ),
                    ),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No matches.',
                                style: TextStyle(
                                    color: DoseWiseColors.muted)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                16, 4, 16, 24),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) =>
                                _medCard(filtered[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _medCard(Medication med) {
    final timesSummary =
        '${med.times.map((t) => _fmtSlot(t)).join(', ')} · ${_daysSummary(med.days)}';
    final supply = daysOfSupply(med);
    return Dismissible(
      key: ValueKey('med-${med.id}'),
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: DoseWiseColors.tealSoft,
          borderRadius: BorderRadius.circular(16),
        ),
        child:
            const Icon(Icons.check, color: DoseWiseColors.tealDark),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: DoseWiseColors.line,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.more_horiz,
            color: DoseWiseColors.muted),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          // Swipe right → log dose now (spec §1.4).
          await _logDoseNow(med);
        } else {
          // Swipe left → edit/delete menu.
          await _editDeleteSheet(med);
        }
        return false; // never dismiss the card itself
      },
      child: Card(
        child: InkWell(
          onTap: () => _openDetail(med),
          onLongPress: () => _editDeleteSheet(med),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                PillGlyph(
                  size: 40,
                  color: med.type == MedType.vitamin
                      ? DoseWiseColors.amber
                      : DoseWiseColors.teal,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              med.name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (med.paused)
                            const Text('Paused',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: DoseWiseColors.faint)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${med.dose.isEmpty ? '' : '${med.dose} · '}$timesSummary',
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: DoseWiseColors.muted),
                      ),
                      if (supply != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: supply <= 7
                                ? DoseWiseColors.amberSoft
                                : DoseWiseColors.tealSoft,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Text(
                            supply <= 7
                                ? '${med.pillsRemaining} left — refill soon'
                                : '${med.pillsRemaining} pills left',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: supply <= 7
                                    ? DoseWiseColors.amberDark
                                    : DoseWiseColors.tealDark),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 7-day adherence mini-ring (spec §1.4 list layout).
                _MiniRing(
                    future: widget.repo.medAdherence7(med.id!)),
                const Icon(Icons.chevron_right,
                    color: DoseWiseColors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtSlot(String hhmm) {
    final p = hhmm.split(':');
    return formatTime(
        DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])),
        widget.settings);
  }

  String _daysSummary(List<int> days) {
    if (days.length == 7) return 'Daily';
    if (days.length == 5 &&
        [1, 2, 3, 4, 5].every(days.contains)) {
      return 'Weekdays';
    }
    const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return days.map((d) => names[d - 1]).join(' ');
  }

  Future<bool> _confirmDelete(Medication med) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${med.name}?'),
        content: const Text(
            'Reminders stop. Your history is kept for honest stats.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: DoseWiseColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repo.delete(med.id!);
      return true;
    }
    return false;
  }
}

/// 7-day adherence mini-ring for a medication card.
class _MiniRing extends StatelessWidget {
  const _MiniRing({required this.future});
  final Future<double?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double?>(
      future: future,
      builder: (_, snap) {
        final pct = snap.data;
        return SizedBox(
          width: 40,
          height: 40,
          child: CustomPaint(
            painter: _MiniRingPainter(
                pct == null ? 0 : (pct / 100).clamp(0.0, 1.0)),
            child: Center(
              child: Text(
                pct == null ? '—' : '${pct.round()}',
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: DoseWiseColors.tealDark),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniRingPainter extends CustomPainter {
  _MiniRingPainter(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = DoseWiseColors.line
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final fg = Paint()
      ..color = DoseWiseColors.teal
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 3;
    canvas.drawCircle(c, r, bg);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        -3.14159 / 2, 2 * 3.14159 * frac, false, fg);
  }

  @override
  bool shouldRepaint(covariant _MiniRingPainter old) =>
      old.frac != frac;
}
