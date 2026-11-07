# Android Background Execution Architecture Plan: User-Initiated Data Transfer (UIDT) vs. Foreground Service

**Document Version:** 1.0.0  
**Target Architecture:** Android 14+ (API 34+) & Android 15+ (API 35+) with legacy fallback (API 21–33)  
**Status:** Architectural Plan & Decision Specification (Implementation Deferred)

---

## 1. Executive Decision: Who Runs the Engine?

### The Core Architectural Dilemma
When Android schedules a background download job via `JobService`, what component executes the actual network sockets and file I/O?
- **Option A:** Kotlin Native Engine inside `JobService`.
- **Option B:** Headless Flutter Engine (`FlutterEngine` background isolate) executing the Dart `MultiConnectionDownloader`.

### Detailed Trade-Off Comparison

| Evaluation Metric | Option A: Native Kotlin Engine | Option B: Headless Flutter Engine |
| :--- | :--- | :--- |
| **Process Memory Footprint (RSS)** | **~15 – 25 MB** (Extremely lightweight) | **~80 – 140 MB** (Heavy Flutter C++ runtime + Dart VM isolate) |
| **Android LMK (Low Memory Killer) Risk** | **Very Low**: Small memory footprint makes process unlikely to be killed during background multitasking. | **High**: Under memory pressure (e.g., user launches camera or heavy 3D game), the 100MB+ Flutter process is a primary LMK target. |
| **Job Startup Latency** | **< 15 ms**: Instant initialization inside `JobService.onStartJob()`. | **400 – 900 ms**: Must initialize `FlutterLoader`, load AOT assets, launch background isolate, establish channels. |
| **Lifecycle & Termination Handling** | **Deterministic POSIX/Java handles**: `onStopJob()` synchronously closes sockets, flushes file descriptors, and persists state in milliseconds. | **Fragile async isolate teardown**: If system cancels job, Dart isolate may be terminated mid-event loop before completing asynchronous file flushes. |
| **Code Duplication** | Requires maintaining network/file pipeline in Kotlin and UI in Dart. | Single codebase for engine (`MultiConnectionDownloader` in Dart). |
| **Headless Battery Efficiency** | Zero UI runtime overhead; optimal CPU wakelock management. | Dart isolate overhead runs event loop continuously in background. |

### The Authoritative Decision
**Option A (Kotlin Native Engine) is chosen for background execution.**  
For a professional, utility-grade download manager competing with ADM:
1. When the app is in the **foreground/interactive state**, Flutter displays live progress, metrics, and segmented charts.
2. When a download runs or transitions to **background execution**, the native Android `JobService` (API 34+) or `Foreground Service` (API <= 33) manages the transfer using native thread pools and file descriptors (`RandomAccessFile`).
3. State is coordinated via SQLite (`netget_native.db`), serving as the authoritative single source of truth across process restarts.

---

## 2. API 34+ User-Initiated Data Transfer (UIDT) Requirements

### 2.1 Why UIDT is Mandatory on Android 15 (TargetSdk 35)
On Android 15 (API 35), Google enforces a strict **6-hour limit per 24 hours** for `foregroundServiceType="dataSync"`. When an app exceeds this window:
- Android triggers `Service.onTimeout(int, int)`. *(verify in docs)*
- If the service fails to stop immediately, Android terminates the app with an `ANR / Crash`.

User-Initiated Data Transfer (UIDT) jobs introduced in Android 14 (API 34) **do not have the 6-hour limit** and are specifically designed for long-running, user-visible downloads.

### 2.2 Strict Android Constraints for UIDT

1. **Foreground-Initiated Only**:
   - UIDT jobs **MUST be scheduled while the app is in the foreground** (an active visible Activity) or from an allowed foreground-equivalent state.
   - Attempting to call `JobScheduler.schedule()` with `setUserInitiated(true)` while in the background throws `IllegalStateException`. *(verify in docs)*
2. **Required Manifest Permissions**:
   ```xml
   <!-- Mandatory for User-Initiated Data Transfer on API 34+ (verify in docs) -->
   <uses-permission android:name="android.permission.RUN_USER_INITIATED_JOBS" />
   
   <!-- Mandatory for foreground service fallback on API 33 and below (verify in docs) -->
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
   
   <!-- User notification permission on API 33+ (verify in docs) -->
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```
3. **Mandatory User Notification**:
   - A user-initiated job **must** provide a notification via `JobService.setNotification()` *(verify in docs)* immediately inside `onStartJob()`.
   - The notification must clearly identify the active transfer, show an accurate progress bar, and provide actionable controls (Pause, Cancel).
4. **Network Constraints Specification**:
   - The job must specify network requirements via `JobInfo.Builder.setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)` or `JobInfo.NETWORK_TYPE_UNMETERED` (Wi-Fi only setting). *(verify in docs)*
   - `JobInfo.Builder.setEstimatedNetworkBytes(downloadBytes, uploadBytes)` should be populated with the total file size to assist the OS in network budgeting. *(verify in docs)*

---

## 3. Native JobService Specification (`DownloadJobService.kt`)

### 3.1 Job Scheduling Interface
```kotlin
// API signature: JobScheduler.schedule() with UIDT (verify in docs)
fun scheduleDownloadJob(context: Context, taskId: String, totalBytes: Long, unmeteredOnly: Boolean) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) { // API 34+
        val componentName = ComponentName(context, DownloadJobService::class.java)
        val networkType = if (unmeteredOnly) JobInfo.NETWORK_TYPE_UNMETERED else JobInfo.NETWORK_TYPE_ANY
        
        val jobInfo = JobInfo.Builder(taskId.hashCode(), componentName)
            .setUserInitiated(true) // (verify in docs)
            .setDataTransfer(true)  // (verify in docs)
            .setRequiredNetworkType(networkType)
            .setEstimatedNetworkBytes(totalBytes, 0L) // (verify in docs)
            .build()

        val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
        jobScheduler.schedule(jobInfo)
    } else {
        // Fallback for API <= 33: Start Foreground Service
        startLegacyForegroundService(context, taskId)
    }
}
```

### 3.2 Service Implementation and Termination Handling
```kotlin
// API signature: JobService with onStartJob / onStopJob (verify in docs)
class DownloadJobService : JobService() {
    private val activeDownloadEngines = ConcurrentHashMap<Int, NativeDownloadWorker>()

    override fun onStartJob(params: JobParameters): Boolean {
        val taskId = params.jobId // or parsed from extras (verify in docs)
        
        // 1. Immediately post user-visible notification
        val notification = NotificationHelper.createProgressNotification(this, taskId)
        setNotification(params, notification.id, notification.build(), JobService.JOB_END_NOTIFICATION_POLICY_DETACH) // (verify in docs)

        // 2. Launch concurrent download worker on background IO dispatcher
        val worker = NativeDownloadWorker(taskId)
        activeDownloadEngines[params.jobId] = worker

        CoroutineScope(Dispatchers.IO).launch {
            try {
                worker.execute()
                jobFinished(params, false) // Finished successfully, do not reschedule (verify in docs)
            } catch (e: Exception) {
                val shouldRetry = worker.isResumableError(e)
                jobFinished(params, shouldRetry) // (verify in docs)
            } finally {
                activeDownloadEngines.remove(params.jobId)
            }
        }
        return true // Work is running asynchronously (verify in docs)
    }

    override fun onStopJob(params: JobParameters): Boolean {
        // Invoked by the OS when constraints are lost (Wi-Fi dropped, battery saver, etc.)
        val worker = activeDownloadEngines.remove(params.jobId)
        
        // 1. Determine OS stop reason
        val reason = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.stopReason // (verify in docs)
        } else {
            -1
        }
        
        // 2. Synchronously abort sockets and FLUSH file descriptors to disk
        worker?.abortAndFlush()
        
        // 3. Persist segment state checkpoints to SQLite
        worker?.saveCheckpoint()

        // 4. Return true to request JobScheduler to reschedule when constraint is restored
        return true // Reschedule job automatically (verify in docs)
    }
}
```

---

## 4. Legacy Android Fallback (API <= 33)

### Strategy
For Android versions below Android 14 (API 21 to 33):
- Use `ServiceCompat.startForeground()` inside `DownloadService.kt`.
- Set `foregroundServiceType="dataSync"`.
- Because API <= 33 target/runtime environments **do not enforce the 6-hour dataSync timeout**, long-running downloads operate without OS eviction as long as the foreground notification is active.
- Listen to `ConnectivityManager.NetworkCallback` *(verify in docs)* to pause when network connectivity is lost, and resume automatically when reconnected.

---

## 5. Verification Checklist for Implementation Phase

When implementing this native background bridge in a future sprint:
- [ ] Verify `RUN_USER_INITIATED_JOBS` permission in official Android 14+ documentation.
- [ ] Verify `JobInfo.Builder.setUserInitiated(true)` behavior on Samsung OneUI / Xiaomi MIUI battery management.
- [ ] Verify `params.stopReason` constants (`STOP_REASON_CONSTRAINT_CONNECTIVITY`, `STOP_REASON_USER_ACTION`).
- [ ] Verify SQLite write locking (`WAL` mode) between Flutter isolate and native `JobService` process.
- [ ] Test network toggle (Airplane mode on/off) during active multi-connection background transfer.
