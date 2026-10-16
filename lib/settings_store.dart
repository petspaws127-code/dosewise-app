import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1 settings, all local. No account, nothing leaves the phone.
class SettingsStore extends ChangeNotifier {
  /// 'system' | '12' | '24'
  String timeFormat = 'system';

  /// 15 | 30 | 60
  int snoozeMinutes = 15;

  bool soundOn = true;
  bool vibrationOn = true;

  /// Sunday = 7, Monday = 1 (DateTime.weekday). Spec §1.5 weeks are
  /// Mon–Sun, so Monday is the default.
  int firstDayOfWeek = 1;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    timeFormat = p.getString('time_format') ?? 'system';
    snoozeMinutes = p.getInt('snooze_minutes') ?? 15;
    soundOn = p.getBool('sound_on') ?? true;
    vibrationOn = p.getBool('vibration_on') ?? true;
    firstDayOfWeek = p.getInt('first_day_of_week') ?? 1;
    notifyListeners();
  }

  Future<void> setTimeFormat(String v) async {
    timeFormat = v;
    (await SharedPreferences.getInstance()).setString('time_format', v);
    notifyListeners();
  }

  Future<void> setSnoozeMinutes(int v) async {
    snoozeMinutes = v;
    (await SharedPreferences.getInstance()).setInt('snooze_minutes', v);
    notifyListeners();
  }

  Future<void> setSound(bool v) async {
    soundOn = v;
    (await SharedPreferences.getInstance()).setBool('sound_on', v);
    notifyListeners();
  }

  Future<void> setVibration(bool v) async {
    vibrationOn = v;
    (await SharedPreferences.getInstance()).setBool('vibration_on', v);
    notifyListeners();
  }

  Future<void> setFirstDayOfWeek(int v) async {
    firstDayOfWeek = v;
    (await SharedPreferences.getInstance()).setInt('first_day_of_week', v);
    notifyListeners();
  }
}
