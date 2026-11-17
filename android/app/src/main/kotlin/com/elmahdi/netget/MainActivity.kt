package com.elmahdi.netget

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        const val METHOD_CHANNEL = "com.elmahdi.netget/engine"
        const val EVENT_CHANNEL = "com.elmahdi.netget/events"
        private const val REQUEST_CODE_POST_NOTIFICATIONS = 2001
    }

    private var downloadService: DownloadService? = null
    private var isBound = false
    private var eventSink: EventChannel.EventSink? = null
    private var pendingIntentUrl: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        var engine = FlutterEngineCache.getInstance().get(DownloadService.CACHED_ENGINE_ID)
        if (engine == null) {
            engine = FlutterEngine(context)
            FlutterEngineCache.getInstance().put(DownloadService.CACHED_ENGINE_ID, engine)
        }
        return engine
    }

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
                "startDownload", "pauseDownload", "resumeDownload", "cancelDownload" -> {
                    result.success(true)
                }
                "setAutoResumeOnBoot" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val prefs = getSharedPreferences("netget_settings", Context.MODE_PRIVATE)
                    prefs.edit().putBoolean("auto_resume_on_boot", enabled).apply()
                    result.success(true)
                }
                "setSpeedLimit" -> {
                    val limit = (call.argument<Number>("bytesPerSec") ?: 0).toLong()
                    downloadService?.globalSpeedLimitBytesPerSec = limit
                    result.success(true)
                }
                "setSoundsEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    downloadService?.notificationHelper?.setSoundsEnabled(enabled)
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
                        val percent = call.argument<Int>("percent") ?: 0
                        val name = call.argument<String>("name") ?: ""
                        val totalBytes = (call.argument<Number>("totalBytes") ?: -1L).toLong()
                        downloadService?.updateDartActiveDownloads(
                            count = count,
                            progressText = progressText,
                            percent = percent,
                            fileName = name,
                            totalBytes = totalBytes
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error(
                            "FGS_NOT_ALLOWED",
                            "Foreground service update failed: ${e.message}",
                            e.javaClass.name
                        )
                    }
                }
                "notifyDownloadCompleted" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val savePath = call.argument<String>("savePath") ?: ""
                    downloadService?.notificationHelper?.notifyCompleted(taskId.hashCode(), fileName, savePath)
                    result.success(true)
                }
                "notifyDownloadFailed" -> {
                    val taskId = call.argument<String>("taskId") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val errorMessage = call.argument<String>("errorMessage") ?: "Download failed"
                    downloadService?.notificationHelper?.notifyFailed(taskId.hashCode(), taskId, fileName, errorMessage)
                    result.success(true)
                }
                "playSound" -> {
                    val sound = call.argument<String>("sound") ?: ""
                    downloadService?.notificationHelper?.playSound(sound)
                    result.success(true)
                }
                "checkNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        val isGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (isGranted) {
                            result.success("granted")
                        } else {
                            val shouldShow = ActivityCompat.shouldShowRequestPermissionRationale(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS
                            )
                            result.success(if (shouldShow) "denied" else "not_determined")
                        }
                    } else {
                        val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
                        result.success(if (enabled) "granted" else "denied")
                    }
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        val isGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (isGranted) {
                            result.success("granted")
                        } else {
                            pendingPermissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQUEST_CODE_POST_NOTIFICATIONS
                            )
                        }
                    } else {
                        val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
                        result.success(if (enabled) "granted" else "denied")
                    }
                }
                "openNotificationSettings" -> {
                    try {
                        val intent = Intent()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            intent.action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                            intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        } else {
                            intent.action = "android.settings.APP_NOTIFICATION_SETTINGS"
                            intent.putExtra("app_package", packageName)
                            intent.putExtra("app_uid", applicationInfo.uid)
                        }
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }
                "getFreeDiskSpace" -> {
                    val path = call.argument<String>("path") ?: getExternalFilesDir(null)?.absolutePath ?: filesDir.absolutePath
                    try {
                        val stat = android.os.StatFs(path)
                        val availableBytes = stat.availableBlocksLong * stat.blockSizeLong
                        result.success(availableBytes)
                    } catch (e: Exception) {
                        result.error("STATFS_FAILED", e.message, null)
                    }
                }
                "openFile" -> {
                    val filePath = call.argument<String>("path") ?: ""
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                            return@setMethodCallHandler
                        }
                        val extension = file.extension.lowercase()
                        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
                        val contentUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri, mimeType)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", e.message, null)
                    }
                }
                "shareFile" -> {
                    val filePath = call.argument<String>("path") ?: ""
                    try {
                        val file = File(filePath)
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File does not exist: $filePath", null)
                            return@setMethodCallHandler
                        }
                        val extension = file.extension.lowercase()
                        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
                        val contentUri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, contentUri)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(Intent.createChooser(intent, file.name))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message, null)
                    }
                }
                "getDeviceOemInfo" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                    } else {
                        true
                    }
                    val info = mapOf(
                        "manufacturer" to Build.MANUFACTURER.lowercase(),
                        "brand" to Build.BRAND.lowercase(),
                        "model" to Build.MODEL,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "isBatteryOptimizationIgnored" to isIgnored
                    )
                    result.success(info)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Fallback to general battery optimization screen
                            try {
                                val fallbackIntent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(fallbackIntent)
                                result.success(true)
                            } catch (err: Exception) {
                                result.error("BATTERY_OPT_ERROR", err.message, null)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                "openOemBatterySettings" -> {
                    val mfr = Build.MANUFACTURER.lowercase()
                    val intentsToTry = mutableListOf<Intent>()

                    when {
                        mfr.contains("xiaomi") || mfr.contains("redmi") || mfr.contains("poco") -> {
                            intentsToTry.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")))
                            intentsToTry.add(Intent().setComponent(ComponentName("com.miui.securitycenter", "com.miui.powercenter.PowerSettings")))
                        }
                        mfr.contains("huawei") || mfr.contains("honor") -> {
                            intentsToTry.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity")))
                            intentsToTry.add(Intent().setComponent(ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity")))
                        }
                        mfr.contains("samsung") -> {
                            intentsToTry.add(Intent().setComponent(ComponentName("com.samsung.android.lool", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                            intentsToTry.add(Intent().setComponent(ComponentName("com.samsung.android.sm", "com.samsung.android.sm.ui.battery.BatteryActivity")))
                        }
                        mfr.contains("transsion") || mfr.contains("tecno") || mfr.contains("infinix") || mfr.contains("itel") -> {
                            intentsToTry.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.MainActivity")))
                            intentsToTry.add(Intent().setComponent(ComponentName("com.transsion.phonemaster", "com.transsion.phonemaster.AutoStartManagementActivity")))
                        }
                        mfr.contains("oppo") || mfr.contains("realme") -> {
                            intentsToTry.add(Intent().setComponent(ComponentName("com.coloros.safecenter", "com.coloros.safecenter.permission.startup.StartupAppListActivity")))
                            intentsToTry.add(Intent().setComponent(ComponentName("com.oppo.safe", "com.oppo.safe.permission.startup.StartupAppListActivity")))
                        }
                        mfr.contains("vivo") -> {
                            intentsToTry.add(Intent().setComponent(ComponentName("com.iqoo.secure", "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity")))
                            intentsToTry.add(Intent().setComponent(ComponentName("com.vivo.permissionmanager", "com.vivo.permissionmanager.activity.BgStartUpManagerActivity")))
                        }
                    }

                    // Generic App Details screen fallback
                    intentsToTry.add(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    })

                    var launched = false
                    for (candidate in intentsToTry) {
                        try {
                            candidate.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(candidate)
                            launched = true
                            break
                        } catch (_: Exception) {}
                    }
                    result.success(launched)
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_POST_NOTIFICATIONS) {
            val res = pendingPermissionResult
            pendingPermissionResult = null
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                res?.success("granted")
            } else {
                val shouldShow = if (Build.VERSION.SDK_INT >= 33) {
                    ActivityCompat.shouldShowRequestPermissionRationale(
                        this,
                        Manifest.permission.POST_NOTIFICATIONS
                    )
                } else {
                    false
                }
                if (!shouldShow) {
                    res?.success("permanently_denied")
                } else {
                    res?.success("denied")
                }
            }
        }
    }

    override fun onDestroy() {
        if (isBound) {
            unbindService(connection)
            isBound = false
        }
        super.onDestroy()
    }
}
