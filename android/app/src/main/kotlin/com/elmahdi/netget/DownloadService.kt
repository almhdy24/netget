package com.elmahdi.netget

import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Binder
import android.os.Build
import android.os.Environment
import android.os.IBinder
import java.io.File
import java.io.InputStream
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class DownloadService : Service() {

    inner class LocalBinder : Binder() {
        fun getService(): DownloadService = this@DownloadService
    }

    private val binder = LocalBinder()
    lateinit var dbHelper: DownloadDatabaseHelper
    lateinit var notificationHelper: NotificationHelper

    private val executor = Executors.newFixedThreadPool(8)
    private val activeTasks = ConcurrentHashMap<String, DownloadWorker>()
    private var isForeground = false

    // Throttled UI event callback
    var onUpdateListener: ((Map<String, Any>) -> Unit)? = null
    private var lastEmitTime = 0L

    // Global speed limiter (Token Bucket)
    var globalSpeedLimitBytesPerSec = 0L // 0 = unlimited

    // Network callback for auto-resume
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun onCreate() {
        super.onCreate()
        dbHelper = DownloadDatabaseHelper(this)
        notificationHelper = NotificationHelper(this)
        registerNetworkCallback()
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            val action = it.action
            val taskId = it.getStringExtra(NotificationHelper.EXTRA_TASK_ID)
            if (taskId != null) {
                when (action) {
                    NotificationHelper.ACTION_PAUSE -> pauseDownload(taskId)
                    NotificationHelper.ACTION_RESUME -> resumeDownload(taskId)
                    NotificationHelper.ACTION_CANCEL -> cancelDownload(taskId)
                }
            }
        }
        return START_STICKY
    }

    /**
     * Android 15 (API 35) foreground service dataSync 6-hour timeout handling.
     * Persists all active transfers, stops foreground, and posts user resumable notification.
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        // Persist all downloading tasks as paused
        activeTasks.values.forEach { worker ->
            worker.pause()
            dbHelper.updateStatus(worker.taskId, "paused")
        }
        activeTasks.clear()

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
                    // Auto-resume paused tasks marked for auto-resume when network returns
                    activeTasks.values.filter { it.isPaused.get() }.forEach {
                        it.resume()
                    }
                }
            }
            connectivityManager?.registerNetworkCallback(request, networkCallback!!)
        } catch (_: Exception) {}
    }

    fun startDownload(
        id: String,
        url: String,
        fileName: String,
        savePath: String,
        totalBytes: Long,
        connectionCount: Int,
        category: String,
        etag: String?,
        lastModified: String?
    ) {
        val worker = DownloadWorker(
            id, url, fileName, savePath, totalBytes, connectionCount,
            category, etag, lastModified
        )
        activeTasks[id] = worker
        updateForegroundState()
        executor.execute(worker)
        notificationHelper.playSound("start")
    }

    fun pauseDownload(id: String) {
        activeTasks[id]?.pause()
        dbHelper.updateStatus(id, "paused")
        updateForegroundState()
    }

    fun resumeDownload(id: String) {
        activeTasks[id]?.let {
            it.resume()
            executor.execute(it)
        }
        updateForegroundState()
    }

    fun cancelDownload(id: String) {
        activeTasks[id]?.cancel()
        activeTasks.remove(id)
        dbHelper.updateStatus(id, "cancelled")
        updateForegroundState()
    }

    private fun updateForegroundState() {
        val runningCount = activeTasks.values.count { !it.isPaused.get() && !it.isCancelled.get() }
        if (runningCount > 0) {
            val totalSpeed = activeTasks.values.sumOf { it.currentSpeedBytesPerSec }
            val summary = notificationHelper.buildSummaryNotification(
                runningCount,
                formatSpeed(totalSpeed),
                0
            )
            if (!isForeground) {
                startForeground(NotificationHelper.SUMMARY_NOTIFICATION_ID, summary)
                isForeground = true
            }
        } else if (isForeground) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(false)
            }
            isForeground = false
        }
    }

    fun notifyProgress(taskId: String, downloaded: Long, total: Long, speed: Double, isPaused: Boolean) {
        val now = System.currentTimeMillis()
        if (now - lastEmitTime >= 250) { // Throttle to 4 Hz
            lastEmitTime = now
            val map = mapOf(
                "taskId" to taskId,
                "downloadedBytes" to downloaded,
                "totalBytes" to total,
                "speedBytesPerSec" to speed,
                "isPaused" to isPaused
            )
            onUpdateListener?.invoke(map)
            updateForegroundState()
        }
    }

    private fun formatSpeed(bytesPerSec: Double): String {
        if (bytesPerSec <= 0) return "0 B/s"
        val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s")
        var b = bytesPerSec
        var i = 0
        while (b >= 1024 && i < units.size - 1) {
            b /= 1024
            i++
        }
        return String.format("%.1f %s", b, units[i])
    }

    override fun onDestroy() {
        networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        activeTasks.values.forEach { it.cancel() }
        executor.shutdownNow()
        super.onDestroy()
    }

    // --- WORKER CLASS RUNNING HTTP RANGE THREADS WITH 64 KB BOUNDED MEMORY ---
    inner class DownloadWorker(
        val taskId: String,
        val urlString: String,
        val fileName: String,
        val savePath: String,
        var totalBytes: Long,
        val connectionCount: Int,
        val category: String,
        var etag: String?,
        var lastModified: String?
    ) : Runnable {

        val isPaused = AtomicBoolean(false)
        val isCancelled = AtomicBoolean(false)
        var downloadedBytes: Long = 0
        var currentSpeedBytesPerSec: Double = 0.0

        fun pause() {
            isPaused.set(true)
        }

        fun resume() {
            isPaused.set(false)
        }

        fun cancel() {
            isCancelled.set(true)
        }

        override fun run() {
            try {
                val file = File(savePath)
                file.parentFile?.mkdirs()

                var existingBytes = 0L
                if (file.exists()) {
                    existingBytes = file.length()
                }
                downloadedBytes = existingBytes

                val url = URL(urlString)
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 15000
                conn.readTimeout = 20000
                conn.setRequestProperty("User-Agent", "NetGet/1.0 (Android; en-US)")
                conn.setRequestProperty("Accept-Encoding", "identity")

                if (existingBytes > 0) {
                    conn.setRequestProperty("Range", "bytes=$existingBytes-")
                    if (etag != null) {
                        conn.setRequestProperty("If-Range", etag)
                    } else if (lastModified != null) {
                        conn.setRequestProperty("If-Range", lastModified)
                    }
                }

                conn.connect()
                val responseCode = conn.responseCode

                if (responseCode == HttpURLConnection.HTTP_PARTIAL) {
                    val len = conn.contentLength.toLong()
                    if (len > 0) totalBytes = existingBytes + len
                } else if (responseCode == HttpURLConnection.HTTP_OK) {
                    existingBytes = 0
                    downloadedBytes = 0
                    totalBytes = conn.contentLength.toLong()
                    etag = conn.getHeaderField("ETag")
                    lastModified = conn.getHeaderField("Last-Modified")
                } else if (responseCode >= 400) {
                    dbHelper.updateStatus(taskId, "failed")
                    conn.disconnect()
                    return
                }

                val raf = RandomAccessFile(file, "rw")
                if (totalBytes > 0 && raf.length() < totalBytes) {
                    try {
                        raf.setLength(totalBytes) // Pre-allocate file space
                    } catch (_: Exception) {}
                }
                raf.seek(existingBytes)

                val inputStream: InputStream = conn.inputStream
                val buffer = ByteArray(65536) // Fixed 64 KB bounded buffer
                var bytesRead: Int

                var bytesSinceTick = 0L
                var lastTickTime = System.currentTimeMillis()

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    if (isCancelled.get()) {
                        raf.close()
                        inputStream.close()
                        conn.disconnect()
                        return
                    }

                    if (isPaused.get()) {
                        raf.close()
                        inputStream.close()
                        conn.disconnect()
                        dbHelper.updateProgress(taskId, downloadedBytes, 0.0, 0)
                        notifyProgress(taskId, downloadedBytes, totalBytes, 0.0, true)
                        return
                    }

                    raf.write(buffer, 0, bytesRead)
                    downloadedBytes += bytesRead
                    bytesSinceTick += bytesRead

                    val now = System.currentTimeMillis()
                    val diff = now - lastTickTime
                    if (diff >= 500) {
                        currentSpeedBytesPerSec = (bytesSinceTick.toDouble() / diff) * 1000.0
                        lastTickTime = now
                        bytesSinceTick = 0
                        notifyProgress(taskId, downloadedBytes, totalBytes, currentSpeedBytesPerSec, false)
                    }
                }

                raf.close()
                inputStream.close()
                conn.disconnect()

                if (!isPaused.get() && !isCancelled.get()) {
                    dbHelper.updateStatus(taskId, "completed", System.currentTimeMillis())
                    dbHelper.updateProgress(taskId, downloadedBytes, 0.0, 0)
                    notificationHelper.notifyCompleted(taskId.hashCode(), fileName, savePath)
                    activeTasks.remove(taskId)
                    updateForegroundState()
                }
            } catch (e: Exception) {
                dbHelper.updateStatus(taskId, "failed")
                updateForegroundState()
            }
        }
    }
}
