import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/models.dart';
import '../settings_store.dart';
import '../theme.dart';
import 'time_fmt.dart';
import 'widgets.dart';

/// Template chips for the 30-second path (spec §1.1): tap → name + default
/// time filled, user confirms with Save = 2 taps.
const List<(String, String)> kTemplates = [
  ('Multivitamin', '1 tablet'),
  ('Vitamin D', '1 capsule'),
  ('Vitamin C', '1 tablet'),
  ('Omega-3', '2 softgels'),
  ('Birth control', '1 pill'),
  ('Custom', ''),
];

const List<String> kWeekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun'
];

/// Add-medication form. Doubles as Edit when [existing] is provided.
/// Spec §1.3: name → dose → time(s) → days → type → Save. One screen.
class AddMedicationScreen extends StatefulWidget {
  const AddMedicationScreen({
    super.key,
    required this.settings,
    this.existing,
    this.onSaved,
    this.autofocusName = true,
    this.onClose,
  });
  final SettingsStore settings;
  final Medication? existing;
  final Future<void> Function(Medication med)? onSaved;
  final bool autofocusName;

  /// When set, the X button calls this instead of popping (onboarding:
  /// X means "skip for now" → enter the app, never pop to nothing).
  final VoidCallback? onClose;

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  late final TextEditingController _name;
  late final TextEditingController _dose;
  late final TextEditingController _pills;
  MedType _type = MedType.medication;
  List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  List<int> _days = [1, 2, 3, 4, 5, 6, 7];
  String? _template;
  String? _nameError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _dose = TextEditingController(text: e?.dose ?? '');
    _pills = TextEditingController(
        text: e?.pillsRemaining?.toString() ?? '');
    if (e != null) {
      _type = e.type;
      _times = e.times.map(_parseTime).toList();
      if (_times.isEmpty) {
        _times = [const TimeOfDay(hour: 8, minute: 0)];
      }
      _days = List.of(e.days);
    }
  }

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _pills.dispose();
    super.dispose();
  }

  void _applyTemplate(String name, String dose) {
    setState(() {
      _template = name;
      if (name != 'Custom') {
        _name.text = name;
        _dose.text = dose;
        if (name.toLowerCase().contains('vitamin') ||
            name == 'Multivitamin' ||
            name == 'Omega-3') {
          _type = MedType.vitamin;
        }
      } else {
        _name.clear();
      }
      _nameError = null;
    });
  }

  Future<void> _pickTime(int index) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _times[index],
    );
    if (picked != null) {
      setState(() => _times[index] = picked);
    }
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _times.isNotEmpty;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Give it a name — e.g. Vitamin D');
      return;
    }
    final pills = int.tryParse(_pills.text.trim());
    final med = Medication(
      id: widget.existing?.id,
      name: _name.text.trim(),
      dose: _dose.text.trim(),
      type: _type,
      times: _times.map(_fmt).toList(),
      days: List.of(_days)..sort(),
      pillsRemaining: pills,
      paused: widget.existing?.paused ?? false,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    final cb = widget.onSaved;
    if (cb != null) await cb(med);
    if (mounted) Navigator.of(context).pop(med);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit medication' : 'Add medication'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (!_isEdit) ...[
              const SectionLabel('Quick add'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, dose) in kTemplates)
                    ChoiceChip(
                      label: Text(name),
                      selected: _template == name,
                      onSelected: (_) => _applyTemplate(name, dose),
                      selectedColor: DoseWiseColors.teal,
                      labelStyle: TextStyle(
                        color: _template == name
                            ? Colors.white
                            : DoseWiseColors.teal,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      backgroundColor: DoseWiseColors.tealSofter,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            const SectionLabel('Name'),
            TextField(
              controller: _name,
              autofocus: widget.autofocusName && !_isEdit,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'e.g. Vitamin D3',
                errorText: _nameError,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DoseWiseColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DoseWiseColors.line),
                ),
              ),
              onChanged: (_) {
                // Rebuild so the Save button's enabled state tracks
                // validity live (typing the first character must enable it).
                setState(() {
                  if (_nameError != null) _nameError = null;
                });
              },
            ),
            const SizedBox(height: 14),
            const SectionLabel('Dose'),
            TextField(
              controller: _dose,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g. 1 capsule, 500mg',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DoseWiseColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DoseWiseColors.line),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const SectionLabel('Type'),
            SegmentedButton<MedType>(
              segments: const [
                ButtonSegment(
                    value: MedType.medication, label: Text('Medication')),
                ButtonSegment(
                    value: MedType.vitamin, label: Text('Vitamin')),
              ],
              selected: {_type},
              onSelectionChanged: (v) =>
                  setState(() => _type = v.first),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: SectionLabel('Time')),
                if (_times.length < 6)
                  Flexible(
                    child: TextButton(
                      onPressed: () => setState(() => _times.add(
                          const TimeOfDay(hour: 8, minute: 0))),
                      child: const Text('+ Add another time'),
                    ),
                  ),
              ],
            ),
            for (var i = 0; i < _times.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _pickTime(i),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: DoseWiseColors.line),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule,
                                  size: 18,
                                  color: DoseWiseColors.teal),
                              const SizedBox(width: 10),
                              Text(
                                formatTimeOfDay(_times[i], s),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_times.length > 1)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: DoseWiseColors.red),
                        onPressed: () =>
                            setState(() => _times.removeAt(i)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(child: SectionLabel('Days')),
                Flexible(
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _days = [1, 2, 3, 4, 5]),
                    child: const Text('Weekdays only'),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var d = 1; d <= 7; d++)
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_days.contains(d)) {
                        if (_days.length > 1) _days.remove(d);
                      } else {
                        _days.add(d);
                      }
                    }),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _days.contains(d)
                            ? DoseWiseColors.teal
                            : DoseWiseColors.tealSofter,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        kWeekdayNames[d - 1][0],
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: _days.contains(d)
                              ? Colors.white
                              : DoseWiseColors.teal,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            const SectionLabel('Pills in bottle (optional)'),
            TextField(
              controller: _pills,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: 'e.g. 30 — enables refill alerts',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DoseWiseColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: DoseWiseColors.line),
                ),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _valid ? _save : null,
              child: Text(_isEdit ? 'Save changes' : 'Save medication'),
            ),
            const SizedBox(height: 8),
            if (!_valid)
              const Text(
                'Add a name and at least one time to save.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 12, color: DoseWiseColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}
