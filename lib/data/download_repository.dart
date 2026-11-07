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
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        return [];
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final tasks = <DownloadTask>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            var task = DownloadTask.fromJson(item);
            // If the app closed while a task was downloading or queued, mark it paused
            if (task.status == DownloadStatus.downloading ||
                task.status == DownloadStatus.queued) {
              task = task.copyWith(
                status: DownloadStatus.paused,
                speedBytesPerSec: 0.0,
              );
            }
            tasks.add(task);
          } catch (e) {
            debugPrint('Error parsing stored download task: $e');
          }
        }
      }
      return tasks;
    } catch (e) {
      debugPrint('Failed to load download tasks from file: $e');
      return [];
    }
  }

  @override
  Future<void> saveTasks(List<DownloadTask> tasks) async {
    try {
      final file = await _getFile();
      final tempFile = File('${file.path}.tmp');

      final list = tasks.map((t) => t.toJson()).toList();
      final raw = const JsonEncoder.withIndent('  ').convert(list);

      await tempFile.writeAsString(raw, flush: true);
      if (await tempFile.exists()) {
        await NetGetUtils.safeRenameFile(tempFile, file);
      }
    } catch (e) {
      debugPrint('Failed to save download tasks: $e');
    }
  }

  @override
  Future<void> saveTask(DownloadTask task) async {
    final tasks = await loadTasks();
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.insert(0, task);
    }
    await saveTasks(tasks);
  }

  @override
  Future<void> deleteTask(String id) async {
    final tasks = await loadTasks();
    tasks.removeWhere((t) => t.id == id);
    await saveTasks(tasks);
  }
}
