import 'package:flutter/services.dart';

/// Thin bridge to MainActivity for system-settings deep links that have
/// no Flutter-plugin equivalent (exact-alarm settings, notification
/// settings, battery-optimization app details).
class SystemSettings {
  static const _ch = MethodChannel('com.dosewise.app/settings');

  /// Opens the system "Alarms & reminders" page for this app (Android 12+).
  static Future<void> requestExactAlarmPermission() async {
    try {
      await _ch.invokeMethod('requestExactAlarm');
    } on MissingPluginException {
      // Running on a platform without the native bridge (tests, iOS).
    }
  }

  /// Opens this app's notification settings page.
  static Future<void> openNotificationSettings() async {
    try {
      await _ch.invokeMethod('openNotificationSettings');
    } on MissingPluginException {
      // no-op
    }
  }

  /// Opens this app's "App info" page (battery section lives there).
  static Future<void> openAppInfo() async {
    try {
      await _ch.invokeMethod('openAppInfo');
    } on MissingPluginException {
      // no-op
    }
  }
}
