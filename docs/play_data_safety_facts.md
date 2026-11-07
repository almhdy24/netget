# Google Play Data Safety Facts for NetGet

This document provides verified, factual responses for the Google Play Data Safety section based on direct static inspection of the codebase as of v1.0.0-rc1.

---

## 1. Network Hosts Contacted

NetGet does not contact any proprietary backend servers, telemetry endpoints, or analytics services. All network connections are initiated strictly in response to user actions:

- **User-Specified Download Hosts**:
  - NetGet connects only to the hostname specified by the user in the URL entered via `AddDownloadSheet` ([`lib/ui/widgets/add_download_sheet.dart:167`](file:///data/data/com.termux/files/home/projects/netget/lib/ui/widgets/add_download_sheet.dart#L167)) or received via Android system share / view intents ([`android/app/src/main/kotlin/com/elmahdi/netget/MainActivity.kt:60-74`](file:///data/data/com.termux/files/home/projects/netget/android/app/src/main/kotlin/com/elmahdi/netget/MainActivity.kt#L60-L74)).
  - HTTP/HTTPS connections are initiated directly via `dart:io HttpClient` in [`lib/services/multi_connection_downloader.dart:423`](file:///data/data/com.termux/files/home/projects/netget/lib/services/multi_connection_downloader.dart#L423) and [`lib/services/download_manager.dart:1301`](file:///data/data/com.termux/files/home/projects/netget/lib/services/download_manager.dart#L1301).
- **Hardcoded Endpoints**: Zero. There are no tracking domains, remote configuration endpoints, or advertising servers embedded anywhere in the project.

---

## 2. Dependencies and Data Transmission

Inspection of `pubspec.yaml` and `pubspec.lock` confirms that zero analytics, crash-reporting, tracking, or ad SDKs are included:

- `flutter`: Core Flutter UI framework. Does not collect runtime telemetry from end-user devices.
- `path_provider` (and `path_provider_android`): Resolves local Android directory paths ([`lib/core/constants.dart:90`](file:///data/data/com.termux/files/home/projects/netget/lib/core/constants.dart#L90)). Contains no networking or data collection code.
- `path`: Pure Dart path string manipulation utility. No network access.
- `open_filex`: Launches Android `ACTION_VIEW` intent with a `FileProvider` URI ([`lib/ui/widgets/download_card.dart:882`](file:///data/data/com.termux/files/home/projects/netget/lib/ui/widgets/download_card.dart#L882)). No network access.
- `share_plus`: Invokes the standard Android system share sheet (`ACTION_SEND`) to share local files or text ([`lib/ui/widgets/download_card.dart:893`](file:///data/data/com.termux/files/home/projects/netget/lib/ui/widgets/download_card.dart#L893)). No network access.

---

## 3. On-Device Storage & Locations

All application state is stored locally on the user's device and is never transmitted off-device:

1. **Download Task State & Segment Checkpoints**:
   - Location: `<ApplicationDocumentsDirectory>/netget_tasks.json` ([`lib/data/download_repository.dart:20-55`](file:///data/data/com.termux/files/home/projects/netget/lib/data/download_repository.dart#L20-L55)).
   - Data stored: Task identifier, source URL, file name, target file path, total bytes, downloaded bytes, status string, creation timestamp, completion timestamp, error messages, speed, elapsed seconds, category, ETag, Last-Modified, queue name, connection count, and segment range offsets.
2. **Downloaded File Payloads**:
   - Location: App-specific external storage directory:
     `/storage/emulated/0/Android/data/com.elmahdi.netget/files/Download/` (resolved via `getExternalStorageDirectories(type: StorageDirectory.downloads)` in [`lib/core/constants.dart:90-95`](file:///data/data/com.termux/files/home/projects/netget/lib/core/constants.dart#L90-L95)).
   - Fallback location: `<ApplicationDocumentsDirectory>/NetGetDownloads/` ([`lib/core/constants.dart:96-98`](file:///data/data/com.termux/files/home/projects/netget/lib/core/constants.dart#L96-L98)).
3. **In-Memory Volatile Logs & Metrics**:
   - Ring buffer logs: In-memory list capped at 200 entries ([`lib/services/download_manager.dart:271`](file:///data/data/com.termux/files/home/projects/netget/lib/services/download_manager.dart#L271)). Not written to disk.
   - Speed sparkline history: In-memory list capped at 60 samples ([`lib/services/download_manager.dart:288`](file:///data/data/com.termux/files/home/projects/netget/lib/services/download_manager.dart#L288)). Not written to disk.

---

## 4. Accounts, Advertising, and Analytics

- **User Accounts**: Does not require or support user accounts. No authentication, email addresses, phone numbers, or passwords exist.
- **Advertising**: Contains no advertisements. No advertising SDKs are installed or referenced.
- **Analytics / Tracking**: Contains no analytics services, diagnostic telemetry, or crash trackers.
- **Data Sharing**: NetGet does not sell, transfer, or disclose user data to third parties.

---

## 5. Google Play Data Safety Form Answers Summary

| Play Console Question | NetGet Answer | Detail / Evidence |
|---|---|---|
| **Does your app collect or share user data?** | **No** | NetGet acts exclusively as a local client tool downloading files requested by the user. It does not collect or share any user data. |
| **Is data encrypted in transit?** | **Yes** (when HTTPS is used) | HTTPS requests use TLS encryption handled by the platform `dart:io HttpClient`. Plain HTTP requests are supported for user-requested LAN/HTTP servers. |
| **Can users request data deletion?** | **Yes** | Deleting a download in the app permanently deletes the metadata from `netget_tasks.json` and deletes the file from disk ([`lib/services/download_manager.dart:731-744`](file:///data/data/com.termux/files/home/projects/netget/lib/services/download_manager.dart#L731-L744)). |
