import 'package:flutter/material.dart';

import 'db/database.dart';
import 'meds/medication_repository.dart';
import 'settings_store.dart';
import 'theme.dart';
import 'ui/home_screen.dart';
import 'ui/onboarding_screen.dart';

/// DoseWise root. Shows onboarding on first launch, Home after.
class DoseWiseApp extends StatefulWidget {
  const DoseWiseApp({
    super.key,
    required this.db,
    required this.repo,
    required this.settings,
  });
  final AppDatabase db;
  final MedicationRepository repo;
  final SettingsStore settings;

  @override
  State<DoseWiseApp> createState() => _DoseWiseAppState();
}

class _DoseWiseAppState extends State<DoseWiseApp> {
  bool? _onboarded;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final done =
        await widget.db.metaGet(AppDatabase.kOnboardingDone);
    if (mounted) setState(() => _onboarded = done == '1');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DoseWise',
      debugShowCheckedModeBanner: false,
      theme: DoseWiseTheme.light,
      home: _onboarded == null
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()))
          : _onboarded == true
              ? HomeScreen(
                  db: widget.db,
                  repo: widget.repo,
                  settings: widget.settings)
              : OnboardingScreen(
                  db: widget.db,
                  repo: widget.repo,
                  settings: widget.settings,
                  onDone: () => setState(() => _onboarded = true),
                ),
    );
  }
}
