# Google Play Console Foreground Service Declaration (dataSync)

This document provides factual answers for the Google Play Console **Foreground Service Permission Declaration** under `FOREGROUND_SERVICE_DATA_SYNC`.

---

## 1. What user-facing feature requires the Foreground Service?

**User Action & Feature Description**:
- NetGet is a dedicated file download manager.
- The user initiates file downloads by:
  1. Entering or pasting an HTTP/HTTPS file URL into the "Add Download" modal ([`lib/ui/widgets/add_download_sheet.dart:167`](file:///data/data/com.termux/files/home/projects/netget/lib/ui/widgets/add_download_sheet.dart#L167)).
  2. Sharing a downloadable URL to NetGet from external apps (e.g., web browsers) via Android's system share sheet (`ACTION_SEND` / `ACTION_VIEW` in [`android/app/src/main/AndroidManifest.xml:31-55`](file:///data/data/com.termux/files/home/projects/netget/android/app/src/main/AndroidManifest.xml#L31-L55)).
  3. Tapping "Resume" on a previously queued or paused download task in the dashboard ([`lib/services/download_manager.dart:661`](file:///data/data/com.termux/files/home/projects/netget/lib/services/download_manager.dart#L661)).
- When active downloads are running ($N > 0$), NetGet initiates the foreground service with type `dataSync` (`android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC` in [`android/app/src/main/kotlin/com/elmahdi/netget/DownloadService.kt:198-206`](file:///data/data/com.termux/files/home/projects/netget/android/app/src/main/kotlin/com/elmahdi/netget/DownloadService.kt#L198-L206)).

---

## 2. Why must this operation continue running in the background?

**Technical & User Experience Justification**:
- Large file downloads (operating system images, media files, archives, documents) frequently require several minutes to hours to transfer over variable mobile/Wi-Fi connections.
- If the transfer were interrupted when the user switches to another app, receives a phone call, or turns off the device screen, the download would terminate, wasting substantial mobile network bandwidth and requiring re-downloading.
- The foreground service displays an ongoing, persistent notification in the Android notification drawer showing:
  - The number of active downloads.
  - Total real-time transfer speed.
- The foreground service is stopped immediately (`stopForeground(STOP_FOREGROUND_REMOVE)` and `stopSelf()`) as soon as the active download count reaches zero ($N \to 0$ in [`android/app/src/main/kotlin/com/elmahdi/netget/DownloadService.kt:211-218`](file:///data/data/com.termux/files/home/projects/netget/android/app/src/main/kotlin/com/elmahdi/netget/DownloadService.kt#L211-L218)).

---

## 3. What happens when the service times out (Android 15 policy)?

**Android 15 (API 35+) dataSync Policy Handling**:
- Android 15 limits foreground services declared with `dataSync` to a cumulative 6-hour runtime budget within a 24-hour window.
- When Android invokes the timeout callback `DownloadService.onTimeout(startId, fgsType)` ([`android/app/src/main/kotlin/com/elmahdi/netget/DownloadService.kt:88-109`](file:///data/data/com.termux/files/home/projects/netget/android/app/src/main/kotlin/com/elmahdi/netget/DownloadService.kt#L88-L109)):
  1. The native service sends an `onTimeout` event to the Dart engine via `EventChannel` ([`lib/services/download_manager.dart:312-317`](file:///data/data/com.termux/files/home/projects/netget/lib/services/download_manager.dart#L312-L317)).
  2. The Dart engine invokes `pauseAll()`, immediately flushing and closing all `RandomAccessFile` and `HttpClient` connections to preserve downloaded byte offsets without file corruption.
  3. The service calls `stopForeground(STOP_FOREGROUND_DETACH)` and `stopSelf()` to comply with the Android 15 lifecycle requirements.
  4. The application posts a user notification alerting the user that the background transfer budget has elapsed and providing a one-tap action to resume when convenient.
