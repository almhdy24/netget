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

### Mapping Formula
The Flutter pubspec version is systematically converted as:
```
Major  = pubspec.yaml MAJOR
Minor  = pubspec.yaml MINOR
Build  = pubspec.yaml PATCH
Revision = pubspec.yaml BUILD_NUMBER
```

### Examples
| `pubspec.yaml` | Android `versionName` | Android `versionCode` | Windows MSIX Version |
| :--- | :--- | :--- | :--- |
| `1.0.0-rc1+1` | `1.0.0-rc1` | `1` | `1.0.0.1` |
| `1.0.0+2` | `1.0.0` | `2` | `1.0.0.2` |
| `1.0.1+3` | `1.0.1` | `3` | `1.0.1.3` |
| `1.1.0+4` | `1.1.0` | `4` | `1.1.0.4` |
| `2.0.0+10` | `2.0.0` | `10` | `2.0.0.10` |

---

## 4. Release Checklist

1. Update `pubspec.yaml` version:
   - Increment `<version-name>` according to SemVer rules.
   - Increment `<build-number>` monotonically.
2. Run `dart analyze lib/ test/` and `flutter test`.
3. Commit with message: `chore(release): bump version to <version-name>+<build-number>`.
4. Tag commit with `v<version-name>`.
