package com.elmahdi.netget

import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Binder
import android.os.Build
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class DownloadService : Service() {

    companion object {
        const val CACHED_ENGINE_ID = "netget_engine"
        const val ACTION_AUTO_RESUME_BOOT = "ACTION_AUTO_RESUME_BOOT"
    }

    inner class LocalBinder : Binder() {
        fun getService(): DownloadService = this@DownloadService
    }

    private val binder = LocalBinder()
    lateinit var notificationHelper: NotificationHelper
    private var isForeground = false

    // Throttled UI event callback
    var onUpdateListener: ((Map<String, Any>) -> Unit)? = null

    // Global speed limiter (Token Bucket)
    var globalSpeedLimitBytesPerSec = 0L // 0 = unlimited

    // Network callback for auto-resume
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Headless Flutter engine reference
    private var headlessEngine: FlutterEngine? = null

    override fun onCreate() {
        super.onCreate()
        notificationHelper = NotificationHelper(this)
        registerNetworkCallback()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            val action = it.action
            if (action == ACTION_AUTO_RESUME_BOOT) {
                ensureHeadlessEngineRunning()
            }
        }
        return START_STICKY
    }

    /**
     * Initializes and caches a headless FlutterEngine running downloadServiceMain
     * if an engine is not currently cached.
     */
    fun ensureHeadlessEngineRunning(): FlutterEngine {
        var engine = FlutterEngineCache.getInstance().get(CACHED_ENGINE_ID)
        if (engine == null) {
            engine = FlutterEngine(this)
            val flutterLoader = FlutterInjector.instance().flutterLoader()
            if (!flutterLoader.initialized()) {
                flutterLoader.startInitialization(this)
                flutterLoader.ensureInitializationComplete(this, null)
            }
            val entrypoint = DartExecutor.DartEntrypoint(
                flutterLoader.findAppBundlePath(),
                "downloadServiceMain"
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
            FlutterEngineCache.getInstance().put(CACHED_ENGINE_ID, engine)
        }
        headlessEngine = engine
        return engine
    }

    // Active transfers reported from Dart DownloadManager
    private var dartActiveCount: Int = 0
    private var dartProgressText: String = ""
    private var dartPercent: Int = 0
    private var dartFileName: String = ""
    private var dartTotalBytes: Long = -1L

    fun updateDartActiveDownloads(
        count: Int,
        progressText: String,
        percent: Int = 0,
        fileName: String = "",
        totalBytes: Long = -1L
    ) {
        dartActiveCount = count
        dartProgressText = progressText
        dartPercent = percent
        dartFileName = fileName
        dartTotalBytes = totalBytes
        updateForegroundState()
    }

    /**
     * Android 15 (API 35) foreground service dataSync 6-hour timeout handling.
     * Emits onTimeout event to Dart engine to pause active transfers,
     * stops foreground, and posts timeout notification.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        // Emit timeout event to Dart DownloadManager
        onUpdateListener?.invoke(mapOf("event" to "onTimeout"))
        dartActiveCount = 0

        notificationHelper.notifyTimeout(NotificationHelper.SUMMARY_NOTIFICATION_ID)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(false)
        }
        isForeground = false
        stopSelf(startId)
    }

    private fun registerNetworkCallback() {
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            val request = NetworkRequest.Builder()
                .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            networkCallback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    onUpdateListener?.invoke(mapOf("event" to "onNetworkAvailable"))
                }
            }
            connectivityManager?.registerNetworkCallback(request, networkCallback!!)
        } catch (_: Exception) {}
    }

    private fun updateForegroundState() {
        if (dartActiveCount > 0) {
            val summary = notificationHelper.buildSummaryNotification(
                activeCount = dartActiveCount,
                totalSpeedStr = dartProgressText,
                completedCount = 0,
                percent = dartPercent,
                fileName = dartFileName,
                totalBytes = dartTotalBytes
            )
            if (!isForeground) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(
                            NotificationHelper.SUMMARY_NOTIFICATION_ID,
                            summary,
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                        )
                    } else {
                        startForeground(NotificationHelper.SUMMARY_NOTIFICATION_ID, summary)
                    }
                    isForeground = true
                } catch (e: Exception) {
                    isForeground = false
                    throw e
                }
            } else {
                try {
                    notificationHelper.notifySummary(NotificationHelper.SUMMARY_NOTIFICATION_ID, summary)
                } catch (_: Exception) {}
            }
        } else if (isForeground) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
            } catch (_: Exception) {}
            isForeground = false
        }
    }

    override fun onDestroy() {
        notificationHelper.releaseSoundPool()
        networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        headlessEngine?.destroy()
        headlessEngine = null
        super.onDestroy()
    }
}
