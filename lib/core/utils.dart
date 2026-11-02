import 'package:flutter/material.dart';

class NetGetUtils {
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
      return remainingSecs > 0 ? '${minutes}m ${remainingSecs}s' : '${minutes}m';
    }
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    return '${hours}h ${remainingMins}m';
  }

  /// Extracts clean file name from URL or returns a fallback name.
  static String extractFileNameFromUrl(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      // Check path segments for a filename with an extension
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
      // If path didn't have an extension, check query parameters
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

  /// Strips invalid file characters on Android/Linux.
  static String sanitizeFileName(String input) {
    var cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_').trim();
    if (cleaned.isEmpty) {
      cleaned = 'download_${DateTime.now().millisecondsSinceEpoch}';
    }
    return cleaned;
  }

  /// Returns appropriate Material Icon for a given file name/extension.
  static IconData getFileTypeIcon(String fileName) {
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
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
}
