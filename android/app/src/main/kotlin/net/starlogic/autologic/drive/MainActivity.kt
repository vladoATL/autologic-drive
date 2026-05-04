package net.starlogic.autologic.drive

import android.Manifest
import android.bluetooth.BluetoothProfile
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * UI host. The actual Bluetooth / Android Auto detection lives in
 * [MonitorService] (always-on foreground service) and the channels live in
 * [EngineChannels] on the cached engine — so events keep flowing even when
 * the user dismisses the activity from recents.
 *
 * MainActivity remains [FlutterFragmentActivity] (not FlutterActivity) so
 * `local_auth`'s BiometricPrompt can attach to a fragment manager.
 */
class MainActivity : FlutterFragmentActivity() {

    /// Reuse the engine pre-warmed in [AutoLogicApplication.onCreate] so the
    /// Dart isolate (and therefore `BluetoothWatcher`) survives Activity
    /// recreations. Using the framework's `getCachedEngineId()` hook (rather
    /// than `provideFlutterEngine`) makes the embedding manage attach /
    /// detach lifecycle correctly — fixes the "FlutterJNI is not attached
    /// to native" crash that happens on certain activity recreations when
    /// the engine is wired in manually.
    override fun getCachedEngineId(): String = AutoLogicApplication.ENGINE_ID

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        startMonitorServiceIfNeeded()
    }

    override fun onResume() {
        super.onResume()
        // Retry MonitorService start in case the user granted BLUETOOTH_CONNECT
        // since the activity was created (e.g. via Settings or onboarding).
        startMonitorServiceIfNeeded()
        // Backstop: replay the currently-connected BT addresses through the
        // event channel in case we missed broadcasts while suspended.
        EngineChannels.emit(
            address = "",            // sentinel, ignored by Dart
            stateLabel = "poll_request",
            profile = "poll",
        )
    }

    private fun startMonitorServiceIfNeeded() {
        android.util.Log.i("MainActivity", "startMonitorServiceIfNeeded — checking permissions")
        // Respect the user's explicit "Sledovať na pozadí" toggle from
        // SettingsScreen. Stored by the `shared_preferences` Flutter plugin
        // under key `flutter.monitor_service_enabled` (default true).
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (flutterPrefs.contains("flutter.monitor_service_enabled") &&
            !flutterPrefs.getBoolean("flutter.monitor_service_enabled", true)
        ) {
            android.util.Log.i("MainActivity", "monitor_service_enabled = false — user opted out")
            return
        }
        // Android 14+ refuses a `connectedDevice`-typed FGS without
        // BLUETOOTH_CONNECT granted at runtime. If we call
        // startForegroundService() and the service then bails out without
        // calling startForeground() in time, the OS throws
        // ForegroundServiceDidNotStartInTimeException and crashes the app.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT)
                != PackageManager.PERMISSION_GRANTED
        ) {
            android.util.Log.i(
                "MainActivity",
                "BLUETOOTH_CONNECT not granted — skipping MonitorService start, will retry after onboarding"
            )
            return
        }
        val intent = Intent(this, MonitorService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        android.util.Log.i("MainActivity", "startForegroundService(MonitorService) called")
    }
}
