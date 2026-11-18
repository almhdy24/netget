package com.elmahdi.netget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Intent.ACTION_BOOT_COMPLETED == intent.action ||
            "android.intent.action.QUICKBOOT_POWERON" == intent.action) {
            val prefs = context.getSharedPreferences("netget_settings", Context.MODE_PRIVATE)
            val autoResumeOnBoot = prefs.getBoolean("auto_resume_on_boot", true)
            if (autoResumeOnBoot) {
                val serviceIntent = Intent(context, DownloadService::class.java).apply {
                    action = "ACTION_AUTO_RESUME_BOOT"
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(serviceIntent)
                    } else {
                        context.startService(serviceIntent)
                    }
                } catch (_: Exception) {}
            }
        }
    }
}
