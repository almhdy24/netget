# Changelog

All notable changes to the NetGet project are documented in this file.

## [1.0.0-rc2] - 2026-11-07

### Added
- **Failure UX & Localized Error Handling**:
  - Centralized error taxonomy (`DownloadFailureCode` / `DownloadFailureHelper`) mapping failures to concise, human-readable localized messages: timeout, connection refused, host unreachable, network loss, HTTP 401/403/404, file changed on server, and storage full (`ENOSPC`).
  - Raw exception text and stack traces preserved solely in detailed task history logs; UI cards display clean user guidance and a prominent "Retry" button.
  - Automatic retry when network is lost with visible "waiting for network" status and background connectivity monitoring.
- **In-Context Notification Permission Flow (Android 13+ `POST_NOTIFICATIONS`)**:
  - Permission is requested contextually on the user's first download initiation rather than at application cold start.
  - Explanatory bottom sheet presented prior to the system permission dialog.
  - Dismissible Home banner fallback when permission is denied, with direct navigation to system notification settings, strictly throttled to at most once per user session.
- **Native Notification Progress Bar & Status Notifications**:
  - Native ongoing foreground notification displaying a real progress bar (`setProgress`), title "NDM", and dynamic content: single downloads show `<filename> - X%` with transfer speed; multiple downloads show aggregate `N downloads - X%`.
  - Progress updates throttled to at most once per second with silent ongoing updates (`setOnlyAlertOnce(true)`).
  - Separate completion and failure notifications posted to a dedicated default channel with tap-to-open actions.
- **Home & Details UX Overhaul**:
  - Sectioned task ordering: Active -> Queued & Paused -> Failed -> Completed with explicit count badges.
  - Simplified cards: 2-line title ellipsis, primary action button per status (Pause / Resume / Retry / Open), with secondary actions accessible via swipe-to-dismiss or long-press bottom sheet.
  - Swipe-to-delete with modal confirmation offering "Also delete file from storage".
  - Empty state with on-tap clipboard paste suggestion chip.
  - Add Download sheet with auto-paste suggestion, detected file name and size via HEAD probe, and segmented connection selector (1, 2, 4 streams; default 1).
  - High-performance, zero-jank UI updates: per-task `ValueNotifier<DownloadTask>` handles ensure high-frequency progress ticks rebuild only the active card rather than the entire dashboard.

### Fixed
- **Stale Error Bug**:
  - Resolved stale error persistence bug across retries, resumes, and new download runs.
  - Implemented explicit `clearError: true` flag in `DownloadTask.copyWith` to guarantee `errorMessage`, `failureCode`, and `errorDetails` are completely erased in memory, on UI cards, and in `netget_tasks.json`.

### Changed
- Display branding renamed to **NDM** (short) and **NetGet Download Manager** (full) across Android application labels, AppBars, About dialog, and localized strings (`en`, `ar`), while keeping package name (`com.elmahdi.netget`), file paths, and platform channel identifiers intact.
- Version bumped to `1.0.0-rc2+2`.

## [1.0.0-rc1] - 2026-11-07

### Added
- **Multi-Connection Download Engine (Beta)**:
  - Concurrent HTTP Range segmented downloads with independent worker streams.
  - Safe concurrent file writes via `ConcurrentFileWriter` utilizing `RandomAccessFile.setPosition()` and `writeFrom()`.
  - Dynamic segment partitioning via `SegmentPlanner` with runtime rebalancing.
  - Periodic durable checkpoints (every 1 second) strictly synchronized with `raf.flush()`.
  - Automatic fallback to single-connection streaming when server ignores `Range` headers (HTTP 200).
  - RFC 7232 / 7233 compliant `If-Range` validation: weak ETags (`W/"..."`) rejected, clean restart from byte 0 on HTTP 200 without error loops, and strict `Content-Range` start boundary validation.
  - Global `HostConnectionPool` enforcing connection limits across all concurrent downloads targeting the same host.
  - Adaptive backoff on HTTP 429 / 503 with `Retry-After` header parsing (clamped to 60 seconds).
  - Storage space safety: handles missing/unreliable `df` metrics gracefully and catches `ENOSPC` (errno 28) during preallocation and streaming, surfacing localized user guidance.
  - Restart safety: prevents corrupted completion of preallocated `.tmp` files with holes; requires full segment verification before rename or restarts from byte 0.
- **Background Execution Architecture Plan**:
  - Comprehensive architectural analysis in `docs/android_background_plan.md` evaluating User-Initiated Data Transfer (UIDT) on Android 14+ vs Foreground Service dataSync fallback.
- **Edge-to-Edge UI & Inset Handling**:
  - Safe padding for Android 3-button navigation bars (48dp) and keyboard IME transitions in `HomeScreen`, `AddDownloadSheet`, and `DownloadDetailsScreen`.
- **CI / CD Automated Release Pipeline**:
  - Tag-triggered GitHub Actions release workflow (`.github/workflows/release.yml`) for `v*` tags with automated linting, test execution, keystore verification, and multi-ABI APK packaging (`universal`, `arm64-v8a`, `armeabi-v7a`, `x86_64`).

### Changed
- Configured default connection count to `1` (stable single-stream path preserved; multi-connection is currently beta).
- Replaced per-tick repository disk saves with throttled saves (maximum 1/s per task, plus immediate saves on pause, cancel, and completion).
- Enforced strict release signing in `android/app/build.gradle.kts` (no silent fallback to debug keystore).
- Disabled R8 minify and resource shrinking (`isMinifyEnabled = false`, `isShrinkResources = false`) for rc1 (R8 off in rc1, untested on device).

### Known Limitations
- **Android 15 Foreground Service dataSync Limit**: Android 15 (API 35+) enforces a 6-hour cumulative dataSync runtime budget per 24 hours. NetGet implements `onTimeout` to safely pause tasks and post a resumable notification when the budget expires.
- **UIDT Not Implemented**: User-Initiated Data Transfer Jobs are architected but not yet implemented; background execution currently uses the native foreground service dataSync channel.
- **Loopback Benchmarks**: Test suite benchmarks were evaluated on local loopback (zero latency, high context switching); physical cellular and high-latency WAN links will exhibit different scaling characteristics.
