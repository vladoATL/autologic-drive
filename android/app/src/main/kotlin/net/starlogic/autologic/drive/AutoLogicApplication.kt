package net.starlogic.autologic.drive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Process-level entry point. Owns ONE long-lived [FlutterEngine] (cache key
 * [ENGINE_ID]) so that Dart-side `BluetoothWatcher` and the `bt_methods` /
 * `bt_connections` channels survive past `MainActivity.onDestroy`.
 *
 * Without this caching, dismissing the app from recents kills the only
 * engine instance. The `MonitorService` foreground service holds the
 * process alive; the cached engine then keeps receiving BT / Android Auto
 * events even when no Activity is on screen.
 */
class AutoLogicApplication : FlutterApplication() {

    override fun onCreate() {
        super.onCreate()
        android.util.Log.i(TAG, "Application.onCreate — pre-warming Flutter engine")

        // Pre-warm the engine so MainActivity attaches instantly and so the
        // MonitorService can address it from a background broadcast.
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault()
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        EngineChannels.attach(this, engine)
        android.util.Log.i(TAG, "EngineChannels attached to cached engine $ENGINE_ID")

        ensureMonitorNotificationChannel()
    }

    /**
     * Foreground services on Android O+ require a notification channel
     * registered before the first start. Defining it here (not in the
     * service itself) means it exists even if the service is started from
     * a broadcast receiver before any Activity has run.
     */
    private fun ensureMonitorNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        // Delete legacy channels (id MIN/LOW) that earlier dev installs
        // created — channel settings are cached by Android and our later
        // importance bumps don't take effect on already-created channels.
        nm.deleteNotificationChannel(MONITOR_CHANNEL_ID)
        android.util.Log.i(TAG, "Deleted any prior $MONITOR_CHANNEL_ID channel")
        val channel = NotificationChannel(
            MONITOR_CHANNEL_ID,
            "Auto-detection",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Background service watching for vehicle BT / Android Auto"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
        }
        nm.createNotificationChannel(channel)
        val verify = nm.getNotificationChannel(MONITOR_CHANNEL_ID)
        android.util.Log.i(
            TAG,
            "Created $MONITOR_CHANNEL_ID channel — importance=${verify?.importance}, sound=${verify?.sound}, lockscreenVis=${verify?.lockscreenVisibility}"
        )
    }

    companion object {
        private const val TAG = "AutoLogicApp"
        const val ENGINE_ID = "autologic_drive_main_engine"
        const val MONITOR_CHANNEL_ID = "monitor_service"
    }
}
