import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../data/download_repository.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';

class _ActiveDownloadContext {
  HttpClientRequest? request;
  StreamSubscription<List<int>>? subscription;
  IOSink? sink;
  bool isPaused = false;
  bool isCancelled = false;
}

class DownloadManager extends ChangeNotifier {
  final DownloadRepository _repository;
  final HttpClient Function()? _clientFactory;
  final Future<Directory> Function()? _downloadsDirResolver;

  List<DownloadTask> _tasks = [];
  final Map<String, _ActiveDownloadContext> _activeContexts = {};
  bool _isInitialized = false;

  DownloadManager({
    required DownloadRepository repository,
    HttpClient Function()? clientFactory,
    Future<Directory> Function()? downloadsDirResolver,
  })  : _repository = repository,
        _clientFactory = clientFactory,
        _downloadsDirResolver = downloadsDirResolver;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  List<DownloadTask> get activeTasks =>
      _tasks.where((t) => t.status.isActive).toList();

  List<DownloadTask> get pausedTasks =>
      _tasks.where((t) => t.status.isPaused).toList();

  List<DownloadTask> get completedTasks =>
      _tasks.where((t) => t.status.isCompleted).toList();

  List<DownloadTask> get failedTasks =>
      _tasks.where((t) => t.status.isFailed).toList();

  int get totalDownloadedBytes => _tasks.fold<int>(
        0,
        (sum, task) => sum + task.downloadedBytes,
      );

  double get currentTotalSpeed => _tasks
      .where((t) => t.status == DownloadStatus.downloading)
      .fold<double>(0.0, (sum, task) => sum + task.speedBytesPerSec);

  bool get isInitialized => _isInitialized;

  /// Initializes the manager and loads existing persisted tasks.
  Future<void> init({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    _tasks = await _repository.loadTasks();
    _isInitialized = true;
    notifyListeners();
  }

  /// Adds a new download URL to the queue.
  Future<DownloadTask> addDownload({
    required String url,
    String? customFileName,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw ArgumentError('Invalid URL scheme: only http and https are supported');
    }

    final id = 'task_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length + 1}';
    final rawName = (customFileName != null && customFileName.trim().isNotEmpty)
        ? customFileName.trim()
        : NetGetUtils.extractFileNameFromUrl(cleanUrl);
    final fileName = NetGetUtils.sanitizeFileName(rawName);

    final downloadsDir = _downloadsDirResolver != null
        ? await _downloadsDirResolver()
        : await NetGetConstants.getDownloadsDirectory();
    final savePath = await _resolveUniqueFilePath(downloadsDir.path, fileName);

    final task = DownloadTask(
      id: id,
      url: cleanUrl,
      fileName: fileName,
      savePath: savePath,
      status: DownloadStatus.queued,
      createdAt: DateTime.now(),
    );

    _tasks.insert(0, task);
    await _repository.saveTasks(_tasks);
    notifyListeners();

    _processQueue();
    return task;
  }

  /// Pauses an active downloading task.
  Future<void> pauseDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final task = _tasks[index];
    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.queued) {
      return;
    }

    final ctx = _activeContexts[id];
    if (ctx != null) {
      ctx.isPaused = true;
      try {
        await ctx.subscription?.cancel();
        await ctx.sink?.flush();
        await ctx.sink?.close();
        ctx.request?.abort();
      } catch (_) {}
      _activeContexts.remove(id);
    }

    _tasks[index] = task.copyWith(
      status: DownloadStatus.paused,
      speedBytesPerSec: 0.0,
    );

    await _repository.saveTasks(_tasks);
    notifyListeners();

    _processQueue();
  }

  /// Resumes a paused or failed task.
  Future<void> resumeDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final task = _tasks[index];
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return;
    }

    _tasks[index] = task.copyWith(
      status: DownloadStatus.queued,
      errorMessage: null,
      speedBytesPerSec: 0.0,
    );

    await _repository.saveTasks(_tasks);
    notifyListeners();

    _processQueue();
  }

  /// Retries a failed or cancelled task.
  Future<void> retryDownload(String id) async {
    await resumeDownload(id);
  }

  /// Cancels an active or queued download.
  Future<void> cancelDownload(String id, {bool deleteFile = false}) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final task = _tasks[index];
    final ctx = _activeContexts[id];
    if (ctx != null) {
      ctx.isCancelled = true;
      try {
        await ctx.subscription?.cancel();
        await ctx.sink?.flush();
        await ctx.sink?.close();
        ctx.request?.abort();
      } catch (_) {}
      _activeContexts.remove(id);
    }

    if (deleteFile && task.savePath.isNotEmpty) {
      try {
        final file = File(task.savePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _tasks[index] = task.copyWith(
      status: DownloadStatus.cancelled,
      speedBytesPerSec: 0.0,
      downloadedBytes: deleteFile ? 0 : task.downloadedBytes,
    );

    await _repository.saveTasks(_tasks);
    notifyListeners();

    _processQueue();
  }

  /// Deletes a task from history, optionally deleting the file from storage.
  Future<void> deleteTask(String id, {bool deleteFile = false}) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final task = _tasks[index];
    if (task.status.isActive) {
      await cancelDownload(id, deleteFile: deleteFile);
    } else if (deleteFile && task.savePath.isNotEmpty) {
      try {
        final file = File(task.savePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _tasks.removeWhere((t) => t.id == id);
    await _repository.saveTasks(_tasks);
    notifyListeners();
  }

  /// Clears all completed tasks from history.
  Future<void> clearCompleted({bool deleteFiles = false}) async {
    final completed = _tasks.where((t) => t.status.isCompleted).toList();
    for (final task in completed) {
      if (deleteFiles && task.savePath.isNotEmpty) {
        try {
          final file = File(task.savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
    _tasks.removeWhere((t) => t.status.isCompleted);
    await _repository.saveTasks(_tasks);
    notifyListeners();
  }

  /// Checks queue and starts pending downloads if under max concurrency limit.
  void _processQueue() {
    final downloadingCount = _tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .length;

    final availableSlots = NetGetConstants.maxConcurrentDownloads - downloadingCount;
    if (availableSlots <= 0) return;

    final queuedTasks = _tasks
        .where((t) => t.status == DownloadStatus.queued)
        .take(availableSlots)
        .toList();

    for (final task in queuedTasks) {
      _startDownloading(task.id);
    }
  }

  HttpClient _createHttpClient() {
    if (_clientFactory != null) {
      return _clientFactory();
    }
    final client = HttpClient()
      ..connectionTimeout = NetGetConstants.connectTimeout
      ..badCertificateCallback = ((cert, host, port) => true);
    return client;
  }

  Future<void> _startDownloading(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index < 0) return;

    var currentTask = _tasks[index];
    if (currentTask.status == DownloadStatus.downloading) return;

    // Update status to downloading
    currentTask = currentTask.copyWith(
      status: DownloadStatus.downloading,
      speedBytesPerSec: 0.0,
      errorMessage: null,
    );
    _tasks[index] = currentTask;
    notifyListeners();

    final ctx = _ActiveDownloadContext();
    _activeContexts[taskId] = ctx;

    HttpClient? client;
    try {
      client = _createHttpClient();
      final file = File(currentTask.savePath);
      int existingBytes = 0;
      if (await file.exists()) {
        existingBytes = await file.length();
      }

      // If file is already fully downloaded
      if (currentTask.totalBytes > 0 && existingBytes >= currentTask.totalBytes) {
        _tasks[index] = currentTask.copyWith(
          downloadedBytes: currentTask.totalBytes,
          status: DownloadStatus.completed,
          speedBytesPerSec: 0.0,
          completedAt: DateTime.now(),
        );
        _activeContexts.remove(taskId);
        client.close(force: true);
        await _repository.saveTasks(_tasks);
        notifyListeners();
        _processQueue();
        return;
      }

      final uri = Uri.parse(currentTask.url);
      final request = await client.getUrl(uri);
      ctx.request = request;

      request.headers.set(HttpHeaders.userAgentHeader, NetGetConstants.userAgent);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');

      // Attempt Range request if partial file exists and task is resumable
      final shouldRange = existingBytes > 0 && currentTask.resumable;
      if (shouldRange) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();

      if (ctx.isPaused || ctx.isCancelled) {
        client.close(force: true);
        return;
      }

      // Check HTTP Status
      final statusCode = response.statusCode;
      if (statusCode >= 400) {
        throw HttpException(
          'HTTP $statusCode: ${response.reasonPhrase}',
          uri: uri,
        );
      }

      bool isAppend = false;
      int totalBytes = currentTask.totalBytes;
      bool resumable = currentTask.resumable;

      if (statusCode == HttpStatus.partialContent) {
        // 206 Partial Content: Server successfully accepted range request
        isAppend = true;
        resumable = true;
        final len = response.contentLength;
        if (len > 0) {
          totalBytes = existingBytes + len;
        }
      } else if (statusCode == HttpStatus.ok) {
        // 200 OK: Full file returned
        isAppend = false;
        existingBytes = 0;
        final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader);
        resumable = acceptRanges?.toLowerCase() == 'bytes';
        totalBytes = response.contentLength;
      }

      // Extract filename from Content-Disposition if not explicitly given
      final contentDisposition = response.headers.value('content-disposition');
      String updatedFileName = currentTask.fileName;
      if (contentDisposition != null) {
        final parsedName = _parseContentDispositionFileName(contentDisposition);
        if (parsedName != null && parsedName.isNotEmpty) {
          updatedFileName = NetGetUtils.sanitizeFileName(parsedName);
        }
      }

      var downloadedBytes = existingBytes;

      _tasks[index] = currentTask.copyWith(
        fileName: updatedFileName,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        resumable: resumable,
      );
      notifyListeners();

      final sink = file.openWrite(
        mode: isAppend ? FileMode.append : FileMode.write,
      );
      ctx.sink = sink;

      final stopwatch = Stopwatch()..start();
      int bytesSinceLastTick = 0;
      DateTime lastEmitTime = DateTime.now();

      final subscription = response.listen(
        (chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          bytesSinceLastTick += chunk.length;

          final now = DateTime.now();
          if (now.difference(lastEmitTime).inMilliseconds >= 700) {
            final elapsedSec = stopwatch.elapsedMicroseconds / 1000000.0;
            final speed = elapsedSec > 0 ? (bytesSinceLastTick / elapsedSec) : 0.0;

            stopwatch.reset();
            bytesSinceLastTick = 0;
            lastEmitTime = now;

            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx >= 0 && _tasks[idx].status == DownloadStatus.downloading) {
              _tasks[idx] = _tasks[idx].copyWith(
                downloadedBytes: downloadedBytes,
                speedBytesPerSec: speed,
              );
              notifyListeners();
            }
          }
        },
        onError: (error) async {
          await sink.flush();
          await sink.close();
          client?.close(force: true);
          _activeContexts.remove(taskId);

          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx >= 0) {
            final t = _tasks[idx];
            if (!t.status.isPaused && !t.status.isCancelled) {
              _tasks[idx] = t.copyWith(
                status: DownloadStatus.failed,
                errorMessage: _cleanErrorMessage(error),
                speedBytesPerSec: 0.0,
                downloadedBytes: downloadedBytes,
              );
              await _repository.saveTasks(_tasks);
              notifyListeners();
            }
          }
          _processQueue();
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          client?.close(force: true);
          _activeContexts.remove(taskId);

          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx >= 0) {
            final t = _tasks[idx];
            if (t.status == DownloadStatus.downloading) {
              _tasks[idx] = t.copyWith(
                status: DownloadStatus.completed,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes > 0 ? totalBytes : downloadedBytes,
                speedBytesPerSec: 0.0,
                completedAt: DateTime.now(),
              );
              await _repository.saveTasks(_tasks);
              notifyListeners();
            }
          }
          _processQueue();
        },
        cancelOnError: true,
      );

      ctx.subscription = subscription;
    } catch (e) {
      client?.close(force: true);
      _activeContexts.remove(taskId);

      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx >= 0) {
        final t = _tasks[idx];
        if (!t.status.isPaused && !t.status.isCancelled) {
          _tasks[idx] = t.copyWith(
            status: DownloadStatus.failed,
            errorMessage: _cleanErrorMessage(e),
            speedBytesPerSec: 0.0,
          );
          await _repository.saveTasks(_tasks);
          notifyListeners();
        }
      }
      _processQueue();
    }
  }

  String _cleanErrorMessage(dynamic error) {
    if (error is SocketException) {
      return 'Network connection failed (${error.osError?.message ?? error.message})';
    }
    if (error is HttpException) {
      return error.message;
    }
    if (error is HandshakeException) {
      return 'SSL/TLS handshake error';
    }
    if (error is TimeoutException) {
      return 'Connection timed out';
    }
    return error.toString().replaceFirst(RegExp(r'^[A-Za-z0-9_]+Exception:\s*'), '');
  }

  String? _parseContentDispositionFileName(String header) {
    try {
      final utf8Match = RegExp(r"filename\*=UTF-8''([^;]+)", caseSensitive: false)
          .firstMatch(header);
      if (utf8Match != null) {
        return Uri.decodeComponent(utf8Match.group(1) ?? '');
      }

      final quotedMatch = RegExp(r'filename="([^"]+)"', caseSensitive: false)
          .firstMatch(header);
      if (quotedMatch != null) {
        return quotedMatch.group(1);
      }

      final plainMatch = RegExp(r'filename=([^;]+)', caseSensitive: false)
          .firstMatch(header);
      if (plainMatch != null) {
        return plainMatch.group(1)?.trim();
      }
    } catch (_) {}
    return null;
  }

  Future<String> _resolveUniqueFilePath(String dirPath, String fileName) async {
    var candidate = '$dirPath/$fileName';
    if (!await File(candidate).exists()) {
      return candidate;
    }

    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex > 0 ? fileName.substring(dotIndex) : '';

    var counter = 1;
    while (await File('$dirPath/$base($counter)$ext').exists()) {
      counter++;
    }
    return '$dirPath/$base($counter)$ext';
  }
}
