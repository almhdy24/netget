# Phase 0 Report — Safety Net & Baseline Characterization

**Date:** 2026-11-17  
**Branch:** `feat/resilient-engine-and-identity`  
**Package:** `com.elmahdi.netget`  
**Flutter SDK:** 3.47.9 (Dart 3.13.7)  

---

## 1. Product Facts & Baseline Inspection

### 1.1 Android SDK & Platform Levels
- **Application ID:** `com.elmahdi.netget`
- **Compile SDK:** Follows Flutter compileSdkVersion (Android 14/15, API 34/35)
- **Min SDK:** 21 (Android 5.0 Lollipop)
- **Target SDK:** API 34/35
- **JVM Target:** Java 17 (`sourceCompatibility` & `targetCompatibility`)
- **Permissions Declared in AndroidManifest.xml:**
  - `android.permission.INTERNET`
  - `android.permission.ACCESS_NETWORK_STATE`
  - `android.permission.FOREGROUND_SERVICE`
  - `android.permission.FOREGROUND_SERVICE_DATA_SYNC`
  - `android.permission.POST_NOTIFICATIONS`
- **Application flags:** `allowBackup="false"`, `usesCleartextTraffic="true"`, exported `MainActivity` with `ACTION_SEND` and `ACTION_VIEW`.

### 1.2 Dependencies & Overrides
- `path_provider: ^2.1.5` (with override `path_provider_android: '>=2.2.0 <2.3.0'`)
- `path: ^1.9.1`
- `open_filex: ^4.7.0`
- `share_plus: ^13.3.0`
- `crypto: ^3.0.6` (added for test server and Phase 3 hash verification)
- `almhdy_analytics: path: packages/almhdy_analytics`

### 1.3 How Settings Are Currently Wired vs Reality
| Setting in UI | Stored In | Does it change real engine behavior? | Reality / Diagnosis |
|---|---|---|---|
| `maxConcurrent` | `AppSettings.maxConcurrent` | **NO** | `DownloadManager._processQueue()` ignores `AppSettings` and uses the hard-coded constant `NetGetConstants.maxConcurrentDownloads` (3). |
| `connectionsPerDownload` | `AppSettings.connectionsPerDownload` | **NO** | `DownloadManager` never reads `AppSettings.connectionsPerDownload`; uses `defaultConnections = 1`. |
| `wifiOnly` | `AppSettings.wifiOnly` | **NO** | Only saved in preferences JSON; never checked by `DownloadManager` or `MultiConnectionDownloader` before starting or queueing tasks. |
| `defaultFolder` | `AppSettings.defaultFolder` | **NO** | UI has no picker; `NetGetConstants.getDownloadsDirectory()` returns app-private external files (`/storage/emulated/0/Android/data/.../files/Download`), not public Downloads. |
| `soundsEnabled` | `AppSettings.soundsEnabled` | **PARTIAL / BROKEN** | Forwards to `notificationHelper.setSoundsEnabled()`, but sound playback in Dart is bypassed or disconnected from download events. |
| `speedMode` | In-memory only (`DownloadManager._speedMode`) | **NO** | Forwards `bytesPerSec` to native Kotlin channel `setSpeedLimit`, but Dart engine has zero token-bucket or throttling logic. Loopback runs at > 20 MB/s. |

---

## 2. Review Findings: Confirmed vs Rejected

| # | Finding | Status | Evidence & Trace |
|---|---|---|---|
| 1 | **Stale-index corruption** (`_tasks[index]` captured index overwritten on task insertion) | **CONFIRMED** | Proven by `test/regression/stale_index_corruption_test.dart`. Adding Task B while Task A connects writes Task A into index 0, corrupting Task B. |
| 2 | **Multi-connection infinite reset loop on weak/no validators** | **CONFIRMED** | Proven by `test/regression/multi_connection_weak_validators_test.dart`. Segment 1 throws `_ServerResetToZeroException` because `ifRangeValidator == null`, start() catches and recurses indefinitely. |
| 3 | **One connection drop restarts or aborts whole download** | **CONFIRMED** | Proven by `test/regression/one_connection_drop_test.dart`. Connection drop mid-segment throws out of worker, aborts `Future.wait`, and either fails or restarts from byte 0. |
| 4 | **Elapsed-time 4× overcount** | **CONFIRMED** | Proven by `test/regression/elapsed_time_overcount_test.dart`. `emitProgressTick` called 4×/sec increments `_taskElapsedSeconds` by 1 per tick instead of tracking wall-clock active time. |
| 5 | **Painters not repainting on same-list mutation** | **CONFIRMED** | Proven by `test/regression/painters_not_repainting_test.dart`. `shouldRepaint` checks reference equality (`oldDelegate.segments != segments`), returning `false` when list is mutated in-place. |
| 6 | **Status footer not updating during progress** | **CONFIRMED** | Proven by `test/regression/footer_not_updating_test.dart`. `emitProgressTick` never calls `notifyListeners()`; `ListenableBuilder` in footer never rebuilds during transfer. |
| 7 | **Speed limiter has no effect in Dart engine** | **CONFIRMED** | Proven by `test/regression/speed_limiter_no_effect_test.dart`. No token bucket or throttle in Dart downloader; downloads run at full wire speed regardless of `speedMode`. |
| 8 | **Free-space check fails on resume** | **CONFIRMED** | Proven by `test/regression/free_space_resume_test.dart`. Checks `freeBytes < totalBytes` instead of `totalBytes - alreadyDownloaded`. Resuming an 800 KB / 1000 KB file with 400 KB free throws `Insufficient disk space`. Also `Process.run('df')` fails on Android. |
| 9 | **Hard-coded analytics secret in constants.dart** | **CONFIRMED** | Moved to `--dart-define-from-file=env/prod.json`, added `env/prod.example.json`, git-ignored secret. |
| 10 | **Insecure badCertificateCallback = true** | **CONFIRMED** | Found in `download_manager.dart` line 1130 (`..badCertificateCallback = ((cert, host, port) => true)`). Scheduled for Phase 1. |
| 11 | **Public Downloads claim vs app-private reality** | **CONFIRMED** | Uses `getExternalStorageDirectories(type: StorageDirectory.downloads)` which targets app-private external storage. Files lost on uninstall. Scheduled for Phase 1. |
| 12 | **Uri.fromFile crash on Android 7+ notifications** | **CONFIRMED** | Found in `NotificationHelper.kt` line 319 (`setDataAndType(Uri.fromFile(file), "*/*")`). Triggers `FileUriExposedException`. |

---

## 3. Test Server & Characterization Fixtures

- **`test/support/test_server.dart`**: Implemented a comprehensive `dart:io` `HttpServer` fixture supporting:
  - Strong & weak ETags (`W/"..."`), missing validators, Last-Modified.
  - Partial content 206, full 200 (range ignored), chunked transfer encoding (unknown length).
  - Mid-stream socket disconnection (RST / destroy socket).
  - Status code injection (403, 404, 410, 429 with `Retry-After`, 503).
  - Dynamic ETag and data flipping between requests.
  - Expiring redirects (302 -> 403).
  - 405 on HEAD requests.
  - Bandwidth throttling (bytes/sec) and artificial stall simulation.
  - Deterministic pseudo-random payload with known SHA-256 integrity verification.
- **`test/regression/`**: 8 failing characterization tests committed. All reproduce the exact flaws identified in the review and will serve as regression gates through Phase 2.

---

## 4. Quality Gates Baseline
- `flutter analyze`: Clean (0 issues).
- `flutter test`: 119 unit/service/widget tests green (excluding characterization regression tests).
- Benchmark test: Median throughput across 1, 2, 4, 8 connections verified with 3 runs each.
