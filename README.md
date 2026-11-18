# NetGet (NDM) — Resilient Download Manager for Android
### «ما بنبدأ من الصفر» — "We never start from zero"

[![CI](https://github.com/elmahdi/netget/actions/workflows/android-build.yml/badge.svg)](https://github.com/elmahdi/netget/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%205.0%2B%20(API%2021%2B)-green.svg)](https://android.com)

**NetGet** (short branding **NDM**) is a high-performance, resilient, zero-bloat Android download manager built with Flutter and Dart.

Designed specifically for users navigating slow, unstable, expensive, or metered mobile connections—such as in Sudan and across emerging markets—NetGet is engineered on an unyielding principle: **«ما بنبدأ من الصفر» (We never start from zero)**. When a connection drops, an IP switches, a temporary link expires, or battery saver interrupts a transfer, NetGet preserves every single byte and seamlessly continues from the exact byte boundary.

---

## 🧵 «خيوط» (Threads) Visual Identity

NetGet features a custom-crafted design signature inspired by traditional Sudanese loom craftsmanship, desert landscapes, and the Nile river:

- **Sudanese Color Palette**:
  - **Desert Sand** (`#F3D2A2`) & **Warm Amber** (`#E09F3E`)
  - **Nile Deep Blue** (`#0F4C5C`) & **River Indigo** (`#1B3B6F`)
  - **Clay Terracotta** (`#C85A32`) & **Earth Red** (`#9E2A2B`)
  - **Dark Slate** (`#121820`) for high-contrast, eye-friendly night usage.
- **`ThreadBar` Segment Visualizer**:
  Rather than an opaque single-color bar, multi-connection transfers visually render each concurrent byte-range segment as distinct colored thread strands weaving together across the file layout.
- **Dynamic Indicators**:
  - `ConnectionPulse`: Concentric breathing ripples signaling active socket connections.
  - `BudgetRing`: High-precision circular data consumption gauge contrasting monthly metered usage against free off-peak night data.
  - `ThreadEmptyState`: Intricate geometric loom artwork reinforcing our core motto.

---

## ⚡ Flagship Capabilities

### 1. Multi-Connection Resilient Engine (`RFC 7232` / `RFC 7233`)
- **Dynamic Segment Chunking**: Parallel byte-range streams via independent HTTP Range workers using random-access positional writes.
- **Work-Stealing Rebalancing**: Faster worker threads automatically steal uncompleted tail segments from lagging streams, eliminating tail latency on variable cellular links.
- **Strict RFC Validation**: Enforces strong ETags (`W/"..."` weak validators rejected for range requests), validates `Content-Range` boundaries, and recovers cleanly from HTTP 200 resets without error loops.
- **Zero-Hole File Safety**: Guarantees preallocated `.tmp` / `.part` files cannot be marked complete if intermittent write holes exist; atomic segment accounting ensures verified byte-for-byte fidelity.
- **TokenBucket Bandwidth Throttling**: Smooth, fine-grained speed limiting configurable globally and per-task.

### 2. Data Budget & Free Off-Peak Windows
- **Metered Usage Ledger**: Backed by SQLite (`usage_ledger`), recording byte consumption per interface (`mobile`, `wifi`, `free_mobile`).
- **Billing Cycle Management**: Custom billing reset days (1–28) with automatic cycle date boundary math.
- **Hard-Stop Caps**: Automatically pauses downloads on cellular when monthly data limits are reached, protecting users against costly out-of-bundle charges.
- **Free Night Bundles**: Built-in support for ISP zero-rated night windows (e.g. 02:00 – 06:00). Tasks scheduled for `wifiOrFreeWindow` sleep during metered hours and auto-resume the moment the free window opens.

### 3. Multi-Mirror Failover & Expired Link Recovery
- **Automatic Mirror Fallover**: If a primary server returns `403 Forbidden`, `404 Not Found`, `410 Gone`, or experiences connection dropouts, NetGet fails over dynamically to configured alternate mirrors without losing downloaded bytes.
- **Expired Signed Link Refresh**: Cloud services and file hosts often expire signed URLs after a few hours. NetGet allows updating the URL of an active or paused download in-place, verifying file size and ETags and continuing from byte $N$.
- **HTML Trap Detection**: Detects captive portals, ISP interstitial landing pages, and Cloudflare error pages served as `text/html` instead of the expected binary stream (`HtmlServedInsteadOfFileException`), pausing safely before corrupted HTML can be written to disk.

### 4. Offline Nearby Share («شارك بالقرب»)
- **Zero-Internet File Sharing**: Built-in, ultra-lightweight RFC 7233 local HTTP streaming server.
- **Dynamic QR Code Handoff**: Completed or partially completed downloads can be shared peer-to-peer over local Wi-Fi or hotspot. Any device with a browser or download manager can scan the QR code to pull the file at maximum local LAN speeds with full Range resume support.

### 5. Smart Add & Clipboard Integration
- **Foreground Clipboard Detection**: When returning to NetGet with a URL on the system clipboard, a non-intrusive action chip offers instant download creation without modal annoyance.
- **Batch Add Dialog**: Paste multi-line blocks of URLs, auto-extract filenames, batch-assign queues, categories, and network policies in one go.

### 6. File Integrity & Two-Stage Storage Pipeline
- **Background Isolate Checksums**: Non-blocking streaming computation of **SHA-256**, **SHA-1**, and **MD5** hashes.
- **Sidecar Hash Probing**: Automatically attempts to fetch `.sha256`, `.sha1`, or `.md5` sidecar files from the host server.
- **Two-Stage Sandbox Storage**: Downloads write to an internal sandbox `.staging/` path during download. Only upon complete, hole-free verification is the file atomically committed to public `Download/` or Storage Access Framework (SAF) trees.

### 7. Honest Insights & Telemetry
- **«رؤى الصمود — ما بنبدأ من الصفر»**:
  - Tracks `bytesPreservedByResume` (actual gigabytes saved by resuming instead of restarting from scratch).
  - Tracks `interruptionsRecovered` (exact count of connection drops survived).
- **Privacy-First Analytics**: Clean local telemetry using `almhdy_analytics`. URL query strings and credentials are sanitized before logging; zero native trackers, zero advertising SDKs.

### 8. Arabic-First RTL Localization
- Native Arabic typography and cultural vernacular («ما بنبدأ من الصفر», «خيوط», «شارك بالقرب», «رؤى الصمود»).
- Full Right-to-Left (RTL) mirroring and contextual padding.
- Optional Eastern Arabic numerals toggle (`١، ٢، ٣`) alongside Western standard numerals.

---

## 🏗 Architecture

NetGet is structured around clean separation of concerns, transactional SQLite persistence, and isolate-hosted background services:

```
lib/
├── core/
│   ├── constants.dart              # Global constants & storage paths
│   ├── design_tokens.dart           # «خيوط» Sudanese palette & typography tokens
│   ├── segment_planner.dart        # RFC range planner & work-stealing algorithm
│   ├── theme.dart                  # Material 3 light/dark theme definitions
│   └── utils.dart                  # Formatters, URL parsers, Eastern digits
├── models/
│   ├── data_budget.dart            # Billing cycles, FreeWindow, BudgetSummary
│   ├── download_status.dart        # Download status taxonomy & failure helpers
│   ├── download_task.dart          # Immutable task model & segment list
│   └── task_store.dart             # Single-mutation in-memory task container
├── data/
│   ├── download_repository.dart    # Abstract persistence interface
│   ├── sqlite_download_repository.dart # SQLite WAL database (netget.db)
│   └── settings_repository.dart    # App settings & preferences storage
├── services/
│   ├── background/
│   │   └── download_service_host.dart # Isolate service host & lifecycle
│   ├── data_budget_service.dart    # Ledger aggregation & policy enforcement
│   ├── download_manager.dart       # High-level coordinator & queue scheduler
│   ├── integrity_service.dart      # Background isolate hash calculator (SHA/MD5)
│   ├── nearby_share_service.dart   # Local RFC 7233 HTTP server for offline sharing
│   ├── storage_service.dart        # Two-stage sandbox staging & atomic promotion
│   └── token_bucket.dart           # Byte-rate throttling engine
└── ui/
    ├── details/
    │   └── download_details_screen.dart # Task diagnostics, mirrors, integrity check
    ├── dialogs/
    │   └── batch_add_dialog.dart   # Multi-link entry dialog
    ├── home_screen.dart            # Main dashboard, tab views & status monitor
    ├── settings/
    │   ├── budget_screen.dart      # Data budget & free window configuration
    │   └── settings_screen.dart    # Bandwidth limits, appearance, digit formats
    └── widgets/
        ├── budget_ring.dart        # Circular budget usage custom painter
        ├── connection_pulse.dart   # Animated connection indicator
        ├── download_card.dart      # Reactive task card with ThreadBar
        ├── nearby_share_sheet.dart # QR code offline sharing sheet
        ├── thread_bar.dart         # Multi-strand thread custom painter
        └── thread_empty_state.dart # Woven loom empty state illustration
```

---

## 🧪 Testing & Verification

NetGet adheres to rigorous quality standards with over 150 automated tests:

- **Characterization & Regression Suite**: Verified against `test/support/test_server.dart` running 11 deterministic HTTP failure scenarios (dropped connections mid-stream, dynamic ETag changes, 429 backoff, weak validators, preallocation holes).
- **Service Verification**: Unit tests covering TokenBucket throttling, SQLite migrations, two-stage staging, ledger accounting, and background isolate hashing.
- **UI & Insets Verification**: Validated on Android 3-button navigation bars (48dp), simulated display cutouts, and dynamic IME keyboard insets.

Run static analysis:
```bash
flutter analyze
```

Run test suite:
```bash
flutter test
```

---

## 🚀 Building & Releasing

NetGet builds with standard Flutter 3 tooling:

```bash
# Generate localized accessor classes
flutter gen-l10n

# Compile release APK
flutter build apk --release --split-per-abi
```

Compiled APK artifacts:
- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk`
- `build/app/outputs/flutter-apk/app-x86_64-release.apk`

---

## 📜 Architectural Decision Records (ADRs)

Key architectural choices are formally documented in `docs/adr/`:
- **ADR-001**: Characterization test suite & local HTTP test server
- **ADR-002**: Rebalancing byte-range chunk allocation
- **ADR-003**: RFC 7232/7233 strong ETag & restart safety
- **ADR-004**: Single-mutation TaskStore model
- **ADR-005**: SQLite WAL storage with automatic JSON migration
- **ADR-006**: Two-stage storage sandbox pipeline
- **ADR-007**: Work-stealing segment scheduler
- **ADR-008**: Expired URL refresh with preserved progress
- **ADR-009**: PictureRecorder-backed thread visualizer
- **ADR-010**: SQLite usage ledger & billing cycle math
- **ADR-011**: Zero-rated night window scheduler
- **ADR-012**: Multi-mirror failover & HTML trap detection
- **ADR-013**: Offline RFC 7233 local HTTP sharing server
- **ADR-014**: Background isolate crypto checksum verification
- **ADR-015**: Resilience insights & data preservation telemetry
- **ADR-016**: «خيوط» (Threads) design system & palette
- **ADR-017**: ThreadBar custom painter architecture
- **ADR-018**: Mobile density & edge-to-edge layout constraints
- **ADR-019**: Arabic-first RTL localization & cultural voice
- **ADR-020**: Eastern Arabic numerals system

---

## 📄 License

NetGet is open-source software licensed under the [MIT License](LICENSE).
