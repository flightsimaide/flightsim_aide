package com.flightsimaide.app

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and the Wi-Fi multicast lock channel. Android drops
 * multicast packets (X-Plane's beacon) for apps that do not hold the lock;
 * Dart acquires it while the beacon listener runs and releases it after.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquire" -> {
                        acquireLock()
                        result.success(null)
                    }
                    "release" -> {
                        releaseLock()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireLock() {
        if (multicastLock == null) {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ?: return
            multicastLock = wifi.createMulticastLock("flightsim_aide-beacon").apply {
                setReferenceCounted(false)
            }
        }
        multicastLock?.let { if (!it.isHeld) it.acquire() }
    }

    private fun releaseLock() {
        multicastLock?.let { if (it.isHeld) it.release() }
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "flightsim_aide/multicast"
    }
}
