# Changelog

All notable changes to the NetGet project are documented in this file.

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

### Known Limitations
- **Android 15 Foreground Service dataSync Limit**: Android 15 (API 35+) enforces a 6-hour cumulative dataSync runtime budget per 24 hours. NetGet implements `onTimeout` to safely pause tasks and post a resumable notification when the budget expires.
- **UIDT Not Implemented**: User-Initiated Data Transfer Jobs are architected but not yet implemented; background execution currently uses the native foreground service dataSync channel.
- **Loopback Benchmarks**: Test suite benchmarks were evaluated on local loopback (zero latency, high context switching); physical cellular and high-latency WAN links will exhibit different scaling characteristics.
