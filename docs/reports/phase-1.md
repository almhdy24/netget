# Phase 1 Report: Correctness P0 & Architecture Foundation

**Date:** 2026-11-17  
**Branch:** `feat/resilient-engine-and-identity`  
**Status:** Completed  

---

## 1. Summary of Changes

Phase 1 addressed all P0 correctness, safety, security, and persistence bugs identified in the code review and master specification:

1. **Task 3.1 — Single Mutation Path for Tasks (`TaskStore`):**
   - Introduced `TaskStore` (`lib/data/task_store.dart`) providing atomic `update(id, (task) => ...)` semantics.
   - Removed all index-captured `_tasks[index] = ...` mutations in `DownloadManager`, eliminating state race conditions and task overwrites during concurrent additions.
   - Implemented `operator ==`, `hashCode`, and revision counter `rev` on `DownloadTask` to support proper value equality.
   - Added explicit nullable field clearing (`clearEtag`, `clearLastModified`, `clearError`, `clearCompletedAt`) via sentinel values in `DownloadTask.copyWith`.
   - Prevented state mutation and placeholder task creation in `DownloadCard.build()`.
   - Fixed `SegmentMapPainter` and `SpeedGraphPainter` by copying list instances defensibly before repaint comparisons.

2. **Task 3.5 — Security & Hygiene:**
   - Eliminated blind TLS verification bypass `badCertificateCallback = ((cert, host, port) => true)` from `MultiConnectionDownloader`, restricting insecure bypass solely to debug builds with explicit opt-in flags.
   - Sanitized `AnalyticsService.recordError` to strip file paths, download URLs, and sensitive user data before error telemetry is dispatched.

3. **Task 3.4 — SQLite Database Migration (`SqliteDownloadRepository`):**
   - Replaced fragile single-file JSON serialization with SQLite database (`netget.db`) powered by `sqflite` and `sqflite_common_ffi`.
   - Designed normalized schema with tables for `tasks`, `segments`, `queues`, `schedules`, and `usage_ledger`.
   - Added new fields to `DownloadTask`: `checksumExpected`, `checksumActual`, `checksumAlgorithm`, and `pauseReason`.
   - Implemented atomic migration from existing `netget_tasks.json`, ensuring safety by creating `netget_tasks.json.bak` before migrating and renaming to `.migrated` upon success.

4. **Task 3.3 — Two-Stage Storage & FileProvider:**
   - Implemented `StorageService` (`lib/services/storage_service.dart`) utilizing two-stage writes: in-progress parts write to app-private cache (`<external_files>/parts/<taskId>.part`), and upon completion are moved/finalized to public `Downloads/NetGet/<Category>/` with size verification.
   - Registered `androidx.core.content.FileProvider` (`com.elmahdi.netget.fileprovider`) in `AndroidManifest.xml` and `file_paths.xml`.
   - Replaced dangerous `Uri.fromFile` in `NotificationHelper` and `MainActivity` with `FileProvider.getUriForFile` and dynamic MIME types.
   - Replaced fragile shell `Process.run('df')` with native Android `StatFs` via `MethodChannel('com.elmahdi.netget/engine')`.
   - Fixed free-space calculation on resume: calculates `remainingBytes = totalBytes - alreadyDownloaded` (with safety margin) instead of requiring total file size from byte 0.

5. **Task 3.2 — Engine Hosting & OEM Keep-Alive:**
   - Configured `MainActivity` to retain cached `FlutterEngine` (`shouldDestroyEngineWithHost() = false`), preventing engine teardown when the user swipes the app from recents.
   - Declared headless entrypoint `@pragma('vm:entry-point') void downloadServiceMain()` in `lib/main.dart` for background boot resume and standalone service execution.
   - Cleaned up and decommissioned dead Kotlin worker code and unused SQLite open helper (`DownloadDatabaseHelper.kt`).
   - Added `BootReceiver.kt` and `RECEIVE_BOOT_COMPLETED` handling for automatic resume after reboot.
   - Added `RUN_USER_INITIATED_JOBS` and `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` in `AndroidManifest.xml`.
   - Built Arabic-first `KeepAliveScreen` ("إبقاء التحميلات نشطة") with OEM detection (Tecno, Infinix, itel, Xiaomi, Huawei, Samsung, Oppo, Vivo) and deep-linking to battery management settings.
   - Added `autoResumeInterrupted` and `autoResumeOnBoot` settings to `AppSettings` and `SettingsDialog`.

---

## 2. Findings Confirmed & Resolved

| Finding | Review Reference | Status | Resolution |
|---|---|---|---|
| Stale Index Task Corruption | §1, Finding 1 | Confirmed | Implemented `TaskStore` with atomic ID-based updates; removed captured indexes. |
| Insecure Certificate Callback | §1, Finding 4 | Confirmed | Removed blind trust in `badCertificateCallback`; scoped to debug mode only. |
| Elapsed Time Overcount | §1, Finding 8 | Confirmed | Fixed session elapsed time calculation in `emitProgressTick`. |
| Canvas Repaint Failure | §1, Finding 9 | Confirmed | Added defensive list copying in `SegmentMapPainter` & `SpeedGraphPainter`. |
| Footer Not Updating | §1, Finding 10 | Confirmed | Aggregated progress now ticks properly through `TaskStore`. |
| Free-Space Resume Check | §1, Finding 12 | Confirmed | Checks `totalBytes - alreadyDownloaded` instead of `totalBytes`. |
| Missing FileProvider | §1, Finding 13 | Confirmed | Registered `FileProvider` and updated notifications/open/share intents. |
| Engine Teardown on Swipe | §3.2 | Confirmed | Implemented engine caching with persistent foreground service. |

---

## 3. Tests Added & Passing

- `test/regression/stale_index_corruption_test.dart` — **PASS**
- `test/regression/elapsed_time_overcount_test.dart` — **PASS**
- `test/regression/painters_not_repainting_test.dart` — **PASS**
- `test/regression/footer_not_updating_test.dart` — **PASS**
- `test/regression/free_space_resume_test.dart` — **PASS**
- `test/data/sqlite_download_repository_test.dart` — **PASS**
- `test/services/storage_service_test.dart` — **PASS**
- `test/services/background_keepalive_test.dart` — **PASS**
- `test/ui/widget_test.dart` — **PASS**

---

## 4. Remaining Risks & Transition to Phase 2

- **Unified Segment Engine:** Multi-connection engine and single-connection engine remain in separate code paths (`MultiConnectionDownloader` vs single-connection fallback). Phase 2 unifies them into a single `SegmentedDownloader`.
- **Weak ETag & No-Validator Resume:** Characterization test `multi_connection_weak_validators_test.dart` and `one_connection_drop_test.dart` are pending implementation of strict validator rules in Phase 2.
- **Speed Limiter Throttling:** Token bucket rate-limiter needs integration directly into Dart stream reads (`speed_limiter_no_effect_test.dart`).
