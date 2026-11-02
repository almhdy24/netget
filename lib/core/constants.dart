import 'dart:io';
import 'package:path_provider/path_provider.dart';

class NetGetConstants {
  static const String appName = 'NetGet';
  static const String appSubtitle = 'Download Manager';
  static const String userAgent = 'NetGet/1.0 (Android; en-US)';

  /// Default concurrent download limit to avoid starving bandwidth or device I/O.
  static const int maxConcurrentDownloads = 3;

  /// Connection timeout for starting requests.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Resolves the storage directory for downloaded files.
  /// Uses app-specific external storage Downloads directory if available,
  /// falling back to app documents directory.
  static Future<Directory> getDownloadsDirectory() async {
    try {
      if (Platform.isAndroid) {
        final externalDirs = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (externalDirs != null && externalDirs.isNotEmpty) {
          final dir = externalDirs.first;
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir;
        }
      }
    } catch (_) {}

    final docsDir = await getApplicationDocumentsDirectory();
    final downloads = Directory('${docsDir.path}/NetGetDownloads');
    if (!await downloads.exists()) {
      await downloads.create(recursive: true);
    }
    return downloads;
  }
}
