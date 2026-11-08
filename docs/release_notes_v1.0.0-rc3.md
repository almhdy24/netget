# NDM (NetGet Download Manager) v1.0.0-rc3 Release Notes

Welcome to Release Candidate 3 of **NDM (NetGet Download Manager)** – a lightweight, fast, offline-first download manager for Android inspired by classic desktop tools.

---

## What's New in v1.0.0-rc3

### 1. AlmHdyAnalytics & Telemetry Integration
- Integrated self-hosted, privacy-first **AlmHdyAnalytics** client (`api.almhdy24.com`).
- Completely fire-and-forget, non-blocking telemetry architecture wrapped in try/catch handlers ensuring download paths and UI rendering are never delayed.
- Automated error and crash capture hooked into `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
- Tracks coarse, non-PII metrics and categories only (no URLs, file names, paths, or IPs are ever collected or sent).

### 2. In-App Statistics & Telemetry Reports Dashboard
- Added a dedicated **Statistics & Reports** screen (`StatisticsScreen`) computed strictly from local task metadata.
- Overview cards: Total Tasks, Completed, Failed, Success Rate, and Total Downloaded Bytes.
- Visual 7-day activity bar chart with date labels and daily volume calculation.
- File type distribution breakdown with custom-painted progress bars (Video, Audio, Images, Documents, Archives, Apps, Other).
- Interactive entry points from the Transfer Monitor card header, toolbar button, and main overflow menu.
- Full RTL and Arabic localization support.

### 3. Decoupled Real-Time Progress Engine
- Decoupled high-frequency UI progress ticks (up to 4 updates/sec for smooth rendering) from disk persistence.
- Kept disk saves safely throttled to 1/sec, eliminating I/O bottlenecks and UI stutters.
- Fixed multi-connection aggregate byte counts so single-connection and multi-connection tasks update Home cards identically within one frame.
- Proper handling of unknown total file sizes (`totalBytes <= 0`) showing indeterminate smooth progress rather than jumping to 0%.

### 4. Privacy-First Anonymous Statistics Toggle
- Added an "Anonymous usage statistics" toggle in the Settings dialog, ON by default.
- Backed by persistent local storage (`netget_settings.json`) and synchronized directly with the analytics SDK's opt-out/opt-in engine.
- Includes a clear explanatory subtext in both English and Arabic.

### 5. Layout & RenderFlex Polishing
- Eliminated RenderFlex horizontal overflows on narrow screens in `StatsSummaryCard` and `PopupMenuButton`.
- Added flexible truncation to title badges while preserving touch targets and accessibility.

---

## Verification & Integrity
- All 120+ unit, widget, simulated insets, and analytics tests pass.
- 0 warnings, 0 infos, 0 errors in static analysis (`dart analyze lib/ test/`).
- Automated release builds signed and verified via GitHub Actions with SHA-256 integrity checksums.
