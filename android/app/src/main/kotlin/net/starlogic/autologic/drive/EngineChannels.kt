package net.starlogic.autologic.drive

import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Dart-facing channels (`bt_methods`, `bt_connections`) on the
 * cached [FlutterEngine]. Registered once from [AutoLogicApplication.onCreate]
 * so both [MainActivity] (foreground polls) and [MonitorService] (background
 * BT / CarConnection events) can publish to the same Dart [BluetoothWatcher]
 * without setting up channels themselves.
 */
object EngineChannels {

    private const val EVENTS_NAME = "net.starlogic.autologic.drive/bt_connections"
    private const val METHODS_NAME = "net.starlogic.autologic.drive/bt_methods"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var sink: EventChannel.EventSink? = null
    @Volatile private var appContext: Context? = null
    @Volatile private var a2dpProxy: BluetoothA2dp? = null
    @Volatile private var headsetProxy: BluetoothHeadset? = null

    fun attach(context: Context, engine: FlutterEngine) {
        appContext = context.applicationContext
        bindProfileProxies(context.applicationContext)

        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS_NAME)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    sink = events
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                }
            })

        MethodChannel(engine.dartExecutor.binaryMessenger, METHODS_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connectedDevices" -> result.success(getCurrentlyConnectedAddresses())
                    "deviceLabel" -> result.success(getDeviceLabel(context.applicationContext))
                    "startMonitorService" -> {
                        android.util.Log.i("EngineChannels", "Dart -> startMonitorService")
                        val ctx = appContext ?: context.applicationContext
                        val intent = android.content.Intent(ctx, MonitorService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ctx.startForegroundService(intent)
                        } else {
                            ctx.startService(intent)
                        }
                        android.util.Log.i("EngineChannels", "MonitorService start dispatched")
                        result.success(null)
                    }
                    "stopMonitorService" -> {
                        android.util.Log.i("EngineChannels", "Dart -> stopMonitorService")
                        val ctx = appContext ?: context.applicationContext
                        val intent = android.content.Intent(ctx, MonitorService::class.java).apply {
                            action = MonitorService.ACTION_STOP_MONITORING
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            ctx.startForegroundService(intent)
                        } else {
                            ctx.startService(intent)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Push a connection event to Dart. Safe to call from any thread. */
    fun emit(address: String, stateLabel: String, profile: String) {
        val payload = mapOf(
            "address" to address,
            "state" to stateLabel,
            "profile" to profile,
        )
        mainHandler.post {
            try {
                sink?.success(payload)
            } catch (_: Throwable) {
                // Sink can be torn down between null-check and call; ignore.
            }
        }
    }

    fun emit(address: String, state: Int, profile: String) {
        emit(
            address = address,
            stateLabel = when (state) {
                BluetoothProfile.STATE_CONNECTED -> "connected"
                BluetoothProfile.STATE_DISCONNECTED -> "disconnected"
                BluetoothProfile.STATE_CONNECTING -> "connecting"
                BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
                else -> "unknown"
            },
            profile = profile,
        )
    }

    private fun bindProfileProxies(ctx: Context) {
        val adapter = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter ?: return
        val listener = object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                when (profile) {
                    BluetoothProfile.A2DP -> a2dpProxy = proxy as? BluetoothA2dp
                    BluetoothProfile.HEADSET -> headsetProxy = proxy as? BluetoothHeadset
                }
            }

            override fun onServiceDisconnected(profile: Int) {
                when (profile) {
                    BluetoothProfile.A2DP -> a2dpProxy = null
                    BluetoothProfile.HEADSET -> headsetProxy = null
                }
            }
        }
        adapter.getProfileProxy(ctx, listener, BluetoothProfile.A2DP)
        adapter.getProfileProxy(ctx, listener, BluetoothProfile.HEADSET)
    }

    @Suppress("MissingPermission")
    private fun getCurrentlyConnectedAddresses(): List<String> {
        val out = mutableSetOf<String>()
        try {
            a2dpProxy?.connectedDevices?.forEach { out.add(it.address) }
            headsetProxy?.connectedDevices?.forEach { out.add(it.address) }
        } catch (_: SecurityException) {
            // No BLUETOOTH_CONNECT permission yet — caller will retry after grant.
        }
        return out.toList()
    }

    @Suppress("MissingPermission")
    private fun getDeviceLabel(ctx: Context): String {
        try {
            val adapter = (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            val btName = adapter?.name
            if (!btName.isNullOrBlank()) return btName
        } catch (_: SecurityException) {
            // BLUETOOTH_CONNECT not granted yet — fall through.
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val global = Settings.Global.getString(ctx.contentResolver, Settings.Global.DEVICE_NAME)
                if (!global.isNullOrBlank()) return global
            } catch (_: Throwable) {
                // ignore
            }
        }
        return Build.MODEL ?: "Android"
    }
}
