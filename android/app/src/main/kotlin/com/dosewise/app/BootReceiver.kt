package com.dosewise.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

/**
 * Re-registers every dose alarm after events that clear or shift
 * AlarmManager schedules (spec §2 edges 1–3):
 *  - BOOT_COMPLETED            → reboot clears all alarms
 *  - TIME_SET / TIMEZONE_CHANGED → DST shifts & travel (alarms follow
 *    local wall-clock time, so the whole window is rebuilt)
 *
 * Implementation: spins up a background FlutterEngine, registers plugins,
 * executes the Dart entry-point `rescheduleOnBoot` (top-level in main.dart),
 * then destroys the engine. Dart signals completion on the
 * "com.dosewise.app/boot" channel; a 45s watchdog destroys the engine
 * regardless so we never leak it.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val BOOT_CHANNEL = "com.dosewise.app/boot"
        private const val WATCHDOG_MS = 45_000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        // Note: the manifest registers TIME_SET (manual clock changes);
        // accept TIME_CHANGED too — some OEMs deliver that instead.
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_TIME_SET &&
            action != Intent.ACTION_TIME_CHANGED &&
            action != Intent.ACTION_TIMEZONE_CHANGED
        ) {
            return
        }

        val pending = goAsync()
        val appContext = context.applicationContext

        try {
            val engine = FlutterEngine(appContext)
            GeneratedPluginRegistrant.registerWith(engine)

            var finished = false
            fun finish() {
                if (finished) return
                finished = true
                try {
                    engine.destroy()
                } catch (_: Exception) {
                }
                try {
                    pending.finish()
                } catch (_: Exception) {
                }
            }

            MethodChannel(
                engine.dartExecutor.binaryMessenger,
                BOOT_CHANNEL
            ).setMethodCallHandler { call, result ->
                if (call.method == "bootDone") {
                    result.success(null)
                    finish()
                } else {
                    result.notImplemented()
                }
            }

            // Watchdog: never leak the engine.
            Handler(Looper.getMainLooper()).postDelayed(
                { finish() },
                WATCHDOG_MS
            )

            val bundlePath = FlutterInjector.instance()
                .flutterLoader()
                .findAppBundlePath()
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(bundlePath, "rescheduleOnBoot")
            )
        } catch (_: Exception) {
            try {
                pending.finish()
            } catch (_: Exception) {
            }
        }
    }
}
