import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/utils.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';

abstract class DownloadRepository {
  Future<List<DownloadTask>> loadTasks();
  Future<void> saveTasks(List<DownloadTask> tasks);
  Future<void> saveTask(DownloadTask task);
  Future<void> deleteTask(String id);
}

class JsonDownloadRepository implements DownloadRepository {
  final File? _customFile;
  File? _resolvedFile;
  List<DownloadTask>? _cachedTasks;
  Future<void> _writeQueue = Future.value();

  JsonDownloadRepository({File? file}) : _customFile = file;

  Future<File> _getFile() async {
    if (_customFile != null) return _customFile;
    if (_resolvedFile != null) return _resolvedFile!;

    final docsDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(docsDir.path, 'netget_tasks.json'));
    _resolvedFile = file;
    return file;
  }

  @override
  Future<List<DownloadTask>> loadTasks() async {
    if (_cachedTasks != null) {
      return List<DownloadTask>.from(_cachedTasks!);
    }

    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _cachedTasks = [];
        return [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _cachedTasks = [];
        return [];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cachedTasks = [];
        return [];
      }

      final tasks = <DownloadTask>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            var task = DownloadTask.fromJson(item);
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.queued) {
              task = task.copyWith(
                status: DownloadStatus.paused,
                speedBytesPerSec: 0.0,
              );
            }
            tasks.add(task);
          } catch (e, st) {
            debugPrint('Error parsing stored download task: $e\n$st');
          }
        }
      }
      _cachedTasks = tasks;
      return List<DownloadTask>.from(tasks);
    } catch (e, st) {
      debugPrint('Failed to load download tasks from file: $e\n$st');
      _cachedTasks = [];
      return [];
    }
  }

  @override
  Future<void> saveTasks(List<DownloadTask> tasks) {
    _cachedTasks = List<DownloadTask>.from(tasks);

    _writeQueue = _writeQueue.then((_) async {
      try {
        final file = await _getFile();
        final tempFile = File('${file.path}.tmp');

        final list = tasks.map((t) => t.toJson()).toList();
        final raw = const JsonEncoder.withIndent('  ').convert(list);

        await tempFile.writeAsString(raw, flush: true);
        if (await tempFile.exists()) {
          await NetGetUtils.safeRenameFile(tempFile, file);
        }
      } catch (e, st) {
        debugPrint('Failed to persist download tasks to disk: $e\n$st');
      }
    });

    return _writeQueue;
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final currentTasks = _cachedTasks ?? await loadTasks();
    final index = currentTasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      currentTasks[index] = task;
    } else {
      currentTasks.insert(0, task);
    }
    await saveTasks(currentTasks);
  }

  @override
  Future<void> deleteTask(String id) async {
    final currentTasks = _cachedTasks ?? await loadTasks();
    currentTasks.removeWhere((t) => t.id == id);
    await saveTasks(currentTasks);
  }
}
