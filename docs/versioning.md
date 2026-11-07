# NetGet Versioning Strategy

This document defines the authoritative versioning policy and cross-platform mapping rules for NetGet across Google Play and Windows.

---

## 1. Single Source of Truth (`pubspec.yaml`)

All NetGet version numbers originate strictly from `pubspec.yaml`:

```yaml
version: <version-name>+<build-number>
```

Current version:
```yaml
version: 1.0.0-rc1+1
```

### Format Specification
- `<version-name>`: Follows **Semantic Versioning 2.0.0** (`MAJOR.MINOR.PATCH[-PRERELEASE]`).
  - `MAJOR`: Breaking architectural changes or complete redesigns.
  - `MINOR`: New backwards-compatible user-facing features or engines.
  - `PATCH`: Bug fixes, security patches, and minor refactorings.
  - `-PRERELEASE` (optional): `-alpha`, `-beta`, `-rc1`, `-rc2` for pre-release candidates.
- `<build-number>`: A positive integer (`1`, `2`, `3`, ...) separated by `+`.

---

## 2. Google Play Rules

1. **Strict Monotonic Increase**:
   - The build number (`+build`) maps directly to Android's `versionCode`.
   - Google Play Console **strictly rejects** any APK or AAB upload where `versionCode` is less than or equal to any previously uploaded artifact (across all tracks: Internal, Closed, Open, Production).
   - Every single release or test build targeted for Play Console upload **MUST** increment the build number by at least 1.
2. **Version Name Visibility**:
   - The version name (`<version-name>`) maps to Android's `versionName` displayed to end-users in Google Play store listings and app settings.

### Android Gradle Resolution
In `android/app/build.gradle.kts`:
- `versionCode`: resolved directly by the Flutter Gradle Plugin from `pubspec.yaml`'s `<build-number>`.
- `versionName`: resolved directly by the Flutter Gradle Plugin from `pubspec.yaml`'s `<version-name>`.

---

## 3. Windows (MSIX) Mapping

Windows MSIX package identity manifests (`AppxManifest.xml`) enforce a strict 4-part quad numeric schema:
```
Major.Minor.Build.Revision
```
Rules enforced by Windows App Installer and Microsoft Store:
- Every component must be an integer between `0` and `65535`.
- No strings, hyphens, or pre-release suffixes (`-rc1`, `-beta`) are permitted.

### Prerelease Collision Prevention Rule
Because MSIX strips prerelease suffixes (`-rc1`, `-beta`), a prerelease package and a final release would share the exact same version if the build number were ever reset or reused (causing Windows App Installer to fail or reject the final update as "already installed").
**Rule**: The Flutter build number (`+build`) MUST be **strictly monotonically increasing and NEVER reused or reset to 1** across prerelease and GA final builds. Every build upload gets an incremented build number.

### Microsoft Store 4th Segment Constraint
> [!IMPORTANT]
> The Microsoft Store (Partner Center) documentation reserves the 4th segment (`Revision`) for automated store servicing and ingestion updates, and often requires that submitted packages declare the 4th segment as `0` (`Major.Minor.Build.0`) (*verify in Microsoft Store Partner Center packaging docs*).

### Mapping Schemas

#### Schema A: Sideload & GitHub Direct MSIX (`Major.Minor.Patch.BuildNumber`)
Used for direct MSIX package downloads, Enterprise sideloading, and GitHub Releases:
- `Major` = `pubspec MAJOR`
- `Minor` = `pubspec MINOR`
- `Build` = `pubspec PATCH`
- `Revision` = `pubspec BUILD_NUMBER`

#### Schema B: Microsoft Store Ingestion (`Major.Minor.BuildNumber.0`)
Used when submitting packages directly to Microsoft Partner Center:
- `Major` = `pubspec MAJOR`
- `Minor` = `pubspec MINOR`
- `Build` = `pubspec BUILD_NUMBER` (strictly increasing)
- `Revision` = `0` (reserved by Microsoft Store)

### Version Progression Example
| Release State | `pubspec.yaml` | Android `versionName` | Android `versionCode` | Sideload MSIX | MS Store MSIX ("verify") |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Release Candidate 1** | `1.0.0-rc1+1` | `1.0.0-rc1` | `1` | `1.0.0.1` | `1.0.1.0` |
| **Release Candidate 2** | `1.0.0-rc2+2` | `1.0.0-rc2` | `2` | `1.0.0.2` | `1.0.2.0` |
| **v1.0.0 Final GA** | `1.0.0+3` | `1.0.0` | `3` | `1.0.0.3` | `1.0.3.0` |
| **v1.0.1 Hotfix** | `1.0.1+4` | `1.0.1` | `4` | `1.0.1.4` | `1.0.4.0` |
| **v1.1.0 Feature** | `1.1.0+5` | `1.1.0` | `5` | `1.1.0.5` | `1.1.5.0` |

---

## 4. Release Checklist

1. Update `pubspec.yaml` version:
   - Increment `<version-name>` according to SemVer rules.
   - Increment `<build-number>` monotonically.
2. Run `dart analyze lib/ test/` and `flutter test`.
3. Commit with message: `chore(release): bump version to <version-name>+<build-number>`.
4. Tag commit with `v<version-name>`.

---

## 5. R8 Minification and ProGuard Rule Policy

R8 code shrinking and resource shrinking are disabled in `1.0.0-rc1` (`isMinifyEnabled = false`, `isShrinkResources = false`) because it has not yet been validated on a physical device across all architectures.

### Rule for Enabling R8 in Future Releases:
R8 may be enabled (`isMinifyEnabled = true`, `isShrinkResources = true`) only after:
1. A release-signed APK built with R8 enabled successfully passes all manual test scenarios in `docs/device_test_checklist.md` on a physical Android device.
2. ProGuard keep rules (`android/app/proguard-rules.pro`) are verified to protect:
   - Kotlin/Dart MethodChannel and EventChannel communication interfaces (`com.elmahdi.netget.*`).
   - Foreground service components (`DownloadService`, `NotificationHelper`).
   - JSON data model structures and serialization fields.
3. Verification confirms that stack traces in release mode can be de-obfuscated with `mapping.txt` and that no `ClassNotFoundException` or reflection errors occur at runtime.
