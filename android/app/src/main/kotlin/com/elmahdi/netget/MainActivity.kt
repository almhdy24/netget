package com.elmahdi.netget

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "com.elmahdi.netget/engine"
        const val EVENT_CHANNEL = "com.elmahdi.netget/events"
    }

    private var downloadService: DownloadService? = null
    private var isBound = false
    private var eventSink: EventChannel.EventSink? = null
    private var pendingIntentUrl: String? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            val binder = service as DownloadService.LocalBinder
            downloadService = binder.getService()
            isBound = true

            downloadService?.onUpdateListener = { updateMap ->
                runOnUiThread {
                    eventSink?.success(updateMap)
                }
            }
        }

        override fun onServiceDisconnected(arg0: ComponentName) {
            isBound = false
            downloadService = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
        val serviceIntent = Intent(this, DownloadService::class.java)
        startService(serviceIntent)
        bindService(serviceIntent, connection, Context.BIND_AUTO_CREATE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.let {
            if (Intent.ACTION_SEND == it.action && "text/plain" == it.type) {
                val sharedText = it.getStringExtra(Intent.EXTRA_TEXT)
                if (sharedText != null && (sharedText.startsWith("http://") || sharedText.startsWith("https://"))) {
                    pendingIntentUrl = sharedText.trim()
                }
            } else if (Intent.ACTION_VIEW == it.action) {
                val dataUri = it.data
                if (dataUri != null) {
                    val scheme = dataUri.scheme
                    if ("http".equals(scheme, ignoreCase = true) || "https".equals(scheme, ignoreCase = true)) {
                        pendingIntentUrl = dataUri.toString().trim()
                    }
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startDownload" -> {
                    val id = call.argument<String>("id") ?: ""
                    val url = call.argument<String>("url") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val savePath = call.argument<String>("savePath") ?: ""
                    val totalBytes = (call.argument<Number>("totalBytes") ?: -1).toLong()
                    val connections = call.argument<Int>("connections") ?: 4
                    val category = call.argument<String>("category") ?: "other"
                    val etag = call.argument<String>("etag")
                    val lastModified = call.argument<String>("lastModified")

                    downloadService?.startDownload(id, url, fileName, savePath, totalBytes, connections, category, etag, lastModified)
                    result.success(true)
                }
                "pauseDownload" -> {
                    val id = call.argument<String>("id") ?: ""
                    downloadService?.pauseDownload(id)
                    result.success(true)
                }
                "resumeDownload" -> {
                    val id = call.argument<String>("id") ?: ""
                    downloadService?.resumeDownload(id)
                    result.success(true)
                }
                "cancelDownload" -> {
                    val id = call.argument<String>("id") ?: ""
                    downloadService?.cancelDownload(id)
                    result.success(true)
                }
                "setSpeedLimit" -> {
                    val limit = (call.argument<Number>("bytesPerSec") ?: 0).toLong()
                    downloadService?.globalSpeedLimitBytesPerSec = limit
                    result.success(true)
                }
                "getPendingIntentUrl" -> {
                    val url = pendingIntentUrl
                    pendingIntentUrl = null
                    result.success(url)
                }
                "updateActiveDownloads" -> {
                    try {
                        val count = call.argument<Int>("activeCount") ?: 0
                        val progressText = call.argument<String>("progressText") ?: ""
                        downloadService?.updateDartActiveDownloads(count, progressText)
                        result.success(true)
                    } catch (e: Exception) {
                        // Catches ForegroundServiceStartNotAllowedException (Android 12+ / API 31+)
                        // and any SecurityException or generic runtime error (verify in docs)
                        result.error(
                            "FGS_NOT_ALLOWED",
                            "Foreground service update failed: ${e.message}",
                            e.javaClass.name
                        )
                    }
                }
                "playSound" -> {
                    val sound = call.argument<String>("sound") ?: ""
                    downloadService?.notificationHelper?.playSound(sound)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onDestroy() {
        if (isBound) {
            unbindService(connection)
            isBound = false
        }
        super.onDestroy()
    }
}
