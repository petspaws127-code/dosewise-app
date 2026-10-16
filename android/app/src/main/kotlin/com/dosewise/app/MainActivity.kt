package com.dosewise.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * DoseWise main activity. Besides the standard Flutter hosting it exposes
 * a tiny settings bridge (channel "com.dosewise.app/settings") because
 * Flutter has no plugin for the exact-alarm / notification / app-info
 * system pages.
 */
class MainActivity : FlutterActivity() {
    private val channel = "com.dosewise.app/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Android 12+: opens this app's "Alarms & reminders" page so
                // the user can grant SCHEDULE_EXACT_ALARM.
                "requestExactAlarm" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
                        ).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                    }
                    result.success(null)
                }
                // This app's notification settings page.
                "openNotificationSettings" -> {
                    val intent = Intent(
                        Settings.ACTION_APP_NOTIFICATION_SETTINGS
                    ).apply {
                        putExtra(
                            Settings.EXTRA_APP_PACKAGE,
                            packageName
                        )
                    }
                    startActivity(intent)
                    result.success(null)
                }
                // This app's App-info page (battery section lives there).
                "openAppInfo" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS
                    ).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
