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

### (c) Network Disconnection, Failure UX & Retry Flow
- **Objective**: Verify network disconnection handling, failure mapping, auto-retry, and manual retry without stale errors.
- **Steps**:
  1. Start an active download.
  2. Enable Airplane mode in Android Quick Settings or disconnect Wi-Fi/mobile data.
  3. Wait 5-10 seconds.
  4. Inspect the task card:
     - Verify it transitions to a waiting/failure state showing a clear, localized reason (e.g. "No internet connection" / "Network disconnected") rather than raw socket exception stack traces.
     - Raw error details remain accessible strictly inside task details history log.
  5. If auto-retry is active, restore connection; verify the download resumes automatically.
  6. Alternatively, trigger a failed state (e.g., test URL timing out). Tap the **Retry** button on the card:
     - Task transitions to downloading/queued.
     - Verify that the card and details screen immediately clear all previous error messages and badges.
     - Verify `netget_tasks.json` has `errorMessage: null` and `failureCode: null` for the retrying task.
- **Expected Result**:
  - No raw stack traces shown on home cards.
  - Tapping **Retry** clears previous errors completely.
  - Resumed/retried download completes cleanly with matching SHA-256.

---

### (d) In-Context Notification Permission (`POST_NOTIFICATIONS`) Flow (Android 13+)
- **Objective**: Verify that notification permission is requested in context on the first download, with appropriate fallback banners and deep links.
- **Steps**:
  1. Fresh install or revoke notification permission via ADB:
     ```bash
     adb shell pm revoke com.elmahdi.netget android.permission.POST_NOTIFICATIONS
     ```
  2. Open NDM. Confirm no notification prompt appears on launch (app launch must never nag).
  3. Tap **+** and start the first download:
     - An in-context bottom sheet appears explaining why notifications are needed: "Notifications show download progress and let downloads continue in the background".
     - Tap **Continue**; the Android system `POST_NOTIFICATIONS` dialog appears.
  4. **Subcase 1: User grants permission**:
     - System dialog granted -> download starts with ongoing foreground progress notification.
  5. **Subcase 2: User denies permission once**:
     - Deny permission -> bottom sheet dismisses, download proceeds without crashing.
     - Home screen displays a small dismissible info banner: "Enable notifications to see download progress in the background" with an **Enable** button.
     - Dismissing the banner hides it for the remainder of the session (no repeated nagging).
     - Tapping **Enable** navigates directly to the app's system notification settings screen.
  6. **Subcase 3: User permanently denies ("Don't ask again")**:
     - Subsequent attempts or tapping the settings banner open Android system settings directly.
- **Expected Result**:
  - Permission is never requested on cold start; only in-context on the first download action.
  - Downloads proceed normally regardless of permission state.
  - No crash (`SecurityException`) occurs when permission is denied.

---

### (e) Native Foreground Notification Progress Bar & Status Notifications
- **Objective**: Verify native notification progress bar accuracy, throttling, and status alerts.
- **Steps**:
  1. Ensure notification permission is granted.
  2. Start a single download:
     - Check the Android notification drawer:
       - Title displays **NDM**.
       - Ongoing progress bar accurately reflects current progress (`setProgress(100, percent, false)`).
       - Text shows `<file_name> - X%` alongside transfer speed.
       - Progress updates are throttled (at most 1 update per second).
       - Updates do not vibrate or make alert sounds (`setOnlyAlertOnce(true)`).
       - Tap the notification: verifies it launches/resumes the main NDM activity.
  3. Start a second concurrent download:
     - Notification text updates to `N downloads - X%` showing aggregate progress.
  4. Allow a download to complete:
     - A dedicated completion notification appears on the default importance channel (`ndm_status_channel`).
     - Tapping the completion notification opens the downloaded file or details.
  5. Trigger a download failure:
     - A failure notification is posted on the status channel.
     - Tapping opens the task details screen.
- **Expected Result**:
  - Smooth progress bar without UI freezing or alert sound spam.
  - Separate status channel used for completion/failure alerts.

---

### (f) Android 15 `dataSync` Timeout Handling
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

### (g) Insets & Edge-to-Edge Display (3-Button vs Gesture Navigation)
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

### (h) Storage Full Behaviour (`ENOSPC`)
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
