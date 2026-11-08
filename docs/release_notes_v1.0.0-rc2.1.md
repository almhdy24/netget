# NDM (NetGet Download Manager) v1.0.0-rc2 Release Notes

Welcome to Release Candidate 2 of **NDM (NetGet Download Manager)** – a lightweight, fast, offline-first download manager for Android inspired by classic desktop tools.

---

## What's New in v1.0.0-rc2

### 1. Display Branding Rename to NDM
- Rebranded display title to **NDM** (short) and **NetGet Download Manager** (full) across Android application labels, AppBars, and About dialogs.
- Internal package identifiers, directory structures, and platform channels remain preserved for backward compatibility.

### 2. Stale Error Bug Resolution
- Fixed an issue where previous failure messages lingered on cards and in persisted task state after a download was retried or resumed.
- Added explicit `clearError: true` support to `DownloadTask.copyWith` ensuring runtime state, UI cards, and persisted `netget_tasks.json` are completely reset on retry.

### 3. Failure UX & Automatic Network Recovery
- **Centralized Error Classification**: Mapped runtime errors, timeouts, connection drops, storage full (`ENOSPC`), file mutation, and HTTP 401/403/404 into clear, localized user guidance.
- **Card Experience**: UI cards present a clean failure reason and a single primary "Retry" button. Raw exception stack traces are kept exclusively in detailed task history logs.
- **Auto-Retry**: Listens to network connectivity transitions to automatically queue interrupted downloads when a connection is re-established.

### 4. Contextual Notification Permission Flow (Android 13+)
- Deferred `POST_NOTIFICATIONS` permission prompt until the user starts their first download.
- Presented an explanatory bottom sheet before triggering the Android system dialog.
- Added a non-nagging, dismissible Home banner with direct deep link to system notification settings if permission is denied.

### 5. Native Foreground Notification Progress Bar
- Implemented real-time progress bar (`setProgress`) in ongoing foreground notifications.
- Displays aggregate progress percentage, file name (for single downloads), and transfer speed.
- Throttled notification updates to at most once per second with silent ongoing alerts (`setOnlyAlertOnce(true)`).
- Dedicated notification channels: low-importance silent channel for ongoing transfers, and default channel for completion and failure alerts.

### 6. Home & Details UX Overhaul
- **Sectioned Task Ordering**: Organizes tasks into `Active` -> `Queued & Paused` -> `Failed` -> `Completed` sections with explicit count badges.
- **Simplified Card Design**: Clutter removed; single primary action per status (Pause / Resume / Retry / Open) with filename clamped to 2 lines with ellipsis.
- **Swipe-to-Delete**: Left swipe gesture opens confirmation dialog with an option to also delete the file from storage.
- **Empty State**: Added an "Add download" quick action and clipboard URL paste chip (reads clipboard strictly on explicit user tap).
- **Add Download Sheet**: Auto-paste URL suggestion, HEAD probe to detect file name and size before starting, and segmented connection selector (1, 2, 4 streams; default 1).
- **High-Performance Updates**: Migrated progress ticks to per-task `ValueNotifier` handles, preventing unnecessary dashboard and sibling card rebuilds.

### 7. Theme Mode Persistence & Picker
- Added `SettingsRepository` for atomic local JSON persistence of user settings (`netget_settings.json`).
- Added Material 3 Theme Selection dialog with System default, Light, and Dark modes.
- Reactive theme icon in AppBar and overflow menu displaying the active theme mode.

### 8. Custom About Dialog & Open-Source Licenses
- Replaced standard Flutter `AboutDialog` with a custom dialog and dedicated open-source license viewer, eliminating framework branding ("Powered by Flutter").

---

## Verification & Integrity
- All unit and widget tests pass.
- 0 warnings, 0 infos, 0 errors in `dart analyze`.
- Automated release builds signed and verified via GitHub Actions with SHA-256 integrity checksums.
