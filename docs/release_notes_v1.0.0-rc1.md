# NetGet v1.0.0-rc1 Release Notes

Welcome to the Release Candidate 1 of **NetGet** – an offline-first, high-performance download manager for Android and desktop platforms.

---

## What's New in v1.0.0-rc1

### 1. High-Performance Multi-Connection Download Engine (Beta)
- **Parallel Chunking**: Download files using multiple parallel HTTP Range connections when supported by remote servers.
- **Durable Segment Checkpointing**: Engine progress checkpoints are strictly persisted only after calling `raf.flush()`.
- **Contiguous Hole Protection**: A preallocated `.tmp` file is never marked complete or renamed unless every byte segment is verified complete. If segment tracking data is missing, downloads cleanly restart from byte 0.
- **RFC-Compliant If-Range Handling**:
  - Weak ETags (`W/"..."`) are rejected for range validation per RFC 7232/7233.
  - Server responding with HTTP 200 OK cleanly resets file to byte 0 without entering infinite error loops.
  - Content-Range response start offsets are strictly validated against the requested byte offsets.
- **Global Host Limiter & Retry Backoff**:
  - `HostConnectionPool` caps active connections globally across all concurrent downloads per remote host.
  - HTTP 429 (Too Many Requests) and 503 (Service Unavailable) honor `Retry-After` headers clamped to a 60-second ceiling.
- **ENOSPC Disk Space Protection**:
  - Gracefully handles unknown disk metrics on Android mounts where `df` returns `null`.
  - Catches `ENOSPC` (errno 28) during preallocation and write operations, surfacing localized error guidance.
- **Conservative Default**: Default connections remain set to **1** for maximum stability; multi-connection mode is currently in **Beta**.

### 2. Throttled Persistence & Performance
- Replaced per-tick repository disk saves with throttled disk writes (max 1 write per second during progress ticks, plus immediate flushes on state transitions).
- Zero frame drops during high-speed parallel downloads.

### 3. Android Edge-to-Edge Navigation Safe Areas
- System bottom inset padding prevents 3-button navigation bars (48dp) from occluding Floating Action Buttons, download cards, or action sheets.
- Smooth keyboard insets handling in `AddDownloadSheet`.

### 4. Automated Release Pipeline
- Automated GitHub Actions workflow on `v*` tags building signed universal and split-per-ABI APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`) with SHA-256 integrity manifests.

---

## Known Limitations

1. **Android 15 Foreground Service dataSync Limits**:
   - Android 15 (API 35+) imposes a strict 6-hour cumulative limit per 24 hours on `foregroundServiceType="dataSync"`.
   - NetGet implements the `onTimeout()` callback in `DownloadService.kt` to save download state to disk and notify the user before the system terminates the process.
2. **User-Initiated Data Transfer (UIDT)**:
   - Full UIDT JobService support is designed in `docs/android_background_plan.md` but not yet implemented. Native background execution currently uses the dataSync foreground service.
3. **Loopback Benchmarks**:
   - Included benchmark results were captured in loopback network tests. While loopback confirms socket concurrency and linear throughput scaling under rate limits, real-world cellular/Wi-Fi links are subject to variable latency and packet loss.

---

## Manual Verification Checklist for Physical Devices

Before general availability, test the following on a physical Android device (preferably running Android 14 or 15):

- [ ] **3-Button Navigation Bar**: Ensure the "Add Download" FAB and bottom cards are not obscured by the 3-button navigation bar.
- [ ] **IME Keyboard Transition**: Verify the URL input field in `AddDownloadSheet` moves smoothly above the soft keyboard without overflowing.
- [ ] **Foreground Notification Controls**: Verify that tapping "Pause", "Resume", and "Cancel" in the notification shade correctly controls the active download.
- [ ] **OS Process Termination & Recovery**: Start a large download, kill the app from the Recent Apps screen / ADB (`am kill com.elmahdi.netget`), and relaunch. Confirm that the task resumes from its persisted segment offset without data corruption.
- [ ] **Multi-Connection CDN Download**: Download a multi-gigabyte file from a rate-limited CDN with `connections = 4` and verify the integrity of the downloaded file.
