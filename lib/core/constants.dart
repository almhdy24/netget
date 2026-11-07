import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum DownloadCategory {
  all,
  video,
  audio,
  images,
  documents,
  archives,
  apps,
  other;

  String get label {
    switch (this) {
      case DownloadCategory.all:
        return 'All';
      case DownloadCategory.video:
        return 'Video';
      case DownloadCategory.audio:
        return 'Audio';
      case DownloadCategory.images:
        return 'Images';
      case DownloadCategory.documents:
        return 'Documents';
      case DownloadCategory.archives:
        return 'Archives';
      case DownloadCategory.apps:
        return 'Apps';
      case DownloadCategory.other:
        return 'Other';
    }
  }

  String get folderName {
    switch (this) {
      case DownloadCategory.video:
        return 'Video';
      case DownloadCategory.audio:
        return 'Audio';
      case DownloadCategory.images:
        return 'Images';
      case DownloadCategory.documents:
        return 'Documents';
      case DownloadCategory.archives:
        return 'Archives';
      case DownloadCategory.apps:
        return 'Apps';
      default:
        return 'Other';
    }
  }
}

enum SpeedMode {
  unlimited(0, 'Unlimited'),
  high(5 * 1024 * 1024, 'High (5 MB/s)'),
  medium(1 * 1024 * 1024, 'Med (1 MB/s)'),
  low(256 * 1024, 'Low (256 KB/s)');

  final int bytesPerSec;
  final String label;
  const SpeedMode(this.bytesPerSec, this.label);
}

class NetGetConstants {
  static const String appName = 'NetGet';
  static const String appSubtitle = 'Download Manager';
  static const String userAgent = 'NetGet/1.0 (Android; en-US)';

  /// Default connections per download
  static const int defaultConnections = 4;
  static const int minConnections = 1;
  static const int maxConnections = 16;

  /// Default concurrent download limit
  static const int maxConcurrentDownloads = 3;

  /// Connection timeout for starting requests
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Default queue name
  static const String defaultQueueName = 'Main';

  /// Resolves the storage directory for downloaded files.
  static Future<Directory> getDownloadsDirectory({String? subFolder}) async {
    Directory baseDir;
    try {
      if (Platform.isAndroid) {
        final externalDirs = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (externalDirs != null && externalDirs.isNotEmpty) {
          baseDir = externalDirs.first;
        } else {
          final docsDir = await getApplicationDocumentsDirectory();
          baseDir = Directory(p.join(docsDir.path, 'NetGetDownloads'));
        }
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        baseDir = Directory(p.join(docsDir.path, 'NetGetDownloads'));
      }
    } catch (_) {
      final docsDir = await getApplicationDocumentsDirectory();
      baseDir = Directory(p.join(docsDir.path, 'NetGetDownloads'));
    }

    if (subFolder != null && subFolder.isNotEmpty) {
      final target = Directory(p.join(baseDir.path, subFolder));
      if (!await target.exists()) {
        await target.create(recursive: true);
      }
      return target;
    }

    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    return baseDir;
  }
}
