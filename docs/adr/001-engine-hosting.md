# ADR 001: Background Engine Hosting Architecture

## Status
Accepted

## Context
In the current NetGet implementation, the Dart `DownloadManager` and `MultiConnectionDownloader` run on the main isolate of `MainActivity`'s `FlutterEngine`. When the user swipes the app from Android's recent apps list, the Activity is destroyed, and the Flutter runtime along with all Dart isolates is terminated.

Although a native Kotlin `DownloadService` runs as a foreground service with `foregroundServiceType="dataSync"`, the Kotlin service only received periodic UI progress callbacks from Dart (`updateActiveDownloads`). It did not execute the downloads. Consequently, swiping the app from recents created a "zombie notification" where the Android notification claimed progress while the actual download was dead.

Furthermore, a separate legacy Kotlin download worker existed in `DownloadService.kt` and `DownloadDatabaseHelper.kt` with divergent logic, creating code duplication and synchronization hazards.

## Decision
We implement **Option A** as recommended:
1. The native foreground `DownloadService` manages a headless `FlutterEngine` (cached via `FlutterEngineCache.getInstance()`) executing a background Dart entrypoint annotated with `@pragma('vm:entry-point') void downloadServiceMain()`.
2. The background engine isolate hosts the single `DownloadManager`, the SQLite database, and the `SegmentedDownloader` engine.
3. The UI in `MainActivity` connects to this service via a lightweight `DownloadClient` abstraction over platform channels/ports. When the UI is visible, it consumes live aggregate progress streams (<= 4 Hz). When the UI is destroyed, the background engine continues uninterrupted.
4. When all active transfers complete or are paused, the background service stops foreground mode and releases the engine if idle.
5. On Android 14+ (API 34+), foreground service type `dataSync` is declared, and user-initiated data transfer jobs (`JobInfo.Builder.setUserInitiated(true)`) are supported for user-started downloads.
6. The dead legacy Kotlin downloader and SQLite helper are decommissioned and removed.

## Consequences
- **Positive:** Active downloads continue running reliably when the app is swiped from recents or when the Activity is reclaimed under memory pressure.
- **Positive:** Single, unified Dart engine codebase (`SegmentedDownloader`) handles all network, segmentation, throttling, and persistence logic.
- **Positive:** Eliminates zombie notifications: foreground notifications strictly reflect actual active engine tasks.
- **Trade-off:** The headless `FlutterEngine` requires ~20-30 MB of RAM while downloads are active. This is well within budget for targeted devices and is cleanly released when downloads finish.
