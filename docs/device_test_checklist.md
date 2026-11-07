# NetGet Physical Device Manual Test Checklist

This document details the manual verification procedures required on physical Android hardware before promotional release builds.

---

## Pre-Test Setup
- **Target Hardware**: Physical Android device running Android 10+ (recommend testing on Android 14/15 if available).
- **Build**: Release APK built from `release/play-ready`:
  ```bash
  flutter build apk --release
  adb install -r build/app/outputs/flutter-apk/app-release.apk
  ```

---

## Test Cases

### (a) Large Background Download with Screen Off
- **Objective**: Verify that Foreground Service `dataSync` prevents Android Doze / LMK from killing the transfer.
- **Steps**:
  1. Add a large test download (e.g., 500 MB to 1 GB test file with known SHA-256).
  2. Start download; confirm notification appears showing active download count and transfer speed.
  3. Swipe NetGet out of recent apps (swipe away from app switcher).
  4. Turn off screen and leave device idle on battery for 30 minutes.
  5. Wake device; check notification or re-open NetGet.
- **Verification**:
  - Pull downloaded file to host machine:
    ```bash
    adb pull /storage/emulated/0/Android/data/com.elmahdi.netget/files/Download/<filename> .
    sha256sum <filename>
    ```
- **Expected Result**:
  - Download completes with status "Completed".
  - Computed SHA-256 matches remote source file exactly (0 bit errors, zero corruption).

---

### (b) Process Kill Mid-Download & Resume
- **Objective**: Verify that non-graceful process termination preserves segment checkpoints without file corruption.
- **Steps**:
  1. Start a multi-connection or single-connection download of a large file (> 200 MB).
  2. While actively downloading at ~50%, abruptly terminate the process via ADB:
     ```bash
     adb shell am force-stop com.elmahdi.netget
     ```
  3. Re-launch NetGet from launcher.
  4. Inspect the task in the dashboard; tap **Resume**.
- **Expected Result**:
  - Task state shows "Paused" upon re-opening (persisted in `netget_tasks.json`).
  - Resume uses HTTP `Range` headers to resume from the last flushed checkpoint without restarting from 0 (if server supports Range) or cleanly restarts if ETag changed.
  - Final completed file SHA-256 matches source file.

---

### (c) Airplane Mode & Network Flapping
- **Objective**: Verify network disconnection handling and recovery.
- **Steps**:
  1. Start an active download.
  2. Enable Airplane mode in Android Quick Settings.
  3. Wait 10 seconds.
  4. Disable Airplane mode (reconnect to Wi-Fi/Cellular).
- **Expected Result**:
  - Active download encounters network socket interruption and cleanly transitions to "Paused" or "Failed" with localized error "Network connection unavailable".
  - Tapping **Resume** after connectivity returns resumes the download cleanly without deadlocks.

---

### (d) Notification Permission Denied (`POST_NOTIFICATIONS`)
- **Objective**: Verify that denying notification permission on Android 13+ (API 33+) does not crash or block downloads.
- **Steps**:
  1. On Android 13+, revoke notification permission:
     ```bash
     adb shell pm revoke com.elmahdi.netget android.permission.POST_NOTIFICATIONS
     ```
  2. Open NetGet and start a download.
  3. Swipe app to background.
- **Expected Result**:
  - Native `DownloadService` starts without throwing unhandled `SecurityException`.
  - Dart download continues transferring data at full speed.
  - No notification appears in shade, but download finishes successfully.

---

### (e) Android 15 `dataSync` Timeout Handling
- **Objective**: Verify graceful handling of Android 15's 6-hour cumulative foreground dataSync timeout.
- **Steps**:
  1. On Android 15 (API 35+), simulate the FGS dataSync timeout via ADB without waiting 6 hours (*verify exact ADB flag in Android 15 developer preview docs*):
     ```bash
     adb shell cmd device_config put activity_manager data_sync_fgs_timeout_duration 30000
     ```
     *(Alternative: fast-forward system clock or trigger `adb shell cmd activity timeout-service com.elmahdi.netget/.DownloadService`)*.
  2. Start a long-running download.
  3. Trigger the timeout threshold.
- **Expected Result**:
  - Android calls `DownloadService.onTimeout(startId, fgsType)`.
  - Native service emits `{'event': 'onTimeout'}` over `EventChannel`.
  - Dart engine receives event, calls `pauseAll()`, and safely flushes/closes all file handles.
  - App displays "Timeout" notification prompting the user to resume when convenient.

---

### (f) Insets & Edge-to-Edge Display (3-Button vs Gesture Navigation)
- **Objective**: Verify that bottom cards, FloatingActionButtons (FAB), and modal sheets do not overlap system bars.
- **Steps**:
  1. Go to Android Settings -> System -> Navigation Mode.
  2. Select **3-Button Navigation** (Back, Home, Recents).
     - Open NetGet; verify FAB is positioned above the 48dp navigation bar.
     - Scroll to bottom of task list; verify bottom-most card is fully visible and clickable above navigation buttons.
     - Open **Add Download Sheet**; tap URL input field; verify modal moves smoothly above the on-screen keyboard (IME).
  3. Switch to **Gesture Navigation**.
     - Verify bottom padding adjusts dynamically without excessive blank gaps.
- **Expected Result**:
  - No touch targets or text obscured by system bars or keyboard across either mode.

---

### (g) Storage Full Behaviour (`ENOSPC`)
- **Objective**: Verify clean error surfacing when device runs out of storage space.
- **Steps**:
  1. Fill device internal storage or create a dummy file until remaining space is < 10 MB:
     ```bash
     adb shell "dd if=/dev/zero of=/sdcard/fill.tmp bs=1M count=2000"
     ```
  2. Attempt to download a 50 MB file in NetGet.
- **Expected Result**:
  - `MultiConnectionDownloader` pre-allocation check detects insufficient disk space or catches `ENOSPC` (errno 28).
  - Task transitions to "Failed" with localized message:
    `"Insufficient disk space: need X bytes, but only Y bytes available"` or `"No space left on device"`.
  - Zero application crashes.
  - Clean up test dummy file: `adb shell rm /sdcard/fill.tmp`.
