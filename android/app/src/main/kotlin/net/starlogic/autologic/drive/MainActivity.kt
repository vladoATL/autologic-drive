package net.starlogic.autologic.drive

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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Must be FlutterFragmentActivity (not FlutterActivity) so local_auth's
// BiometricPrompt can attach to a fragment manager.
class MainActivity : FlutterFragmentActivity() {

    private val eventsChannelName = "net.starlogic.autologic.drive/bt_connections"
    private val methodsChannelName = "net.starlogic.autologic.drive/bt_methods"

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var a2dpProxy: BluetoothA2dp? = null
    private var headsetProxy: BluetoothHeadset? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerReceiver()
                    bindProfileProxies()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterReceiver()
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodsChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connectedDevices" -> result.success(getCurrentlyConnectedAddresses())
                    else -> result.notImplemented()
                }
            }
    }

    private fun registerReceiver() {
        if (receiver != null) return
        val filter = IntentFilter().apply {
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
        }
        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, raw: Intent?) {
                val intent = raw ?: return
                @Suppress("DEPRECATION")
                val device: BluetoothDevice? = intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                val state = intent.getIntExtra(BluetoothProfile.EXTRA_STATE, BluetoothProfile.STATE_DISCONNECTED)
                if (device == null) return
                emit(
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
        // System broadcasts on Android 13+ require an explicit exported flag.
        registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
    }

    private fun unregisterReceiver() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        receiver = null
    }

    private fun bindProfileProxies() {
        val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter ?: return
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
        adapter.getProfileProxy(this, listener, BluetoothProfile.A2DP)
        adapter.getProfileProxy(this, listener, BluetoothProfile.HEADSET)
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

    private fun emit(address: String, state: Int, profile: String) {
        val payload = mapOf(
            "address" to address,
            "state" to when (state) {
                BluetoothProfile.STATE_CONNECTED -> "connected"
                BluetoothProfile.STATE_DISCONNECTED -> "disconnected"
                BluetoothProfile.STATE_CONNECTING -> "connecting"
                BluetoothProfile.STATE_DISCONNECTING -> "disconnecting"
                else -> "unknown"
            },
            "profile" to profile
        )
        eventSink?.success(payload)
    }

    override fun onResume() {
        super.onResume()
        // Re-poll on every resume in case a connect happened while the app was
        // out of foreground and the broadcast was missed.
        eventSink?.let { _ ->
            getCurrentlyConnectedAddresses().forEach { addr ->
                emit(addr, BluetoothProfile.STATE_CONNECTED, "poll")
            }
        }
    }

    override fun onDestroy() {
        unregisterReceiver()
        val adapter = BluetoothAdapter.getDefaultAdapter()
        a2dpProxy?.let { adapter?.closeProfileProxy(BluetoothProfile.A2DP, it) }
        headsetProxy?.let { adapter?.closeProfileProxy(BluetoothProfile.HEADSET, it) }
        super.onDestroy()
    }
}
