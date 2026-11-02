# NetGet – Download Manager

NetGet is a lightweight, fast, and reliable Android download manager built with Flutter and Dart. Inspired by classic desktop download managers such as IDM, FlashGet, and Free Download Manager (FDM), NetGet prioritizes transfer speed, reliability, low resource consumption, and a clean Material 3 interface without advertisements.

---

## ⚡ Features

- **Transfer Monitor**: Real-time aggregate download speed, transferred bytes, and active/completed counters.
- **Genuine Pause & Resume**: Uses standard HTTP Range requests (`RFC 9110` / `RFC 7233`) with `bytes=<offset>-` headers for resumable downloads.
- **Real-Time Progress Tracking**: Downloaded size, total size, percentage progress, live transfer speed (MB/s), and estimated time remaining (ETA).
- **Concurrency & Queue Management**: Intelligent queue processing with concurrent download limits to prevent device bandwidth and I/O starvation.
- **File Management**: Direct integration with Android intents for opening completed files with system default handlers and sharing via Android share sheet.
- **Robust Persistence**: Atomic local JSON storage that persists download task states, gracefully restoring running downloads to paused state across app restarts.
- **Material 3 Design**: Professional, clean UI with comprehensive Light and Dark theme support.
- **Zero Ads & Zero Bloat**: Minimal native dependencies, no tracking SDKs, and low memory footprint.

---

## 🏗 Architecture

```
lib/
├── main.dart                          # App entry point & theme provider
├── core/
│   ├── constants.dart                 # App constants & storage directory resolver
│   ├── theme.dart                     # Material 3 light & dark theme definitions
│   └── utils.dart                     # File size, speed, ETA formatters & URL parser
├── models/
│   ├── download_status.dart           # Status enum (queued, downloading, paused, etc.)
│   └── download_task.dart             # Download task data model & serialization
├── data/
│   └── download_repository.dart       # Atomic file-based JSON persistence layer
├── services/
│   └── download_manager.dart          # Core download queue & HTTP streaming engine
└── ui/
    ├── home_screen.dart               # Dashboard screen, quick-add bar & tabs
    └── widgets/
        ├── add_download_sheet.dart    # Quick-add modal dialog
        ├── download_card.dart         # Download task card with real-time controls
        ├── empty_state_view.dart      # Clean empty state illustrations
        └── stats_summary_card.dart    # Transfer monitor statistics card
```

---

## 🛠 Tech Stack

- **Framework**: [Flutter](https://flutter.dev) (Dart 3)
- **Target Platform**: Android (API 21+)
- **Networking**: Dart `HttpClient` with streaming chunks and HTTP Range header support
- **State Management**: Built-in `ChangeNotifier` and reactive `ListenableBuilder`
- **File Management**: `path_provider`, `open_filex`, `share_plus`
- **Design System**: Material 3

---

## 🧪 Testing & Verification

NetGet includes unit and widget tests covering:
- Download task model serialization and progress calculations
- Byte, speed, and ETA formatters
- URL filename extraction and filesystem sanitization
- Atomic repository persistence and recovery
- Queue manager state transitions, pauses, cancels, and error handling
- Home dashboard, transfer monitor, and download card widgets

Run analysis:
```bash
flutter analyze
```

Run test suite:
```bash
flutter test
```

---

## 🚀 Continuous Integration (GitHub Actions)

Every push to `main` and pull request triggers `.github/workflows/android-build.yml`:
1. Sets up JDK 17 (Temurin) and Flutter SDK.
2. Installs Android NDK.
3. Runs `flutter analyze` with 0 warnings/errors.
4. Executes the full unit and widget test suite (`flutter test`).
5. Compiles a release APK via `flutter build apk --release`.
6. Uploads the build artifact as `netget-release-apk`.

---

## 📄 License

NetGet is open source under the MIT License.
