import 'package:dosewise/db/models.dart';
import 'package:dosewise/settings_store.dart';
import 'package:dosewise/ui/add_medication_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Save button sits at the bottom of a lazily-built ListView —
/// scroll it into view before interacting.
Future<void> _scrollToSave(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpForm(
  WidgetTester tester, {
  Medication? existing,
  void Function(Medication)? onSavedSync,
}) async {
  final settings = SettingsStore();
  await tester.pumpWidget(
    MaterialApp(
      home: AddMedicationScreen(
        settings: settings,
        existing: existing,
        autofocusName: false,
        onSaved: (m) async => onSavedSync?.call(m),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Save is disabled until name + at least one time',
      (tester) async {
    Medication? saved;
    await _pumpForm(tester,
        onSavedSync: (m) => saved = m);

    // Enter the name BEFORE scrolling: the ListView disposes off-screen
    // fields, so the name field must be targeted while it's built.
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Vitamin D3');
    await tester.pump();

    await _scrollToSave(tester, 'Save medication');

    final saveBtn =
        find.widgetWithText(FilledButton, 'Save medication');
    expect(saveBtn, findsOneWidget);
    // Name entered + default 8:00 AM time → enabled.
    expect(tester.widget<FilledButton>(saveBtn).onPressed,
        isNotNull);

    await tester.tap(saveBtn);
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.name, 'Vitamin D3');
    expect(saved!.times, ['08:00']);
    expect(saved!.days, [1, 2, 3, 4, 5, 6, 7]);
  });

  testWidgets('Save stays disabled with empty name', (tester) async {
    await _pumpForm(tester);
    await _scrollToSave(tester, 'Save medication');
    final saveBtn =
        find.widgetWithText(FilledButton, 'Save medication');
    expect(saveBtn, findsOneWidget);
    expect(
        tester.widget<FilledButton>(saveBtn).onPressed, isNull);
  });

  testWidgets('Template chip fills name + dose in one tap',
      (tester) async {
    Medication? saved;
    await _pumpForm(tester,
        onSavedSync: (m) => saved = m);

    await tester.tap(find.text('Omega-3'));
    await tester.pump();

    // Name + dose pre-filled from the template.
    final fields =
        tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.first.controller!.text, 'Omega-3');

    await _scrollToSave(tester, 'Save medication');
    await tester.tap(
        find.widgetWithText(FilledButton, 'Save medication'));
    await tester.pumpAndSettle();
    expect(saved!.name, 'Omega-3');
    expect(saved!.dose, '2 softgels');
    expect(saved!.type, MedType.vitamin);
  });

  testWidgets('The last time slot cannot be removed', (tester) async {
    await _pumpForm(tester);

    // Initially one time slot → no remove button (by design: the form
    // always keeps at least one time, so Save's "≥1 time" rule always holds).
    expect(
        find.byIcon(Icons.remove_circle_outline), findsNothing);

    // The time section may need scrolling into view.
    await tester.scrollUntilVisible(
      find.text('+ Add another time'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(
        find.widgetWithText(TextButton, '+ Add another time'));
    await tester.pumpAndSettle();
    expect(
        find.byIcon(Icons.remove_circle_outline), findsNWidgets(2));

    // Remove one → back to a single slot, remove button gone again.
    await tester
        .tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();
    expect(
        find.byIcon(Icons.remove_circle_outline), findsNothing);
  });

  testWidgets('Edit mode pre-fills existing values', (tester) async {
    final existing = Medication(
      id: 7,
      name: 'Magnesium',
      dose: '1 tablet',
      type: MedType.medication,
      times: ['21:00'],
      days: [1, 2, 3, 4, 5],
      pillsRemaining: 12,
      createdAt: DateTime(2026, 1, 1),
    );
    await _pumpForm(tester, existing: existing);

    expect(find.text('Edit medication'), findsOneWidget);
    final fields =
        tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.first.controller!.text, 'Magnesium');
    await _scrollToSave(tester, 'Save changes');
    expect(
        find.widgetWithText(FilledButton, 'Save changes'),
        findsOneWidget);
  });
}
