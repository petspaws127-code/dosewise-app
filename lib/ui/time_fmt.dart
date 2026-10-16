import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../settings_store.dart';

/// Single time formatter for the whole app (spec §2 edge 6):
/// system locale default, manual 12/24h override in Settings.
/// No hardcoded AM/PM anywhere else.
String formatTime(DateTime t, SettingsStore s) {
  switch (s.timeFormat) {
    case '24':
      return DateFormat('HH:mm').format(t);
    case '12':
      return DateFormat('h:mm a').format(t);
    default:
      return DateFormat.jm().format(t);
  }
}

String formatTimeOfDay(TimeOfDay t, SettingsStore s) => formatTime(
      DateTime(2000, 1, 1, t.hour, t.minute),
      s,
    );

/// "in 25 min" / "in 2 h" / "8:00 AM" countdown copy for the hero card.
String countdownCopy(DateTime at, SettingsStore s) {
  final diff = at.difference(DateTime.now());
  if (diff.isNegative || diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'in ${diff.inHours} h';
  return formatTime(at, s);
}

String formatDayHeader(DateTime d) => DateFormat('EEEE, MMMM d').format(d);
