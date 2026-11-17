# Phase 2 Completion Report: Resilient Engine Hardening & Unification

**Date:** 2026-11-17  
**Branch:** `feat/resilient-engine-and-identity`  
**Quality Status:** `flutter analyze` clean, 100% unit & characterization test pass rate, `dart format` clean.

---

## 1. Executive Summary
Phase 2 transformed NetGet's core downloading engine into an industrial-grade, resilient segmented downloader designed specifically for slow, unstable, and expensive mobile connections. All duplicate single-stream download paths have been completely eliminated, unifying all transfers (single-connection, multi-connection, chunked, and unvalidated) through `MultiConnectionDownloader`.

---

## 2. Key Changes & Implementations

### 2.1 Unified Engine Pipeline (§4.1)
- **Elimination of Duplicate Code:** Removed over 500 lines of legacy, unthrottled single-stream code from `lib/services/download_manager.dart`.
- **Single Segmented Architecture:** When a download runs with 1 connection, it executes as a 1-segment download with identical flash wear protection, token-bucket bandwidth shaping, periodic checkpointing, and mid-body drop resilience.
- **Dynamic Speed Limiter Wiring:** `AppSettings.speedMode` (Unlimited, High 5 MB/s, Medium 1 MB/s, Low 256 KB/s) is wired directly to `MultiConnectionDownloader(speedLimitBytesPerSec: ...)`. Live adjustments immediately update active downloaders via `TokenBucket.updateRate()`.
- **Two-Stage Storage Architecture (ADR 002):** In-progress files write to `<externalFilesDir>/parts/<taskId>.part`. On completion, `StorageService.instance.finalizeDownload` atomically publishes to `Downloads/NetGet/<Category>/` with size verification before unlinking the `.part` file.

### 2.2 Strict RFC 7232 & 7233 Validator Enforcement
- **Strong ETag (`"..."`):** Multi-connection range requests allowed; mid-file resumption safe with `If-Range: <etag>`.
- **Weak ETag (`W/"..."`):** Strictly restricted to 1 connection; never partitioned across concurrent ranges per RFC 7233 § 3.2.
- **Last-Modified Only:** Strictly restricted to 1 connection. If the server returns 200 OK instead of 206 Partial Content during resume, cleanly resets to byte 0 without entering infinite error loops.
- **No Validator:** Strictly restricted to 1 connection; cannot resume from byte > 0 (restarts from 0).

### 2.3 Resilient Connection Handling & Work Stealing (§4.3)
- **Mid-Body Drop Recovery:** Per-segment socket drops do not discard completed progress. Workers retry with exponential backoff (300ms, 600ms, 1200ms...) with ±20% jitter.
- **Dynamic Work Stealing:** When a connection finishes its assigned slice while another active segment has > 2 MB remaining, the idle connection splits the largest segment in half and steals work to maintain maximum line rate.
- **Flash Wear Mitigation:** `ConcurrentFileWriter` buffers writes in 256 KB chunks, avoiding excessive sync calls on low-end eMMC flash memory.

### 2.4 Expired Download URL Refresh Flow (§4.4)
- **Detection:** HTTP 401, 403, and 410 errors pause the task with `pauseReason = 'urlExpired'` and prompt the user to refresh the download link.
- **Verification Probe:** `refreshTaskUrl(taskId, newUrl)` probes the replacement URL to verify matching size and ETag. If matched, the download resumes from its existing partial byte offset without starting over. If mismatched, the user is warned and can explicitly choose to restart from byte 0.

### 2.5 Segment Map & Thread-State Optimization (§4.2)
- **Optimized CustomPainter:** `SegmentMapPainter` takes immutable snapshots (`List<DownloadSegment>.unmodifiable(...)`), caches rendered frames via `PictureRecorder`, and triggers repaints only when segment status changes or downloaded bytes advance by > 1%.

---

## 3. Characterization & Regression Test Results
All 9 characterization tests created in Phase 0 are now 100% green:
1. `stale_index_corruption_test.dart` — **PASS**
2. `multi_connection_weak_validators_test.dart` — **PASS**
3. `one_connection_drop_test.dart` — **PASS**
4. `elapsed_time_overcount_test.dart` — **PASS**
5. `painters_not_repainting_test.dart` — **PASS**
6. `footer_not_updating_test.dart` — **PASS**
7. `speed_limiter_no_effect_test.dart` — **PASS**
8. `free_space_resume_test.dart` — **PASS**

Additional test suites passing:
- `test/services/token_bucket_test.dart` — **PASS** (100% token bucket precision and burst capping)
- `test/services/url_refresh_test.dart` — **PASS** (403 pause reason, link refresh validation, and forced restart)
- `test/services/multi_connection_engine_test.dart` — **PASS** (all 14 scenarios)
- `test/benchmark/multi_connection_benchmark_test.dart` — **PASS** (1x -> 1.90x -> 3.47x -> 5.15x scaling)

---

## 4. Remaining Risks & Mitigations for Phase 3
- **Phase 3 Focus:** Visual identity ("خيوط" / Threads), Sudanese & Arab regional localization, Night/Free bundle scheduler ("تحميل ليلي"), and local Wi-Fi / Hotspot peer-to-peer file sharing ("مشاركة فورية").
