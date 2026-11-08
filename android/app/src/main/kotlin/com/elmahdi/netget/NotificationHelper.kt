package com.elmahdi.netget

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import java.io.File

class NotificationHelper(private val context: Context) {

    companion object {
        const val PROGRESS_CHANNEL_ID = "ndm_progress_channel"
        const val PROGRESS_CHANNEL_NAME = "NDM Download Progress"
        const val STATUS_CHANNEL_ID = "ndm_status_channel"
        const val STATUS_CHANNEL_NAME = "NDM Transfer Status"
        const val CHANNEL_ID = PROGRESS_CHANNEL_ID
        const val CHANNEL_NAME = PROGRESS_CHANNEL_NAME
        const val SUMMARY_NOTIFICATION_ID = 1001

        const val ACTION_PAUSE = "com.elmahdi.netget.ACTION_PAUSE"
        const val ACTION_RESUME = "com.elmahdi.netget.ACTION_RESUME"
        const val ACTION_CANCEL = "com.elmahdi.netget.ACTION_CANCEL"
        const val EXTRA_TASK_ID = "task_id"
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private var soundPool: SoundPool? = null
    private var soundStartId = 0
    private var soundCompleteId = 0
    private var soundFailedId = 0
    private var soundQueueDoneId = 0
    private var soundsEnabled = true

    init {
        createNotificationChannel()
        initSoundPool()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Low-importance channel for ongoing progress (no sound, no vibration)
            val progressChannel = NotificationChannel(
                PROGRESS_CHANNEL_ID,
                PROGRESS_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows live download speeds and transfer progress"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(progressChannel)

            // Default-importance channel for completed and failed notifications
            val statusChannel = NotificationChannel(
                STATUS_CHANNEL_ID,
                STATUS_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Notifies when downloads complete or fail"
                setShowBadge(true)
            }
            notificationManager.createNotificationChannel(statusChannel)
        }
    }

    private fun initSoundPool() {
        try {
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            soundPool = SoundPool.Builder()
                .setMaxStreams(3)
                .setAudioAttributes(audioAttributes)
                .build()

            val res = context.resources
            val pkg = context.packageName

            val startRes = res.getIdentifier("sound_start", "raw", pkg)
            if (startRes != 0) soundStartId = soundPool?.load(context, startRes, 1) ?: 0

            val compRes = res.getIdentifier("sound_complete", "raw", pkg)
            if (compRes != 0) soundCompleteId = soundPool?.load(context, compRes, 1) ?: 0

            val failRes = res.getIdentifier("sound_failed", "raw", pkg)
            if (failRes != 0) soundFailedId = soundPool?.load(context, failRes, 1) ?: 0

            val qRes = res.getIdentifier("sound_queue_done", "raw", pkg)
            if (qRes != 0) soundQueueDoneId = soundPool?.load(context, qRes, 1) ?: 0
        } catch (_: Exception) {}
    }

    fun playSound(type: String) {
        if (!soundsEnabled) return
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager?.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
            return // Respect DND / Silent
        }

        val soundId = when (type) {
            "start" -> soundStartId
            "complete" -> soundCompleteId
            "failed" -> soundFailedId
            "queue_done" -> soundQueueDoneId
            else -> 0
        }
        if (soundId != 0) {
            soundPool?.play(soundId, 0.7f, 0.7f, 1, 0, 1.0f)
        }
    }

    fun setSoundsEnabled(enabled: Boolean) {
        soundsEnabled = enabled
    }

    fun buildSummaryNotification(
        activeCount: Int,
        totalSpeedStr: String = "",
        completedCount: Int = 0,
        percent: Int = 0,
        fileName: String? = null,
        totalBytes: Long = -1L
    ): Notification {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title: String
        val contentText: String
        val subText: String?

        if (activeCount > 0) {
            val speedPart = if (totalSpeedStr.isNotBlank()) " • $totalSpeedStr" else ""
            if (activeCount == 1 && !fileName.isNullOrEmpty()) {
                title = fileName
                if (totalBytes > 0) {
                    contentText = "$percent%$speedPart"
                    subText = "$percent%"
                } else {
                    contentText = if (totalSpeedStr.isNotBlank()) "In progress • $totalSpeedStr" else "In progress"
                    subText = "Active"
                }
            } else {
                title = "$activeCount active downloads"
                if (totalBytes > 0) {
                    contentText = "$percent%$speedPart"
                    subText = "$percent%"
                } else {
                    contentText = if (totalSpeedStr.isNotBlank()) totalSpeedStr else "In progress"
                    subText = "$activeCount tasks"
                }
            }
        } else {
            title = "NetGet"
            contentText = "All transfers finished"
            subText = null
        }

        val isIndeterminate = activeCount > 0 && totalBytes <= 0
        val progressVal = if (isIndeterminate) 0 else percent.coerceIn(0, 100)

        val smallIcon = context.resources.getIdentifier("ic_stat_download", "drawable", context.packageName).let {
            if (it != 0) it else android.R.drawable.stat_sys_download
        }

        val builder = NotificationCompat.Builder(context, PROGRESS_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(title)
            .setContentText(contentText)
            .setContentIntent(pendingIntent)
            .setProgress(100, progressVal, isIndeterminate)
            .setOngoing(activeCount > 0)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setColor(0xFF176BFF.toInt())
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (!subText.isNullOrEmpty()) {
            builder.setSubText(subText)
        }

        return builder.build()
    }

    fun notifySummary(notificationId: Int, notification: Notification) {
        try {
            notificationManager.notify(notificationId, notification)
        } catch (_: Exception) {
            // Safe when POST_NOTIFICATIONS is denied on Android 13+ (verify in docs)
        }
    }

    fun buildTaskProgressNotification(
        notificationId: Int,
        taskId: String,
        fileName: String,
        downloadedBytes: Long,
        totalBytes: Long,
        speedStr: String,
        etaStr: String,
        isPaused: Boolean
    ): Notification {
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val appPendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Action: Pause or Resume
        val toggleAction = if (isPaused) {
            val resumeIntent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_RESUME
                putExtra(EXTRA_TASK_ID, taskId)
            }
            val resumePending = PendingIntent.getService(
                context,
                notificationId * 10 + 1,
                resumeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_media_play,
                "Resume",
                resumePending
            ).build()
        } else {
            val pauseIntent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_PAUSE
                putExtra(EXTRA_TASK_ID, taskId)
            }
            val pausePending = PendingIntent.getService(
                context,
                notificationId * 10 + 2,
                pauseIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            NotificationCompat.Action.Builder(
                android.R.drawable.ic_media_pause,
                "Pause",
                pausePending
            ).build()
        }

        // Action: Cancel
        val cancelIntent = Intent(context, DownloadService::class.java).apply {
            action = ACTION_CANCEL
            putExtra(EXTRA_TASK_ID, taskId)
        }
        val cancelPending = PendingIntent.getService(
            context,
            notificationId * 10 + 3,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val cancelAction = NotificationCompat.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "Cancel",
            cancelPending
        ).build()

        val progress = if (totalBytes > 0) ((downloadedBytes * 100) / totalBytes).toInt() else 0
        val contentText = if (isPaused) {
            "Paused • ${formatBytes(downloadedBytes)}"
        } else {
            if (totalBytes > 0) "$progress% • $speedStr • ETA $etaStr" else "$speedStr • ETA $etaStr"
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.resources.getIdentifier("ic_stat_download", "drawable", context.packageName).let {
                if (it != 0) it else android.R.drawable.stat_sys_download
            })
            .setContentTitle(fileName)
            .setContentText(contentText)
            .setContentIntent(appPendingIntent)
            .setProgress(100, progress, totalBytes <= 0)
            .setOngoing(!isPaused)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setColor(0xFF176BFF.toInt())
            .addAction(toggleAction)
            .addAction(cancelAction)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (totalBytes > 0) {
            builder.setSubText("$progress%")
        }

        return builder.build()
    }

    fun notifyCompleted(notificationId: Int, fileName: String, savePath: String) {
        try {
            val file = File(savePath)
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                setDataAndType(Uri.fromFile(file), "*/*")
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val notification = NotificationCompat.Builder(context, STATUS_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle("Download Complete")
                .setContentText(fileName)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setColor(0xFF39E75F.toInt())
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()

            notificationManager.notify(notificationId, notification)
            playSound("complete")
        } catch (_: Exception) {
            // Safe when POST_NOTIFICATIONS is denied on Android 13+ (verify in docs)
        }
    }

    fun notifyFailed(notificationId: Int, taskId: String, fileName: String, errorMessage: String) {
        try {
            val appIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("taskId", taskId)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val errorDetail = if (errorMessage.isNotBlank()) "$fileName: $errorMessage" else fileName
            val notification = NotificationCompat.Builder(context, STATUS_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle("Download Failed")
                .setContentText(errorDetail)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setColor(0xFFD32F2F.toInt())
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()

            notificationManager.notify(notificationId, notification)
            playSound("failed")
        } catch (_: Exception) {
            // Safe when POST_NOTIFICATIONS is denied on Android 13+ (verify in docs)
        }
    }

    fun notifyTimeout(notificationId: Int) {
        val resumeIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            resumeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("Download Paused (System 6h timeout)")
            .setContentText("Tap to resume your active downloads")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        notificationManager.notify(notificationId, notification)
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes <= 0) return "0 B"
        val units = arrayOf("B", "KB", "MB", "GB", "TB")
        var b = bytes.toDouble()
        var i = 0
        while (b >= 1024 && i < units.size - 1) {
            b /= 1024
            i++
        }
        return String.format("%.1f %s", b, units[i])
    }
}
