import 'package:flutter/material.dart';

import '../db/models.dart';
import '../meds/medication_repository.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'add_medication_screen.dart';
import 'time_fmt.dart';
import 'widgets.dart';

/// Medication detail (spec §1.4): schedule, refill, 30-day strip,
/// Edit / Pause / Delete. History is kept on delete (stats honesty).
class MedicationDetailScreen extends StatefulWidget {
  const MedicationDetailScreen({
    super.key,
    required this.repo,
    required this.settings,
    required this.medId,
  });
  final MedicationRepository repo;
  final SettingsStore settings;
  final int medId;

  @override
  State<MedicationDetailScreen> createState() =>
      _MedicationDetailScreenState();
}

class _MedicationDetailScreenState
    extends State<MedicationDetailScreen> {
  Medication? _med;
  List<DoseLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final med = widget.repo.meds
        .where((m) => m.id == widget.medId)
        .firstOrNull;
    final logs = await widget.repo.logsForMed(widget.medId);
    if (!mounted) return;
    setState(() {
      _med = med;
      _logs = logs;
    });
  }

  Future<void> _edit() async {
    final med = _med;
    if (med == null) return;
    await Navigator.of(context).push<Medication>(
      MaterialPageRoute(
        builder: (_) => AddMedicationScreen(
          settings: widget.settings,
          existing: med,
          onSaved: (m) => widget.repo.update(m),
        ),
      ),
    );
    await widget.repo.load();
    _load();
  }

  Future<void> _togglePause() async {
    final med = _med;
    if (med == null) return;
    await widget.repo.setPaused(med.id!, !med.paused);
    await widget.repo.load();
    _load();
  }

  Future<void> _delete() async {
    final med = _med;
    if (med == null) return;
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
    if (ok == true && mounted) {
      await widget.repo.delete(med.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _markRefilled() async {
    final med = _med;
    if (med == null) return;
    final ctrl = TextEditingController(
        text: med.pillsRemaining?.toString() ?? '30');
    final count = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mark refilled'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Pills in the new bottle'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context)
                .pop(int.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (count != null && count > 0) {
      await widget.repo.markRefilled(med.id!, count);
      await widget.repo.load();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = _med;
    return Scaffold(
      appBar: AppBar(
        title: Text(med?.name ?? 'Medication'),
        actions: [
          IconButton(
              icon: const Icon(Icons.edit),
              onPressed: med == null ? null : _edit),
        ],
      ),
      body: med == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(med),
                  const SizedBox(height: 12),
                  _scheduleCard(med),
                  const SizedBox(height: 12),
                  _refillCard(med),
                  const SizedBox(height: 12),
                  _historyCard(),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _togglePause,
                    icon: Icon(med.paused
                        ? Icons.play_arrow
                        : Icons.pause),
                    label: Text(med.paused
                        ? 'Resume reminders'
                        : 'Pause reminders'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DoseWiseColors.red,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(Medication med) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            PillGlyph(
              size: 48,
              color: med.type == MedType.vitamin
                  ? DoseWiseColors.amber
                  : DoseWiseColors.teal,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(med.name,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800)),
                  if (med.dose.isNotEmpty)
                    Text(med.dose,
                        style: const TextStyle(
                            fontSize: 14,
                            color: DoseWiseColors.muted)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: med.type == MedType.vitamin
                          ? DoseWiseColors.amberSoft
                          : DoseWiseColors.tealSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      med.type == MedType.vitamin
                          ? 'Vitamin / Supplement'
                          : 'Medication',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: med.type == MedType.vitamin
                              ? DoseWiseColors.amberDark
                              : DoseWiseColors.tealDark),
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

  Widget _scheduleCard(Medication med) {
    const dayNames = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Schedule'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in med.times)
                  InkWell(
                    onTap: _edit,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: DoseWiseColors.tealSofter,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _fmtSlot(t),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: DoseWiseColors.tealDark),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  InkWell(
                    onTap: _edit,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: med.days.contains(d)
                            ? DoseWiseColors.teal
                            : DoseWiseColors.tealSofter
                                .withValues(alpha: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        dayNames[d - 1],
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: med.days.contains(d)
                              ? Colors.white
                              : DoseWiseColors.faint,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (med.paused) ...[
              const SizedBox(height: 10),
              const Text('Reminders are paused.',
                  style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: DoseWiseColors.muted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _refillCard(Medication med) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Refill'),
            if (med.pillsRemaining == null)
              const Text(
                'Refill tracking is off. Edit to add pills in bottle.',
                style: TextStyle(
                    fontSize: 13, color: DoseWiseColors.muted),
              )
            else ...[
              Text('${med.pillsRemaining} pills left',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _markRefilled,
                child: const Text('Mark refilled'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyCard() {
    // Last 30 days strip: one cell per day, colored by outcome.
    final now = DateTime.now();
    final cells = <Widget>[];
    for (var d = 29; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: d));
      final key =
          '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final dayLogs =
          _logs.where((l) => l.date == key).toList();
      Color c;
      if (dayLogs.isEmpty) {
        c = DoseWiseColors.line;
      } else if (dayLogs
          .every((l) => l.status == DoseStatus.taken || l.status == DoseStatus.skipped)) {
        c = DoseWiseColors.teal;
      } else if (dayLogs
          .any((l) => l.status == DoseStatus.missed)) {
        c = DoseWiseColors.red;
      } else {
        c = DoseWiseColors.amber;
      }
      cells.add(Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.all(2),
        decoration:
            BoxDecoration(color: c, shape: BoxShape.circle),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Last 30 days'),
            Wrap(children: cells),
            const SizedBox(height: 8),
            Text('${_logs.length} doses logged total',
                style: const TextStyle(
                    fontSize: 12, color: DoseWiseColors.muted)),
          ],
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
}
