import 'dart:io';
import 'package:flutter/material.dart';
import 'constants.dart';

class NetGetUtils {
  /// Tabular figures text style helper so numbers don't jitter during downloads.
  static TextStyle tabularStyle(TextStyle? baseStyle) {
    final style = baseStyle ?? const TextStyle();
    return style.copyWith(
      fontFeatures: [
        ...?style.fontFeatures,
        const FontFeature.tabularFigures(),
      ],
      fontFamily: 'monospace',
    );
  }

  /// Formats byte count into human-readable string (B, KB, MB, GB).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(i == 0 ? 0 : (count < 10 ? 2 : 1))} ${suffixes[i]}';
  }

  /// Formats download speed in bytes per second.
  static String formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    return '${formatBytes(bytesPerSec.round())}/s';
  }

  /// Formats remaining time into a concise string (e.g. "45s", "2m 15s", "1h 5m").
  static String formatEta(int? seconds) {
    if (seconds == null || seconds < 0) return '--';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainingSecs = seconds % 60;
    if (minutes < 60) {
      return remainingSecs > 0
          ? '${minutes}m ${remainingSecs}s'
          : '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    return '${hours}h ${remainingMins}m';
  }

  /// Formats elapsed seconds into HH:MM:SS or MM:SS.
  static String formatElapsed(int seconds) {
    if (seconds < 0) return '00:00';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Extracts clean file name from URL or returns a fallback name.
  static String extractFileNameFromUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      for (final segment in pathSegments.reversed) {
        final decoded = Uri.decodeComponent(segment);
        if (decoded.contains('.') && decoded.length > 1) {
          final sanitized = sanitizeFileName(decoded);
          if (sanitized.isNotEmpty && sanitized != '.') {
            return sanitized;
          }
        }
      }
      for (final val in uri.queryParameters.values) {
        final lastPart = val.contains('/') ? val.split('/').last : val;
        final decoded = Uri.decodeComponent(lastPart);
        if (decoded.contains('.') && decoded.length > 1) {
          final sanitized = sanitizeFileName(decoded);
          if (sanitized.isNotEmpty && sanitized != '.') {
            return sanitized;
          }
        }
      }
      if (pathSegments.isNotEmpty) {
        final decoded = Uri.decodeComponent(pathSegments.last);
        final sanitized = sanitizeFileName(decoded);
        if (sanitized.isNotEmpty && sanitized != '.') {
          return sanitized;
        }
      }
    } catch (_) {}
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  static final RegExp _windowsReservedNames = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
    caseSensitive: false,
  );

  /// Strips invalid file characters on Android, Linux, and Windows.
  /// Handles Windows reserved device names (CON, PRN, AUX, NUL, COM1..9, LPT1..9),
  /// trailing dots/spaces, and enforces maximum file name length to respect
  /// MAX_PATH (260 characters).
  static String sanitizeFileName(String input, {int maxFileNameLength = 240}) {
    // 1. Replace invalid characters (< > : " / \ | ? * and control chars) with '_'
    var cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t\x00-\x1F]'), '_').trim();

    // 2. Remove trailing dots and spaces (forbidden on Windows filesystem)
    cleaned = cleaned.replaceAll(RegExp(r'[\. ]+$'), '');

    if (cleaned.isEmpty) {
      cleaned = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }

    // 3. Handle Windows reserved DOS device names
    if (_windowsReservedNames.hasMatch(cleaned)) {
      cleaned = '_$cleaned';
    }

    // 4. Enforce max filename length (preserves extension)
    if (cleaned.length > maxFileNameLength) {
      final extIndex = cleaned.lastIndexOf('.');
      if (extIndex > 0 && extIndex > cleaned.length - 20) {
        final ext = cleaned.substring(extIndex);
        final maxBaseLen = maxFileNameLength - ext.length;
        cleaned = '${cleaned.substring(0, maxBaseLen > 0 ? maxBaseLen : maxFileNameLength)}$ext';
      } else {
        cleaned = cleaned.substring(0, maxFileNameLength);
      }
      cleaned = cleaned.replaceAll(RegExp(r'[\. ]+$'), '');
    }

    return cleaned;
  }

  /// Safely renames [source] to [destination] across all operating systems.
  /// On Windows, File.rename() fails if destination exists; this helper
  /// deletes the existing destination first and performs a fallback copy/delete
  /// if atomic rename is blocked by filesystem locking.
  static Future<File> safeRenameFile(File source, File destination) async {
    if (await destination.exists()) {
      await destination.delete();
    }
    try {
      return await source.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) {
        await destination.delete();
      }
      await source.copy(destination.path);
      await source.delete();
      return destination;
    }
  }

  /// Parses RFC 5987 / RFC 6266 Content-Disposition header.
  static String? parseContentDisposition(String? header) {
    if (header == null || header.isEmpty) return null;
    try {
      // filename*=UTF-8''...
      final utf8Match = RegExp(
        r"filename\*=UTF-8''([^;]+)",
        caseSensitive: false,
      ).firstMatch(header);
      if (utf8Match != null) {
        return Uri.decodeComponent(utf8Match.group(1) ?? '').trim();
      }

      // filename="..."
      final quotedMatch = RegExp(
        r'filename="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(header);
      if (quotedMatch != null) {
        return quotedMatch.group(1)?.trim();
      }

      // filename=...
      final plainMatch = RegExp(
        r'filename=([^;]+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (plainMatch != null) {
        return plainMatch.group(1)?.trim();
      }
    } catch (_) {}
    return null;
  }

  /// Classifies a file into one of the DownloadCategory categories.
  static DownloadCategory classifyCategory(
    String fileName, [
    String? mimeType,
  ]) {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.startsWith('video/')) return DownloadCategory.video;
    if (mime.startsWith('audio/')) return DownloadCategory.audio;
    if (mime.startsWith('image/')) return DownloadCategory.images;
    if (mime.contains('pdf') ||
        mime.contains('document') ||
        mime.contains('text/')) {
      return DownloadCategory.documents;
    }
    if (mime.contains('zip') ||
        mime.contains('tar') ||
        mime.contains('compressed')) {
      return DownloadCategory.archives;
    }
    if (mime.contains('android.package-archive')) return DownloadCategory.apps;

    final dot = fileName.lastIndexOf('.');
    final ext = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : '';

    switch (ext) {
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'webm':
      case 'flv':
      case 'wmv':
      case '3gp':
      case 'm4v':
        return DownloadCategory.video;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
      case 'm4a':
      case 'wma':
      case 'opus':
        return DownloadCategory.audio;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
      case 'bmp':
      case 'ico':
      case 'tiff':
        return DownloadCategory.images;
      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
      case 'odt':
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'ppt':
      case 'pptx':
      case 'epub':
        return DownloadCategory.documents;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
      case 'xz':
      case 'iso':
      case 'tgz':
        return DownloadCategory.archives;
      case 'apk':
      case 'xapk':
      case 'apks':
      case 'aab':
        return DownloadCategory.apps;
      default:
        return DownloadCategory.other;
    }
  }

  /// Returns appropriate Material Icon for a given file name/extension.
  static IconData getFileTypeIcon(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    switch (ext) {
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_outlined;
      case 'apk':
        return Icons.android_outlined;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
      case 'webm':
        return Icons.movie_outlined;
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
      case 'ogg':
      case 'm4a':
        return Icons.audiotrack_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'svg':
        return Icons.image_outlined;
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'odt':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_outlined;
      case 'iso':
      case 'img':
        return Icons.disc_full_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  /// Category icon helper.
  static IconData getCategoryIcon(DownloadCategory category) {
    switch (category) {
      case DownloadCategory.all:
        return Icons.all_inbox_rounded;
      case DownloadCategory.video:
        return Icons.movie_outlined;
      case DownloadCategory.audio:
        return Icons.audiotrack_outlined;
      case DownloadCategory.images:
        return Icons.image_outlined;
      case DownloadCategory.documents:
        return Icons.description_outlined;
      case DownloadCategory.archives:
        return Icons.folder_zip_outlined;
      case DownloadCategory.apps:
        return Icons.android_outlined;
      case DownloadCategory.other:
        return Icons.category_outlined;
    }
  }

  /// Returns whether [etag] is a strong validator according to RFC 7232 § 2.3.
  /// Weak ETags (starting with W/ or w/) cannot be used in If-Range requests.
  static bool isStrongEtag(String? etag) {
    if (etag == null) return false;
    final trimmed = etag.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('W/') || trimmed.startsWith('w/')) return false;
    return true;
  }
}
