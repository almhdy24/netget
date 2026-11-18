# ADR 002: Two-Stage Storage & Finalization Strategy

## Status
Accepted

## Context
NetGet's primary value proposition is reliability and user data safety. The current codebase has four major storage defects:
1. Files are written directly to `getExternalStorageDirectories(type: StorageDirectory.downloads)`, which on Android resolves to `/storage/emulated/0/Android/data/com.elmahdi.netget/files/Download`. This is app-private external storage: files are wiped if the app is uninstalled, and standard file managers/galleries do not index them.
2. Multi-connection segmented downloads require `RandomAccessFile` seeking and writing at arbitrary byte offsets. Scoped Storage / Storage Access Framework (SAF) `content://` URIs introduce heavy IPC overhead and do not support low-level POSIX sparse allocation or efficient concurrent random-access writes.
3. Notification completion handlers invoke `Uri.fromFile(file)` with `Intent.ACTION_VIEW`, which throws `android.os.FileUriExposedException` on API 24+ and crashes.
4. Free disk space is currently checked via `Process.run('df', ...)`. On Android, `df` is restricted by SELinux and fails across OEM toybox/toolbox implementations, returning null or misleading values.

## Decision
We adopt a **Two-Stage Storage Architecture**:

1. **Stage 1 (In-Progress Segment Cache):**
   - In-progress downloads write to app-private cache/external files: `<app_external_files>/parts/<taskId>.part`.
   - Direct file descriptors and `RandomAccessFile` are used for maximum I/O performance and atomic chunk seeks.
2. **Stage 2 (Finalize & Publish):**
   - Upon segment completion and SHA-256 / length verification, a **Finalize** step executes.
   - On Android 10+ (API 29+), the file is published to the public **Downloads** directory (`Downloads/NetGet/<Category>/`) via Android `MediaStore.Downloads` API.
   - On legacy Android (API <= 28), it is copied directly to `/storage/emulated/0/Download/NetGet/<Category>/`.
   - If the user configured a custom directory via SAF folder picker, NetGet streams into the user-selected DocumentFile.
   - Only after successful publication and size verification is the temporary `.part` file unlinked. If publication fails (e.g., storage full), the `.part` file is preserved and a retry prompt is shown.
3. **Intent Sharing & File Viewing:**
   - All external intents (`ACTION_VIEW`, `ACTION_SEND`) use `FileProvider` or MediaStore content URIs with resolved MIME types. Direct `file://` URIs are eliminated.
4. **Disk Space Inquiries:**
   - Replace `df` with native `android.os.StatFs` queries via the platform channel. Required space is calculated as `(totalBytes - alreadyDownloaded) + safetyMargin`.

## Consequences
- **Positive:** Downloaded files are permanent and remain in public Downloads even after app uninstallation.
- **Positive:** Zero risk of `FileUriExposedException`.
- **Positive:** Maximum download throughput via direct POSIX random-access writes during Stage 1.
- **Positive:** Safe against partial corruption during power loss or low-storage conditions.
