package net.starlogic.autologic.drive

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.Observer
import androidx.car.app.connection.CarConnection

/**
 * Always-on foreground service that keeps the JVM (and the cached
 * [io.flutter.embedding.engine.FlutterEngine]) alive so Bluetooth / Android
 * Auto connection events can wake a trip even when the user has dismissed
 * the app from recents. Without this, BT broadcasts go to a dead process
 * and trips never auto-start.
 *
 * Hosts:
 * - A runtime-registered receiver for `BluetoothA2dp` / `BluetoothHeadset`
 *   connection-state changes (the signals the Dart `BluetoothWatcher` uses
 *   to auto-start trips).
 * - An [androidx.car.app.connection.CarConnection] LiveData observer that
 *   emits an event when Android Auto projection is connected — a fast,
 *   reliable signal that the driver has plugged into a head unit.
 *
 * Both signals are forwarded to Dart via the existing `bt_connections`
 * `EventChannel` (so the Dart side doesn't need to know about this service).
 */
class MonitorService : LifecycleService() {

    private val notificationId = 4711

    companion object {
        private const val TAG = "MonitorService"
        const val ACTION_STOP_MONITORING = "net.starlogic.autologic.drive.action.STOP_MONITORING"
    }

    private var receiver: BroadcastReceiver? = null
    private var carConnection: CarConnection? = null
    private var carConnectionObserver: Observer<Int>? = null
    private var lastCarType: Int = CarConnection.CONNECTION_TYPE_NOT_CONNECTED

    override fun onBind(intent: Intent): IBinder? {
        super.onBind(intent)
        return null
    }

    override fun onCreate() {
        super.onCreate()
        android.util.Log.i(TAG, "onCreate — entering foreground")
        try {
            startForegroundWithNotification()
        } catch (e: Throwable) {
            android.util.Log.e(TAG, "Failed to enter foreground: $e")
            stopSelf()
            return
        }
        // Belt-and-braces: also explicitly post the same notification through
        // NotificationManager. On Samsung One UI 6.1+ the notification that
        // ships with `startForeground` is sometimes filtered out of the user-
        // visible shade entirely — re-posting via `notify(id, ...)` makes it
        // unavoidably visible. Same id + ongoing flag → no duplicate.
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(notificationId, buildNotification())
            android.util.Log.i(TAG, "Reposted notification via NotificationManager.notify()")
        } catch (e: Throwable) {
            android.util.Log.w(TAG, "notify() repost failed: $e")
        }
        registerBluetoothReceiver()
        observeAndroidAuto()
        android.util.Log.i(TAG, "onCreate complete — receiver registered, AA observer set")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_STOP_MONITORING) {
            android.util.Log.i("MonitorService", "User pressed Pozastaviť — stopping service")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterBluetoothReceiver()
        unobserveAndroidAuto()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        // "Pozastaviť" action — sends ACTION_STOP_MONITORING back to this
        // service, which calls stopForeground + stopSelf. Re-opening the
        // app via the launcher restarts the service from MainActivity.onResume.
        val stopIntent = Intent(this, MonitorService::class.java).apply {
            action = ACTION_STOP_MONITORING
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, AutoLogicApplication.MONITOR_CHANNEL_ID)
            .setContentTitle("AutoLogic Drive")
            .setContentText("Sledujem pripojenie do auta")
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(pendingIntent)
            .addAction(0, "Pozastaviť", stopPendingIntent)
            .build()
    }

    private fun startForegroundWithNotification() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                notificationId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(notificationId, notification)
        }
        android.util.Log.i(TAG, "startForeground OK — id=$notificationId")
    }

    // --- Bluetooth ---------------------------------------------------------

    private fun registerBluetoothReceiver() {
        if (receiver != null) return
        val filter = IntentFilter().apply {
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, raw: Intent?) {
                val intent = raw ?: return
                @Suppress("DEPRECATION")
                val device: BluetoothDevice? =
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                val state = intent.getIntExtra(
                    BluetoothProfile.EXTRA_STATE, BluetoothProfile.STATE_DISCONNECTED
                )
                if (device == null) return
                EngineChannels.emit(
                    address = device.address,
                    state = state,
                    profile = when (intent.action) {
                        BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED -> "a2dp"
                        BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED -> "headset"
                        else -> "other"
                    }
                )
            }
        }
        registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
    }

    private fun unregisterBluetoothReceiver() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        receiver = null
    }

    // --- Android Auto ------------------------------------------------------

    private fun observeAndroidAuto() {
        if (carConnectionObserver != null) return
        val cc = CarConnection(applicationContext)
        carConnection = cc
        val obs = Observer<Int> { type ->
            // Only emit on transitions to CONNECTED; debounce repeats.
            if (type == lastCarType) return@Observer
            lastCarType = type
            if (type == CarConnection.CONNECTION_TYPE_PROJECTION ||
                type == CarConnection.CONNECTION_TYPE_NATIVE
            ) {
                // Android Auto / Automotive OS came online. Use a synthetic
                // "address" so Dart can recognise this isn't a BT MAC.
                EngineChannels.emit(
                    address = "android-auto",
                    state = BluetoothProfile.STATE_CONNECTED,
                    profile = "android_auto"
                )
            }
        }
        carConnectionObserver = obs
        cc.type.observe(this, obs)
    }

    private fun unobserveAndroidAuto() {
        val obs = carConnectionObserver
        val cc = carConnection
        if (obs != null && cc != null) cc.type.removeObserver(obs)
        carConnectionObserver = null
        carConnection = null
    }

}
