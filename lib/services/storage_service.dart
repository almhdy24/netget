import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/constants.dart';
import '../core/utils.dart';

/// Manages the two-stage download storage architecture (ADR 002).
///
/// Stage 1 (In-progress): Random-access writes live in `<app external files>/parts/<taskId>.part`.
/// Stage 2 (Finalize): On completion, verified and moved to public `Downloads/NetGet/<Category>/`
/// or user-selected custom folder via SAF/MediaStore.
class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService();
  static set instance(StorageService s) => _instance = s;

  static const MethodChannel _platform = MethodChannel(
    'com.elmahdi.netget/engine',
  );

  final Future<Directory> Function()? _externalFilesResolver;
  final Future<Directory> Function()? _publicDownloadsResolver;

  StorageService({
    Future<Directory> Function()? externalFilesResolver,
    Future<Directory> Function()? publicDownloadsResolver,
  }) : _externalFilesResolver = externalFilesResolver,
       _publicDownloadsResolver = publicDownloadsResolver;

  /// Returns the base directory for in-progress .part files.
  Future<Directory> getPartsDirectory() async {
    final Directory base;
    if (_externalFilesResolver != null) {
      base = await _externalFilesResolver();
    } else {
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        base = extDir ?? await getApplicationSupportDirectory();
      } else {
        base = await getApplicationSupportDirectory();
      }
    }

    final partsDir = Directory(p.join(base.path, 'parts'));
    if (!await partsDir.exists()) {
      await partsDir.create(recursive: true);
    }
    return partsDir;
  }

  /// Returns the in-progress .part file path for a download task.
  Future<String> getPartFilePath(String taskId) async {
    final partsDir = await getPartsDirectory();
    return p.join(partsDir.path, '$taskId.part');
  }

  /// Resolves the public destination directory for completed downloads.
  Future<Directory> getPublicDownloadDirectory({
    required DownloadCategory category,
    String? customFolderPath,
  }) async {
    if (customFolderPath != null && customFolderPath.trim().isNotEmpty) {
      final customDir = Directory(customFolderPath.trim());
      if (await customDir.exists()) {
        return customDir;
      }
    }

    Directory baseDownloads;
    if (_publicDownloadsResolver != null) {
      baseDownloads = await _publicDownloadsResolver();
    } else if (Platform.isAndroid) {
      // Standard public Android downloads path: /storage/emulated/0/Download/NetGet/<Category>
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        baseDownloads = downloadDir;
      } else {
        baseDownloads =
            (await getDownloadsDirectory()) ??
            (await getApplicationDocumentsDirectory());
      }
    } else {
      baseDownloads =
          (await getDownloadsDirectory()) ??
          (await getApplicationDocumentsDirectory());
    }

    final categoryDirName = category.folderName;
    final targetDir = Directory(
      p.join(baseDownloads.path, 'NetGet', categoryDirName),
    );
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  }

  /// Resolves a collision-free target file path in the public directory.
  Future<String> resolveTargetFilePath({
    required String fileName,
    required DownloadCategory category,
    String? customFolderPath,
  }) async {
    final targetDir = await getPublicDownloadDirectory(
      category: category,
      customFolderPath: customFolderPath,
    );

    var candidate = p.join(targetDir.path, fileName);
    if (!await File(candidate).exists()) {
      return candidate;
    }

    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex > 0 ? fileName.substring(dotIndex) : '';

    var counter = 1;
    while (await File(p.join(targetDir.path, '$base($counter)$ext')).exists()) {
      counter++;
    }
    return p.join(targetDir.path, '$base($counter)$ext');
  }

  /// Finalizes completed download: verifies size, moves from .part to final public path,
  /// and deletes .part only upon successful verification.
  Future<String> finalizeDownload({
    required String partFilePath,
    required String targetFilePath,
    required int expectedBytes,
    void Function(double progress)? onProgress,
  }) async {
    final partFile = File(partFilePath);
    if (!await partFile.exists()) {
      throw FileSystemException('Part file does not exist', partFilePath);
    }

    final partSize = await partFile.length();
    if (expectedBytes > 0 && partSize < expectedBytes) {
      throw FileSystemException(
        'Incomplete part file: expected $expectedBytes bytes, found $partSize bytes',
        partFilePath,
      );
    }

    final targetFile = File(targetFilePath);
    final targetParent = targetFile.parent;
    if (!await targetParent.exists()) {
      await targetParent.create(recursive: true);
    }

    onProgress?.call(0.1);

    // Attempt fast atomic rename first
    try {
      await NetGetUtils.safeRenameFile(partFile, targetFile);
      onProgress?.call(1.0);
      return targetFilePath;
    } catch (_) {
      // Cross-filesystem move fallback: chunked stream copy
      final reader = partFile.openRead();
      final writer = targetFile.openWrite();
      int copied = 0;

      await for (final chunk in reader) {
        writer.add(chunk);
        copied += chunk.length;
        if (expectedBytes > 0) {
          onProgress?.call(copied / expectedBytes);
        }
      }
      await writer.flush();
      await writer.close();

      // Verify copied file size before deleting .part
      final copiedSize = await targetFile.length();
      if (expectedBytes > 0 && copiedSize != expectedBytes) {
        try {
          await targetFile.delete();
        } catch (_) {}
        throw FileSystemException(
          'Target file size mismatch after copy: expected $expectedBytes, got $copiedSize',
          targetFilePath,
        );
      }

      // Safe deletion of temporary .part
      try {
        await partFile.delete();
      } catch (_) {}

      onProgress?.call(1.0);
      return targetFilePath;
    }
  }

  /// Opens the file using the native Android intent and FileProvider.
  Future<bool> openFile(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final result = await _platform.invokeMethod<bool>('openFile', {
          'path': filePath,
        });
        return result ?? false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }

  /// Shares the file using native Android ACTION_SEND intent and FileProvider.
  Future<bool> shareFile(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final result = await _platform.invokeMethod<bool>('shareFile', {
          'path': filePath,
        });
        return result ?? false;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
