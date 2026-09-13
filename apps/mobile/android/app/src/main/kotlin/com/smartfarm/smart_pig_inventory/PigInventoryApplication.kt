package com.smartfarm.smart_pig_inventory

import android.app.Application
import android.content.Context
import android.net.wifi.WifiManager

class PigInventoryApplication : Application() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate() {
        super.onCreate()
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        multicastLock = wifi?.createMulticastLock("pig-inventory-lan-discovery")?.apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onTerminate() {
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onTerminate()
    }
}
