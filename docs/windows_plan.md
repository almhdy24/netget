# Windows Readiness Plan for NetGet

This document outlines the technical architecture, packaging, signing, and lifecycle roadmap for supporting Windows on NetGet.

---

## 1. Directory Structure Added by `flutter create --platforms=windows`

Running `flutter create --platforms=windows .` adds the native C++ Win32 embedding under `windows/`:

```
windows/
├── CMakeLists.txt                      # Root CMake build script for Windows Runner
├── flutter/                            # Generated CMake config & library wrappers
│   ├── CMakeLists.txt
│   ├── generated_plugin_registrant.cc  # Auto-registers Flutter plugins for Windows
│   ├── generated_plugin_registrant.h
│   └── generated_plugins.cmake
└── runner/                             # Win32 Application Runner
    ├── CMakeLists.txt
    ├── flutter_window.cpp              # Implements Win32 window hosting FlutterViewController
    ├── flutter_window.h
    ├── main.cpp                        # Win32 entry point (wWinMain)
    ├── resource.h                      # Resource IDs (icons, versioninfo)
    ├── resources/                      # Application icon (.ico)
    ├── Runner.rc                       # Windows resource script (version, icon)
    ├── Runner.exe.manifest             # Per-monitor DPI awareness, Windows 10/11 compatibility
    ├── utils.cpp                       # UTF-8 <-> UTF-16 Win32 string helpers
    ├── utils.h
    ├── version.h.in                    # Template for version generation from pubspec
    ├── win32_window.cpp                # Pure Win32 window base class (WinProc, message pump)
    └── win32_window.h
```

---

## 2. Packaging & Version Mapping (MSIX)

Windows modern app distribution uses MSIX (via the `msix` Dart pub package or Windows SDK `makeappx.exe` / `makemsix.exe`).

### Version Requirement
MSIX manifests (`AppxManifest.xml`) mandate a strictly numeric 4-part quad version:
```
Major.Minor.Build.Revision
```
Where each component must be an integer between `0` and `65535` (`0.0.0.0` to `65535.65535.65535.65535`). Text strings, prerelease tags (e.g. `-rc1`), and alphabetic metadata are rejected by Windows App Installer and the Microsoft Store.

### Mapping from Flutter SemVer (`1.0.0-rc1+1`)
- **Pubspec version**: `1.0.0-rc1+1`
  - `Major` = `1`
  - `Minor` = `0`
  - `Patch` = `0`
  - `Build Number` (`+1`) = `1`
- **MSIX Quad Version**: `1.0.0.1`
  - `Major` = `1`
  - `Minor` = `0`
  - `Build` = `0` (or mapped patch version)
  - `Revision` = `1` (strictly corresponds to Flutter build number `+1`)

For release builds:
- `1.0.0+1`  -> `1.0.0.1`
- `1.0.1+2`  -> `1.0.1.2`
- `1.1.0+10` -> `1.1.0.10`

*(verify exact MSIX build configuration in `msix` package config)*

---

## 3. Code-Signing Options

Windows SmartScreen warns users against executing unsigned applications. Three primary signing avenues exist:

1. **Microsoft Store Ingestion (Zero-Certificate Overhead)**:
   - Submitting an unsigned or self-signed MSIX package to the Microsoft Partner Center.
   - Microsoft automatically signs the package with their trusted Store root certificate upon certification.
   - Publisher Identity in `AppxManifest.xml` must match the Microsoft Partner Center Publisher ID (`CN=...`).

2. **Azure Trusted Signing (Modern Cloud HSM)**:
   - Microsoft's cloud code-signing service (integrated directly into GitHub Actions via `azure/trusted-signing-action`).
   - Does not require managing physical hardware USB tokens.
   - Pricing and identity verification via Microsoft Entra ID *(verify eligibility and pricing in Azure documentation)*.

3. **Public CA EV / Standard Code-Signing Certificate**:
   - Hardware USB token or Cloud HSM (DigiCert, Sectigo, GlobalSign).
   - Executed via Windows SDK `signtool.exe`:
     ```cmd
     signtool sign /fd SHA256 /a /tr http://timestamp.digicert.com /td SHA256 <package>.msix
     ```

4. **Self-Signed Certificate (Local Testing & Sideloading)**:
   - Generated via PowerShell `New-SelfSignedCertificate`.
   - Users/testers must install the certificate to `LocalMachine\Root` before installing the MSIX.

---

## 4. GitHub Actions CI Job Outline (`windows-latest`)

A Windows release build can be integrated into `.github/workflows/windows-build.yml` or the unified `release.yml`:

```yaml
jobs:
  build-windows:
    name: Build Windows Release
    runs-on: windows-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.29.0' # Or target Flutter SDK channel
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Run static analysis & tests
        run: |
          dart analyze lib/ test/
          flutter test

      - name: Build Windows Executable
        run: flutter build windows --release

      # Optional MSIX generation (requires 'msix' dev_dependency)
      # - name: Build MSIX Package
      #   run: dart run msix:create --version 1.0.0.1

      - name: Upload Windows Build Artifact
        uses: actions/upload-artifact@v4
        with:
          name: netget-windows-release
          path: build/windows/x64/runner/Release/
          if-no-files-found: error
```

---

## 5. Background Execution & System Tray Story

### Preventing Process Kill on Window Close
By default, closing a Windows desktop window terminates the application process. For a download manager, closing the window while downloads are active should minimize to the system tray.

- **Window Management**: Use `window_manager` to hook the native `WM_CLOSE` message:
  ```dart
  await windowManager.setPreventClose(true);
  // In WindowListener.onWindowClose():
  if (downloadManager.hasActiveDownloads) {
    await windowManager.hide();
  } else {
    await windowManager.destroy();
  }
  ```
- **System Tray Integration**: Use `tray_manager` to show an icon in the Windows notification area with a context menu:
  - Show / Hide NetGet
  - Active download count & speed
  - Pause All / Resume All
  - Exit Application

### Preventing System Sleep During Active Transfers
Unlike Android which uses Foreground Services with `FOREGROUND_SERVICE_TYPE_DATA_SYNC`, Windows enters Connected Standby or Modern Standby when idle, which throttles CPU and suspends non-media network traffic.

To ensure uninterrupted downloads on Windows:
- Call the Win32 API `SetThreadExecutionState` via `dart:ffi` or `win32` package:
  ```dart
  import 'package:win32/win32.dart';

  void preventSleep() {
    // ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED
    SetThreadExecutionState(
      EXECUTION_STATE.ES_CONTINUOUS |
      EXECUTION_STATE.ES_SYSTEM_REQUIRED |
      EXECUTION_STATE.ES_AWAYMODE_REQUIRED,
    );
  }

  void allowSleep() {
    SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
  }
  ```
  *(verify behavior across Windows 10 vs Windows 11 Modern Standby systems)*.
