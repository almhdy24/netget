import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../core/constants.dart';
import '../core/download_failure.dart';
import '../core/segment_planner.dart';
import '../core/utils.dart';
import '../data/download_repository.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';
import 'analytics_service.dart';
import 'multi_connection_downloader.dart';

class _ActiveDownloadContext {
  HttpClientRequest? request;
  StreamSubscription<List<int>>? subscription;
  IOSink? sink;
  MultiConnectionDownloader? multiDownloader;
  bool isPaused = false;
  bool isCancelled = false;
}

/// Result of quick URL inspection (HEAD or Range request).
class UrlAnalysisResult {
  final String url;
  final String fileName;
  final int totalBytes;
  final bool resumable;
  final DownloadCategory category;
  final String? etag;
  final String? lastModified;
  final String? mimeType;

  const UrlAnalysisResult({
    required this.url,
    required this.fileName,
    required this.totalBytes,
    required this.resumable,
    required this.category,
    this.etag,
    this.lastModified,
    this.mimeType,
  });
}

/// Configuration schedule for automated queue start/stop execution.
class QueueSchedule {
  final String queueName;
  final int startHour;
  final int startMinute;
  final int stopHour;
  final int stopMinute;
  final bool isEnabled;

  const QueueSchedule({
    required this.queueName,
    required this.startHour,
    required this.startMinute,
    required this.stopHour,
    required this.stopMinute,
    this.isEnabled = true,
  });

  String get formattedStartTime =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
  String get formattedStopTime =>
      '${stopHour.toString().padLeft(2, '0')}:${stopMinute.toString().padLeft(2, '0')}';
}

/// Stream event for live details screen (2-4 Hz).
class TaskDetailsUpdate {
  final DownloadTask task;
  final List<DownloadSegment> segments;
  final List<double> speedSamples;
  final List<TaskLogEvent> eventLog;

  const TaskDetailsUpdate({
    required this.task,
    required this.segments,
    required this.speedSamples,
    required this.eventLog,
  });
}

class DownloadManager extends ChangeNotifier {
  final DownloadRepository _repository;
  final HttpClient Function()? _clientFactory;
  final Future<Directory> Function()? _downloadsDirResolver;

  List<DownloadTask> _tasks = [];
  final Map<String, _ActiveDownloadContext> _activeContexts = {};
  bool _isInitialized = false;

  // Platform channel interface to Native Kotlin foreground service
  static const MethodChannel _platform = MethodChannel(
    'com.elmahdi.netget/engine',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.elmahdi.netget/events',
  );

  // In-memory desktop enhancements: ring buffers & state
  final Map<String, List<TaskLogEvent>> _taskLogs = {};
  final Map<String, List<double>> _taskSpeedSamples = {};
  final Map<String, int> _taskElapsedSeconds = {};
  final Map<String, QueueSchedule> _queueSchedules = {};
  Timer? _schedulerTimer;
  SpeedMode _speedMode = SpeedMode.unlimited;
  final List<String> _namedQueues = [NetGetConstants.defaultQueueName];
  final Map<String, bool> _activeQueues = {
    NetGetConstants.defaultQueueName: true,
  };
  final Map<String, Timer> _networkRetryTimers = {};
  final Map<String, ValueNotifier<DownloadTask>> _taskNotifiers = {};

  /// Retrieves a task-specific ValueNotifier to enable granular widget rebuilding without rebuilding the entire list.
  ValueNotifier<DownloadTask> getTaskNotifier(String taskId) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx >= 0) {
      final task = _tasks[idx];
      final notifier = _taskNotifiers[taskId];
      if (notifier != null) {
        if (notifier.value != task) {
          notifier.value = task;
        }
        return notifier;
      }
      return _taskNotifiers[taskId] = ValueNotifier<DownloadTask>(task);
    }
    return _taskNotifiers.putIfAbsent(
      taskId,
      () => ValueNotifier<DownloadTask>(
        DownloadTask(
          id: taskId,
          url: '',
          fileName: '',
          savePath: '',
          status: DownloadStatus.queued,
          createdAt: DateTime.now(),
        ),
      ),
    );
  }

  void _notifyTaskChanged(String taskId, DownloadTask updated) {
    final notifier = _taskNotifiers[taskId];
    if (notifier != null && notifier.value != updated) {
      notifier.value = updated;
    }
  }

  /// Emits a progress tick for a task, updating its in-memory state and notifying
  /// the task's ValueNotifier for immediate UI rebuild without waiting for disk throttle.
  void emitProgressTick(
    String taskId, {
    required int downloadedBytes,
    int? totalBytes,
    double speedBytesPerSec = 0.0,
    List<DownloadSegment>? segments,
  }) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx >= 0 && _tasks[idx].status == DownloadStatus.downloading) {
      final samples = _taskSpeedSamples.putIfAbsent(taskId, () => []);
      samples.add(speedBytesPerSec);
      if (samples.length > 60) samples.removeAt(0);

      final currentElapsed = (_taskElapsedSeconds[taskId] ?? 0) + 1;
      _taskElapsedSeconds[taskId] = currentElapsed;

      _tasks[idx] = _tasks[idx].copyWith(
        downloadedBytes: downloadedBytes,
        totalBytes: (totalBytes != null && totalBytes > 0)
            ? totalBytes
            : _tasks[idx].totalBytes,
        speedBytesPerSec: speedBytesPerSec,
        elapsedSeconds: currentElapsed,
        segments: segments ?? _tasks[idx].segments,
      );
      _notifyTaskChanged(taskId, _tasks[idx]);
      _syncActiveDownloadsToNative();
      scheduleThrottledSave();
    }
  }

  /// Default connections setting (default 1 preserves legacy single-stream behavior;
  /// multi-connection engine is activated when connections > 1 and server supports ranges).
  int defaultConnections = 1;

  DateTime Function() clock = DateTime.now;
  DateTime _lastSaveTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _saveThrottleTimer;
  bool _hasPendingSave = false;

  // Background keep-alive & native notification synchronization state
  int _reportedActiveCount = 0;
  DateTime _lastNativeProgressReport = DateTime.fromMillisecondsSinceEpoch(0);
  StreamSubscription<dynamic>? _nativeEventSubscription;
  bool isAndroidForTesting = false;
  Stream<dynamic>? eventStreamForTesting;

  /// Reports active download count and debounced progress summary to native foreground service.
  void _syncActiveDownloadsToNative({bool force = false}) {
    if (!Platform.isAndroid && !isAndroidForTesting) return;

    final downloadingTasks = _tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .toList();
    final currentDownloadingCount = downloadingTasks.length;
    final now = clock();

    int overallPercent = 0;
    String singleFileName = '';
    int totalBytes = -1;

    if (currentDownloadingCount == 1) {
      final t = downloadingTasks.first;
      singleFileName = t.fileName;
      totalBytes = t.totalBytes;
      overallPercent = ((t.progress ?? 0.0) * 100).round().clamp(0, 100);
    } else if (currentDownloadingCount > 1) {
      int sumDownloaded = 0;
      int sumTotal = 0;
      bool allTotalsKnown = true;
      for (final t in downloadingTasks) {
        sumDownloaded += t.downloadedBytes;
        if (t.totalBytes > 0) {
          sumTotal += t.totalBytes;
        } else {
          allTotalsKnown = false;
        }
      }
      totalBytes = allTotalsKnown ? sumTotal : -1;
      if (allTotalsKnown && sumTotal > 0) {
        overallPercent = ((sumDownloaded / sumTotal) * 100).round().clamp(
          0,
          100,
        );
      } else {
        overallPercent = 0;
      }
    }

    // 0 <-> N transitions or active count changes are reported immediately
    if (force || currentDownloadingCount != _reportedActiveCount) {
      _reportedActiveCount = currentDownloadingCount;
      _lastNativeProgressReport = now;
      final speedText = currentDownloadingCount > 0
          ? NetGetUtils.formatSpeed(currentTotalSpeed)
          : '';
      _invokeNative('updateActiveDownloads', {
        'activeCount': currentDownloadingCount,
        'progressText': speedText,
        'percent': overallPercent,
        'name': singleFileName,
        'totalBytes': totalBytes,
      });
    } else if (currentDownloadingCount > 0) {
      // Progress updates throttled to at most once per second
      final elapsedMs = now
          .difference(_lastNativeProgressReport)
          .inMilliseconds;
      if (elapsedMs >= 1000) {
        _lastNativeProgressReport = now;
        final speedText = NetGetUtils.formatSpeed(currentTotalSpeed);
        _invokeNative('updateActiveDownloads', {
          'activeCount': currentDownloadingCount,
          'progressText': speedText,
          'percent': overallPercent,
          'name': singleFileName,
          'totalBytes': totalBytes,
        });
      }
    }
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncActiveDownloadsToNative();
  }

  /// Throttled save: max 1 save per second across progress ticks.
  void scheduleThrottledSave() {
    final now = clock();
    final elapsedMs = now.difference(_lastSaveTime).inMilliseconds;
    if (elapsedMs >= 1000) {
      _saveThrottleTimer?.cancel();
      _saveThrottleTimer = null;
      _hasPendingSave = false;
      _lastSaveTime = now;
      _repository.saveTasks(_tasks);
    } else {
      _hasPendingSave = true;
      if (_saveThrottleTimer == null || !_saveThrottleTimer!.isActive) {
        final waitMs = 1000 - elapsedMs;
        _saveThrottleTimer = Timer(Duration(milliseconds: waitMs), () {
          if (_hasPendingSave) {
            _hasPendingSave = false;
            _lastSaveTime = clock();
            _repository.saveTasks(_tasks);
          }
        });
      }
    }
  }

  /// Immediate save for lifecycle state transitions (pause, cancel, complete, delete, add).
  Future<void> saveImmediate() async {
    _saveThrottleTimer?.cancel();
    _saveThrottleTimer = null;
    _hasPendingSave = false;
    _lastSaveTime = clock();
    await _repository.saveTasks(_tasks);
  }

  DownloadManager({
    required DownloadRepository repository,
    HttpClient Function()? clientFactory,
    Future<Directory> Function()? downloadsDirResolver,
  }) : _repository = repository,
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

  int get totalDownloadedBytes =>
      _tasks.fold<int>(0, (sum, task) => sum + task.downloadedBytes);

  double get currentTotalSpeed => _tasks
      .where((t) => t.status == DownloadStatus.downloading)
      .fold<double>(0.0, (sum, task) => sum + task.speedBytesPerSec);

  int get queuedCount =>
      _tasks.where((t) => t.status == DownloadStatus.queued).length;

  int get completedTodayCount {
    final now = DateTime.now();
    return _tasks.where((t) {
      if (!t.status.isCompleted || t.completedAt == null) return false;
      final c = t.completedAt!;
      return c.year == now.year && c.month == now.month && c.day == now.day;
    }).length;
  }

  SpeedMode get speedMode => _speedMode;
  List<String> get namedQueues => List.unmodifiable(_namedQueues);
  bool get isInitialized => _isInitialized;

  /// Changes the global speed mode
  void setSpeedMode(SpeedMode mode) {
    _speedMode = mode;
    _invokeNative('setSpeedLimit', {'bytesPerSec': mode.bytesPerSec});
    notifyListeners();
    AnalyticsService.trackSettingChanged(
      settingName: 'speed_mode',
      settingValue: mode.name,
    );
  }

  Future<void> _invokeNative(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (Platform.isAndroid || isAndroidForTesting) {
      try {
        await _platform.invokeMethod(method, args);
      } on PlatformException catch (e) {
        debugPrint(
          'Native MethodChannel error ($method): ${e.code} - ${e.message}',
        );
        // ForegroundServiceStartNotAllowedException or permission denial: Dart engine
        // logs warning and safely continues downloading without crashing or aborting.
      } catch (e) {
        debugPrint('Unexpected error calling native channel ($method): $e');
      }
    }
  }

  /// Appends an event to the task's in-memory ring buffer (up to 200 events).
  void logEvent(String taskId, String level, String message) {
    final list = _taskLogs.putIfAbsent(taskId, () => []);
    list.add(
      TaskLogEvent(timestamp: DateTime.now(), level: level, message: message),
    );
    if (list.length > 200) {
      list.removeAt(0);
    }
  }

  /// Retrieves cached logs for a task.
  List<TaskLogEvent> getTaskLogs(String taskId) {
    return List.unmodifiable(_taskLogs[taskId] ?? []);
  }

  /// Retrieves cached 60-sample speed history for sparkline.
  List<double> getSpeedSamples(String taskId) {
    return List.unmodifiable(_taskSpeedSamples[taskId] ?? []);
  }

  /// Finds existing task with identical URL for duplicate detection.
  DownloadTask? findTaskByUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return null;
    try {
      return _tasks.firstWhere((t) => t.url.trim() == clean);
    } catch (_) {
      return null;
    }
  }

  /// Initializes the manager and loads existing persisted tasks.
  Future<void> init({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    _tasks = await _repository.loadTasks();
    _isInitialized = true;
    _startSchedulerTimer();
    _initNativeBridge();
    notifyListeners();
  }

  void _initNativeBridge() {
    if (Platform.isAndroid || isAndroidForTesting) {
      try {
        _nativeEventSubscription?.cancel();
        final stream =
            eventStreamForTesting ?? _eventChannel.receiveBroadcastStream();
        _nativeEventSubscription = stream.listen((dynamic event) {
          if (event is Map) {
            // Android 15 dataSync 6-hour timeout event: pause all downloads cleanly
            if (event['event'] == 'onTimeout') {
              pauseAll();
              return;
            }
            final taskId = event['taskId'] as String?;
            final downloaded = (event['downloadedBytes'] as num?)?.toInt();
            final speed = (event['speedBytesPerSec'] as num?)?.toDouble();
            if (taskId != null) {
              final idx = _tasks.indexWhere((t) => t.id == taskId);
              if (idx >= 0) {
                final updated = _tasks[idx].copyWith(
                  downloadedBytes: downloaded ?? _tasks[idx].downloadedBytes,
                  speedBytesPerSec: speed ?? _tasks[idx].speedBytesPerSec,
                );
                _tasks[idx] = updated;
                _notifyTaskChanged(taskId, updated);
                _throttleAggregateNotify();
              }
            }
          }
        }, onError: (_) {});
      } catch (_) {}
    }
  }

  DateTime _lastAggregateNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _aggregateNotifyTimer;

  void _throttleAggregateNotify() {
    final now = DateTime.now();
    if (now.difference(_lastAggregateNotify).inMilliseconds >= 250) {
      _lastAggregateNotify = now;
      notifyListeners();
    } else {
      _aggregateNotifyTimer ??= Timer(const Duration(milliseconds: 250), () {
        _aggregateNotifyTimer = null;
        _lastAggregateNotify = DateTime.now();
        notifyListeners();
      });
    }
  }

  /// Performs quick link analysis (HEAD / Range: 0-0) without starting download.
  Future<UrlAnalysisResult> analyzeUrl(
    String rawUrl, {
    Map<String, String>? headers,
  }) async {
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw ArgumentError('Invalid URL: scheme must be http or https');
    }

    HttpClient? client;
    try {
      client = _createHttpClient();
      HttpClientRequest request;
      try {
        request = await client.headUrl(uri);
      } catch (_) {
        request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      }

      request.headers.set(
        HttpHeaders.userAgentHeader,
        NetGetConstants.userAgent,
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (headers != null) {
        headers.forEach((k, v) => request.headers.set(k, v));
      }

      final response = await request.close();
      final cd = response.headers.value('content-disposition');
      final parsedCd = NetGetUtils.parseContentDisposition(cd);
      final fileName = parsedCd ?? NetGetUtils.extractFileNameFromUrl(cleanUrl);
      final mime = response.headers.value(HttpHeaders.contentTypeHeader);
      final category = NetGetUtils.classifyCategory(fileName, mime);
      final acceptRanges = response.headers.value(
        HttpHeaders.acceptRangesHeader,
      );
      final isResumable =
          (acceptRanges?.toLowerCase() == 'bytes') ||
          (response.statusCode == HttpStatus.partialContent);
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final lastModified = response.headers.value(
        HttpHeaders.lastModifiedHeader,
      );
      final len = response.contentLength;

      return UrlAnalysisResult(
        url: cleanUrl,
        fileName: fileName,
        totalBytes: len > 0 ? len : -1,
        resumable: isResumable,
        category: category,
        etag: etag,
        lastModified: lastModified,
        mimeType: mime,
      );
    } finally {
      client?.close(force: true);
    }
  }

  /// Adds a new download URL with full desktop options.
  Future<DownloadTask> addDownload({
    required String url,
    String? customFileName,
    bool startNow = true,
    DownloadCategory? category,
    int? connectionCount,
    String? subFolder,
    String? queueName,
    String? referrer,
    int? totalBytes,
    bool? resumable,
    String? etag,
    String? lastModified,
    String source = 'link',
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) {
      throw ArgumentError('URL cannot be empty');
    }

    final uri = Uri.tryParse(cleanUrl);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw ArgumentError(
        'Invalid URL scheme: only http and https are supported',
      );
    }

    final id =
        'task_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length + 1}';
    final rawName = (customFileName != null && customFileName.trim().isNotEmpty)
        ? customFileName.trim()
        : NetGetUtils.extractFileNameFromUrl(cleanUrl);
    final fileName = NetGetUtils.sanitizeFileName(rawName);

    final resolvedCategory = category ?? NetGetUtils.classifyCategory(fileName);
    final folderName = subFolder ?? resolvedCategory.folderName;

    final downloadsDir = _downloadsDirResolver != null
        ? await _downloadsDirResolver()
        : await NetGetConstants.getDownloadsDirectory(subFolder: folderName);
    final savePath = await _resolveUniqueFilePath(downloadsDir.path, fileName);

    final connCount = connectionCount ?? defaultConnections;
    final isResumable = resumable ?? true;
    final fileTotalBytes = totalBytes ?? -1;

    // Plan initial segments
    final initialSegments = SegmentPlanner.planInitialSegments(
      totalBytes: fileTotalBytes,
      connectionCount: connCount,
      resumable: isResumable,
    );

    final initialStatus = startNow
        ? DownloadStatus.queued
        : DownloadStatus.paused;

    final task = DownloadTask(
      id: id,
      url: cleanUrl,
      fileName: fileName,
      savePath: savePath,
      totalBytes: fileTotalBytes,
      status: initialStatus,
      createdAt: DateTime.now(),
      category: resolvedCategory,
      connectionCount: connCount,
      resumable: isResumable,
      etag: etag,
      lastModified: lastModified,
      referrer: referrer,
      queueName: queueName ?? NetGetConstants.defaultQueueName,
      segments: initialSegments,
    );

    logEvent(id, 'INFO', 'Download added: $fileName');
    if (!startNow) {
      logEvent(id, 'INFO', 'Download marked for later');
    }

    _tasks.insert(0, task);
    await saveImmediate();
    notifyListeners();

    AnalyticsService.trackDownloadAdded(
      source: source,
      category: resolvedCategory.name,
    );

    if (startNow) {
      _processQueue();
    }
    return task;
  }

  /// Refreshes expired link for a task after verifying compatibility.
  Future<void> refreshTaskUrl(String taskId, String newUrl) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) {
      throw Exception('Task not found');
    }
    final current = _tasks[idx];
    final analysis = await analyzeUrl(newUrl);

    if (current.totalBytes > 0 &&
        analysis.totalBytes > 0 &&
        current.totalBytes != analysis.totalBytes) {
      throw Exception(
        'Size mismatch: Existing file is ${NetGetUtils.formatBytes(current.totalBytes)}, '
        'but new link is ${NetGetUtils.formatBytes(analysis.totalBytes)}.',
      );
    }

    // Strict ETag check if provided by both
    if (current.etag != null &&
        analysis.etag != null &&
        current.etag!.isNotEmpty &&
        analysis.etag!.isNotEmpty &&
        current.etag != analysis.etag) {
      throw Exception(
        'ETag mismatch: Existing file ETag is "${current.etag}", but new link returned "${analysis.etag}". '
        'The remote file has changed and cannot be safely resumed.',
      );
    }

    // Strict Last-Modified check if provided by both
    if (current.lastModified != null &&
        analysis.lastModified != null &&
        current.lastModified!.isNotEmpty &&
        analysis.lastModified!.isNotEmpty &&
        current.lastModified != analysis.lastModified) {
      throw Exception(
        'Last-Modified mismatch: Existing file timestamp is "${current.lastModified}", '
        'but new link returned "${analysis.lastModified}".',
      );
    }

    // Verify resume support
    if (current.resumable && !analysis.resumable) {
      throw Exception(
        'Resume unsupported: The new link does not support HTTP Range requests for partial downloads.',
      );
    }

    _tasks[idx] = current.copyWith(
      url: newUrl.trim(),
      etag: analysis.etag ?? current.etag,
      lastModified: analysis.lastModified ?? current.lastModified,
    );

    logEvent(taskId, 'INFO', 'Download URL refreshed: $newUrl');
    await saveImmediate();
    notifyListeners();
  }

  /// Restarts download from scratch (deletes partial file).
  Future<void> reDownload(String taskId) async {
    _networkRetryTimers.remove(taskId)?.cancel();
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx < 0) return;

    final task = _tasks[idx];
    if (task.status.isActive) {
      await cancelDownload(taskId, deleteFile: true);
    } else {
      try {
        final f = File(task.savePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    _tasks[idx] = task.copyWith(
      downloadedBytes: 0,
      status: DownloadStatus.queued,
      speedBytesPerSec: 0.0,
      errorMessage: null,
      clearError: true,
      completedAt: null,
      clearCompletedAt: true,
      elapsedSeconds: 0,
      segments: SegmentPlanner.planInitialSegments(
        totalBytes: task.totalBytes,
        connectionCount: task.connectionCount,
        resumable: task.resumable,
      ),
    );

    _taskSpeedSamples[taskId] = [];
    _taskElapsedSeconds[taskId] = 0;
    logEvent(taskId, 'INFO', 'Restarted download from 0 B');

    await saveImmediate();
    notifyListeners();
    _processQueue();
  }

  /// Pauses all active/queued downloads.
  Future<void> pauseAll() async {
    final active = _tasks
        .where(
          (t) =>
              t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.queued,
        )
        .toList();
    for (final t in active) {
      await pauseDownload(t.id);
    }
  }

  /// Resumes all paused/failed downloads.
  Future<void> resumeAll() async {
    final paused = _tasks
        .where(
          (t) =>
              t.status == DownloadStatus.paused ||
              t.status == DownloadStatus.failed,
        )
        .toList();
    for (final t in paused) {
      await resumeDownload(t.id);
    }
  }

  /// Pauses an active downloading task.
  Future<void> pauseDownload(String id) async {
    _networkRetryTimers.remove(id)?.cancel();
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
      if (ctx.multiDownloader != null) {
        await ctx.multiDownloader!.pause();
      }
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

    logEvent(id, 'INFO', 'Download paused');
    await saveImmediate();
    notifyListeners();
    AnalyticsService.trackDownloadPaused();

    _processQueue();
  }

  /// Resumes a paused or failed task.
  Future<void> resumeDownload(String id) async {
    _networkRetryTimers.remove(id)?.cancel();
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
      clearError: true,
      speedBytesPerSec: 0.0,
    );

    logEvent(id, 'INFO', 'Download queued for resume');
    await saveImmediate();
    notifyListeners();
    AnalyticsService.trackDownloadResumed();

    _processQueue();
  }

  /// Retries a failed or cancelled task.
  Future<void> retryDownload(String id) async {
    AnalyticsService.trackDownloadRetried();
    await resumeDownload(id);
  }

  /// Cancels an active or queued download.
  Future<void> cancelDownload(String id, {bool deleteFile = false}) async {
    _networkRetryTimers.remove(id)?.cancel();
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index < 0) return;

    final task = _tasks[index];
    final ctx = _activeContexts[id];
    if (ctx != null) {
      ctx.isCancelled = true;
      if (ctx.multiDownloader != null) {
        await ctx.multiDownloader!.cancel();
      }
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

    logEvent(id, 'WARN', 'Download cancelled');
    await saveImmediate();
    notifyListeners();
    AnalyticsService.trackDownloadCancelled();

    _processQueue();
  }

  /// Deletes a task from history, optionally deleting the file from storage.
  Future<void> deleteTask(String id, {bool deleteFile = false}) async {
    _networkRetryTimers.remove(id)?.cancel();
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
    _taskLogs.remove(id);
    _taskSpeedSamples.remove(id);
    _taskElapsedSeconds.remove(id);
    _taskNotifiers.remove(id)?.dispose();

    await saveImmediate();
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
      _taskLogs.remove(task.id);
      _taskSpeedSamples.remove(task.id);
      _taskElapsedSeconds.remove(task.id);
    }
    _tasks.removeWhere((t) => t.status.isCompleted);
    await saveImmediate();
    notifyListeners();
  }

  /// Opt-in details stream that emits at 3 Hz (every 333 ms) while open.
  Stream<TaskDetailsUpdate> watchTaskDetails(String taskId) {
    late StreamController<TaskDetailsUpdate> controller;
    Timer? timer;

    void emitLatest() {
      if (controller.isClosed) return;
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx < 0) return;

      final task = _tasks[idx];
      final segments = task.segments.isNotEmpty
          ? task.segments
          : [
              DownloadSegment(
                index: 0,
                startByte: 0,
                endByte: task.totalBytes > 0 ? task.totalBytes - 1 : -1,
                downloadedBytes: task.downloadedBytes,
                isCompleted: task.status.isCompleted,
              ),
            ];
      final samples =
          _taskSpeedSamples[taskId] ??
          (task.speedBytesPerSec > 0 ? [task.speedBytesPerSec] : []);
      final logs = _taskLogs[taskId] ?? [];
      final elapsed = _taskElapsedSeconds[taskId] ?? task.elapsedSeconds;

      controller.add(
        TaskDetailsUpdate(
          task: task.copyWith(
            speedSamples: samples,
            eventLog: logs,
            segments: segments,
            elapsedSeconds: elapsed,
          ),
          segments: segments,
          speedSamples: samples,
          eventLog: logs,
        ),
      );
    }

    controller = StreamController<TaskDetailsUpdate>(
      onListen: () {
        emitLatest();
        timer = Timer.periodic(
          const Duration(milliseconds: 333),
          (_) => emitLatest(),
        );
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  /// Named queue management
  void createQueue(String name) {
    final clean = name.trim();
    if (clean.isNotEmpty && !_namedQueues.contains(clean)) {
      _namedQueues.add(clean);
      _activeQueues[clean] = true;
      notifyListeners();
    }
  }

  void startQueue(String queueName) {
    _activeQueues[queueName] = true;
    final queuedInThisQueue = _tasks
        .where(
          (t) => t.queueName == queueName && t.status == DownloadStatus.paused,
        )
        .toList();
    for (final t in queuedInThisQueue) {
      resumeDownload(t.id);
    }
    notifyListeners();
  }

  void stopQueue(String queueName) {
    _activeQueues[queueName] = false;
    final activeInThisQueue = _tasks
        .where((t) => t.queueName == queueName && t.status.isActive)
        .toList();
    for (final t in activeInThisQueue) {
      pauseDownload(t.id);
    }
    notifyListeners();
  }

  /// Sets automated start/stop schedule for a named queue.
  void setQueueSchedule(QueueSchedule schedule) {
    _queueSchedules[schedule.queueName] = schedule;
    _startSchedulerTimer();
    notifyListeners();
  }

  /// Retrieves automated schedule for a named queue.
  QueueSchedule? getQueueSchedule(String queueName) {
    return _queueSchedules[queueName];
  }

  /// All configured queue schedules.
  Map<String, QueueSchedule> get queueSchedules =>
      Map.unmodifiable(_queueSchedules);

  void _startSchedulerTimer() {
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    final hasActive = _queueSchedules.values.any((s) => s.isEnabled);
    if (!hasActive) return;

    _schedulerTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final now = DateTime.now();
      for (final schedule in _queueSchedules.values) {
        if (!schedule.isEnabled) continue;
        if (now.hour == schedule.startHour &&
            now.minute == schedule.startMinute) {
          startQueue(schedule.queueName);
        } else if (now.hour == schedule.stopHour &&
            now.minute == schedule.stopMinute) {
          stopQueue(schedule.queueName);
        }
      }
    });
  }

  @override
  void dispose() {
    _schedulerTimer?.cancel();
    _saveThrottleTimer?.cancel();
    _aggregateNotifyTimer?.cancel();
    for (final t in _networkRetryTimers.values) {
      t.cancel();
    }
    _networkRetryTimers.clear();
    for (final n in _taskNotifiers.values) {
      n.dispose();
    }
    _taskNotifiers.clear();
    _nativeEventSubscription?.cancel();
    _nativeEventSubscription = null;
    if (_reportedActiveCount > 0) {
      _reportedActiveCount = 0;
      _invokeNative('updateActiveDownloads', {
        'activeCount': 0,
        'progressText': '',
      });
    }
    super.dispose();
  }

  /// Checks queue and starts pending downloads if under max concurrency limit.
  void _processQueue() {
    final downloadingCount = _tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .length;

    final availableSlots =
        NetGetConstants.maxConcurrentDownloads - downloadingCount;
    if (availableSlots <= 0) return;

    final queuedTasks = _tasks
        .where(
          (t) =>
              t.status == DownloadStatus.queued &&
              (_activeQueues[t.queueName] ?? true),
        )
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

    currentTask = currentTask.copyWith(
      status: DownloadStatus.downloading,
      speedBytesPerSec: 0.0,
      errorMessage: null,
      clearError: true,
    );
    _tasks[index] = currentTask;
    logEvent(taskId, 'PROGRESS', 'Connecting to server...');
    notifyListeners();
    AnalyticsService.trackDownloadStarted(
      connectionCount: currentTask.connectionCount,
    );

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

      // Restart / Resume verification:
      // A file may be preallocated on disk to totalBytes with holes.
      // NEVER mark completed or assume done solely based on file.length() >= totalBytes.
      // A task is only completed if its status is already completed, or all segments are verified complete.
      final areSegmentsVerifiedComplete =
          currentTask.segments.isNotEmpty &&
          currentTask.segments.every((s) => s.isFinished && s.isCompleted) &&
          currentTask.downloadedBytes >= currentTask.totalBytes &&
          currentTask.totalBytes > 0;

      if (currentTask.status == DownloadStatus.completed ||
          areSegmentsVerifiedComplete) {
        _tasks[index] = currentTask.copyWith(
          downloadedBytes: currentTask.totalBytes,
          status: DownloadStatus.completed,
          speedBytesPerSec: 0.0,
          completedAt: currentTask.completedAt ?? DateTime.now(),
        );
        logEvent(taskId, 'INFO', 'File already verified complete');
        _activeContexts.remove(taskId);
        client.close(force: true);
        await saveImmediate();
        notifyListeners();
        _processQueue();
        return;
      }

      // If a multi-connection task has preallocated existing bytes on disk but segment metadata
      // is missing, we cannot know which byte ranges are actual data vs unwritten holes.
      // Restart cleanly from byte 0 to guarantee file integrity.
      if (currentTask.connectionCount > 1 &&
          currentTask.segments.isEmpty &&
          existingBytes > 0) {
        logEvent(
          taskId,
          'WARN',
          'Task has preallocated file with missing segment records. Restarting from byte 0.',
        );
        try {
          final raf = await file.open(mode: FileMode.write);
          await raf.truncate(0);
          await raf.close();
        } catch (_) {}
        existingBytes = 0;
        currentTask = currentTask.copyWith(downloadedBytes: 0, segments: []);
        _tasks[index] = currentTask;
      }

      final uri = Uri.parse(currentTask.url);

      // Multi-connection engine path: used when connectionCount > 1 and server supports ranges
      if (currentTask.connectionCount > 1) {
        final multiDownloader = MultiConnectionDownloader(
          id: taskId,
          uri: uri,
          savePath: currentTask.savePath,
          connectionCount: currentTask.connectionCount,
          etag: currentTask.etag,
          lastModified: currentTask.lastModified,
          initialSegments: currentTask.segments,
          clientFactory: () => _createHttpClient(),
          onProgress: (downloaded, total, speed, segs) {
            emitProgressTick(
              taskId,
              downloadedBytes: downloaded,
              totalBytes: total,
              speedBytesPerSec: speed,
              segments: segs,
            );
          },
          onCheckpoint: (segs) async {
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx >= 0) {
              final flushedBytes = segs.fold<int>(
                0,
                (sum, s) => sum + s.downloadedBytes,
              );
              _tasks[idx] = _tasks[idx].copyWith(
                segments: segs,
                downloadedBytes: flushedBytes,
              );
              scheduleThrottledSave();
            }
          },
          onLog: (lvl, msg) {
            logEvent(taskId, lvl, msg);
          },
        );

        ctx.multiDownloader = multiDownloader;

        bool shouldUseMulti = false;
        try {
          final probe = await multiDownloader.probeServer();
          if (ctx.isPaused || ctx.isCancelled) {
            _activeContexts.remove(taskId);
            client.close(force: true);
            return;
          }
          if (probe.isRangeSupported && probe.totalBytes > 256 * 1024) {
            shouldUseMulti = true;
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx >= 0) {
              _tasks[idx] = _tasks[idx].copyWith(
                totalBytes: probe.totalBytes,
                etag: probe.etag ?? _tasks[idx].etag,
                lastModified: probe.lastModified ?? _tasks[idx].lastModified,
                resumable: true,
              );
            }
          }
        } catch (e) {
          if (e is HttpException && e.message.contains('Server file changed')) {
            logEvent(
              taskId,
              'WARN',
              'Server ETag changed after restart: $e. Discarding partial file and restarting from 0.',
            );
            try {
              final raf = await file.open(mode: FileMode.write);
              await raf.truncate(0);
              await raf.close();
            } catch (_) {}
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx >= 0) {
              _tasks[idx] = _tasks[idx].copyWith(
                downloadedBytes: 0,
                etag: null,
                segments: [],
              );
              await saveImmediate();
            }
            _activeContexts.remove(taskId);
            client.close(force: true);
            unawaited(_startDownloading(taskId));
            return;
          }
          logEvent(
            taskId,
            'WARN',
            'Multi-connection probe: $e; falling back to single stream',
          );
        }

        if (shouldUseMulti) {
          try {
            await multiDownloader.start();
            if (ctx.isPaused ||
                ctx.isCancelled ||
                multiDownloader.isPaused ||
                multiDownloader.isCancelled) {
              _activeContexts.remove(taskId);
              client.close(force: true);
              return;
            }

            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx >= 0 && _tasks[idx].status == DownloadStatus.downloading) {
              _tasks[idx] = _tasks[idx].copyWith(
                status: DownloadStatus.completed,
                downloadedBytes: multiDownloader.totalBytes > 0
                    ? multiDownloader.totalBytes
                    : _tasks[idx].downloadedBytes,
                totalBytes: multiDownloader.totalBytes > 0
                    ? multiDownloader.totalBytes
                    : _tasks[idx].totalBytes,
                speedBytesPerSec: 0.0,
                completedAt: DateTime.now(),
                segments: multiDownloader.segments,
              );
              logEvent(taskId, 'INFO', 'Download completed successfully!');
              final completedTask = _tasks[idx];
              final durationSec = completedTask.completedAt != null
                  ? completedTask.completedAt!
                        .difference(completedTask.createdAt)
                        .inSeconds
                  : 0;
              final avgSpeed = durationSec > 0
                  ? (completedTask.downloadedBytes / durationSec).round()
                  : 0;
              AnalyticsService.trackDownloadCompleted(
                totalBytes: completedTask.downloadedBytes,
                durationSeconds: durationSec,
                avgSpeedBytesPerSec: avgSpeed,
                category: completedTask.category.name,
              );
              await saveImmediate();
              notifyListeners();
              unawaited(
                _invokeNative('notifyDownloadCompleted', {
                  'taskId': taskId,
                  'fileName': _tasks[idx].fileName,
                  'savePath': _tasks[idx].savePath,
                }),
              );
            }
            _activeContexts.remove(taskId);
            client.close(force: true);
            _processQueue();
            return;
          } catch (e) {
            if (ctx.isPaused || ctx.isCancelled) {
              _activeContexts.remove(taskId);
              client.close(force: true);
              return;
            }
            if (e is DiskSpaceException ||
                (e is FileSystemException &&
                    (e.message.contains('Insufficient disk space') ||
                        e.osError?.errorCode == 28 ||
                        e.message.toLowerCase().contains('no space')))) {
              final idx = _tasks.indexWhere((t) => t.id == taskId);
              if (idx >= 0) {
                _tasks[idx] = _tasks[idx].copyWith(
                  status: DownloadStatus.failed,
                  errorMessage:
                      'Disk is full. Please free up storage space to resume download.',
                  speedBytesPerSec: 0.0,
                );
                logEvent(taskId, 'ERROR', 'Disk full: $e');
                AnalyticsService.trackDownloadFailed(errorType: 'storage_full');
                await saveImmediate();
                notifyListeners();
              }
              _activeContexts.remove(taskId);
              client.close(force: true);
              _processQueue();
              return;
            }
            if (e is HttpException &&
                e.message.contains('Server file changed')) {
              logEvent(
                taskId,
                'WARN',
                'Server ETag changed mid-download: $e. Discarding partial file and restarting from 0.',
              );
              try {
                final raf = await file.open(mode: FileMode.write);
                await raf.truncate(0);
                await raf.close();
              } catch (_) {}
              final idx = _tasks.indexWhere((t) => t.id == taskId);
              if (idx >= 0) {
                _tasks[idx] = _tasks[idx].copyWith(
                  downloadedBytes: 0,
                  etag: null,
                  segments: [],
                );
                await saveImmediate();
              }
              _activeContexts.remove(taskId);
              client.close(force: true);
              unawaited(_startDownloading(taskId));
              return;
            }
            logEvent(
              taskId,
              'WARN',
              'Multi-connection download failed: $e; falling back to single stream',
            );
          }
        }
      }

      // Single stream fallback for multi-connection tasks:
      // If the file was preallocated with holes, single-stream cannot safely append to existingBytes.
      if (currentTask.connectionCount > 1 && existingBytes > 0) {
        logEvent(
          taskId,
          'WARN',
          'Single stream fallback for multi-connection task requires fresh restart from byte 0.',
        );
        try {
          final raf = await file.open(mode: FileMode.write);
          await raf.truncate(0);
          await raf.close();
        } catch (_) {}
        existingBytes = 0;
      }

      final request = await client.getUrl(uri);
      ctx.request = request;

      request.headers.set(
        HttpHeaders.userAgentHeader,
        NetGetConstants.userAgent,
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (currentTask.referrer != null) {
        request.headers.set(HttpHeaders.refererHeader, currentTask.referrer!);
      }

      final shouldRange = existingBytes > 0 && currentTask.resumable;
      if (shouldRange) {
        String? ifRangeValidator;
        if (NetGetUtils.isStrongEtag(currentTask.etag)) {
          ifRangeValidator = currentTask.etag;
        } else if (currentTask.lastModified != null &&
            currentTask.lastModified!.trim().isNotEmpty) {
          ifRangeValidator = currentTask.lastModified;
        }

        if (ifRangeValidator != null) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
          request.headers.set(HttpHeaders.ifRangeHeader, ifRangeValidator);
        } else {
          existingBytes = 0;
          try {
            final raf = await file.open(mode: FileMode.write);
            await raf.truncate(0);
            await raf.close();
          } catch (_) {}
        }
      }

      final response = await request.close();

      if (ctx.isPaused || ctx.isCancelled) {
        client.close(force: true);
        return;
      }

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
        final contentRange = response.headers.value(
          HttpHeaders.contentRangeHeader,
        );
        if (contentRange != null && contentRange.startsWith('bytes ')) {
          final rangePart = contentRange.substring(6).split('/')[0].trim();
          final rangeParts = rangePart.split('-');
          if (rangeParts.isNotEmpty) {
            final actualStart = int.tryParse(rangeParts[0]);
            if (actualStart != null && actualStart != existingBytes) {
              await response.drain<void>();
              throw HttpException(
                'Server returned unexpected Content-Range start: $actualStart != requested $existingBytes',
                uri: uri,
              );
            }
          }
        }
        isAppend = true;
        resumable = true;
        final len = response.contentLength;
        if (len > 0) {
          totalBytes = existingBytes + len;
        }
        logEvent(
          taskId,
          'INFO',
          'Resuming from offset ${NetGetUtils.formatBytes(existingBytes)}',
        );
      } else if (statusCode == HttpStatus.ok) {
        isAppend = false;
        existingBytes = 0;
        final acceptRanges = response.headers.value(
          HttpHeaders.acceptRangesHeader,
        );
        resumable = acceptRanges?.toLowerCase() == 'bytes';
        totalBytes = response.contentLength;
        logEvent(
          taskId,
          'INFO',
          'Server returned 200 OK (total: ${NetGetUtils.formatBytes(totalBytes)})',
        );
      }

      final contentDisposition = response.headers.value('content-disposition');
      String updatedFileName = currentTask.fileName;
      if (contentDisposition != null) {
        final parsedName = NetGetUtils.parseContentDisposition(
          contentDisposition,
        );
        if (parsedName != null && parsedName.isNotEmpty) {
          updatedFileName = NetGetUtils.sanitizeFileName(parsedName);
        }
      }

      final newEtag =
          response.headers.value(HttpHeaders.etagHeader) ?? currentTask.etag;
      final newLastModified =
          response.headers.value(HttpHeaders.lastModifiedHeader) ??
          currentTask.lastModified;

      // Update segment tracking
      var segments = currentTask.segments;
      if (segments.isEmpty || segments.first.endByte < 0) {
        segments = SegmentPlanner.planInitialSegments(
          totalBytes: totalBytes,
          connectionCount: currentTask.connectionCount,
          resumable: resumable,
        );
      }

      var downloadedBytes = existingBytes;

      _tasks[index] = currentTask.copyWith(
        fileName: updatedFileName,
        totalBytes: totalBytes,
        downloadedBytes: downloadedBytes,
        resumable: resumable,
        etag: newEtag,
        lastModified: newLastModified,
        segments: segments,
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

          // Update active segment
          if (segments.isNotEmpty) {
            segments[0] = segments.first.copyWith(
              downloadedBytes: downloadedBytes,
            );
          }

          final now = DateTime.now();
          final elapsedMs = now.difference(lastEmitTime).inMilliseconds;
          if (elapsedMs >= 250) {
            final elapsedSec = stopwatch.elapsedMicroseconds / 1000000.0;
            final speed = elapsedSec > 0
                ? (bytesSinceLastTick / elapsedSec)
                : 0.0;

            stopwatch.reset();
            bytesSinceLastTick = 0;
            lastEmitTime = now;

            emitProgressTick(
              taskId,
              downloadedBytes: downloadedBytes,
              speedBytesPerSec: speed,
              segments: segments,
            );
          }
        },
        onError: (Object error) async {
          await sink.flush();
          await sink.close();
          client?.close(force: true);
          _activeContexts.remove(taskId);

          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx >= 0) {
            final t = _tasks[idx];
            if (!t.status.isPaused && !t.status.isCancelled) {
              final failureCode = DownloadFailureMapper.mapException(error);
              final cleanMsg = failureCode.localizedMessage();
              _tasks[idx] = t.copyWith(
                status: DownloadStatus.failed,
                errorMessage: cleanMsg,
                speedBytesPerSec: 0.0,
                downloadedBytes: downloadedBytes,
              );
              logEvent(taskId, 'ERROR', 'Error ($failureCode): $error');
              AnalyticsService.trackDownloadFailed(
                errorType: failureCode.name,
                httpStatus: failureCode == DownloadFailureCode.http403
                    ? 403
                    : (failureCode == DownloadFailureCode.http404 ? 404 : null),
              );
              await saveImmediate();
              notifyListeners();
              unawaited(
                _invokeNative('notifyDownloadFailed', {
                  'taskId': taskId,
                  'fileName': _tasks[idx].fileName,
                  'errorMessage': cleanMsg,
                }),
              );
              if (failureCode == DownloadFailureCode.noConnection) {
                _scheduleNetworkRetry(taskId);
              }
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
              if (segments.isNotEmpty) {
                segments[0] = segments.first.copyWith(isCompleted: true);
              }
              _tasks[idx] = t.copyWith(
                status: DownloadStatus.completed,
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes > 0 ? totalBytes : downloadedBytes,
                speedBytesPerSec: 0.0,
                completedAt: DateTime.now(),
                segments: segments,
              );
              logEvent(taskId, 'INFO', 'Download completed successfully!');
              final completedTask = _tasks[idx];
              final durationSec = completedTask.completedAt != null
                  ? completedTask.completedAt!
                        .difference(completedTask.createdAt)
                        .inSeconds
                  : 0;
              final avgSpeed = durationSec > 0
                  ? (completedTask.downloadedBytes / durationSec).round()
                  : 0;
              AnalyticsService.trackDownloadCompleted(
                totalBytes: completedTask.downloadedBytes,
                durationSeconds: durationSec,
                avgSpeedBytesPerSec: avgSpeed,
                category: completedTask.category.name,
              );
              await saveImmediate();
              notifyListeners();
              unawaited(
                _invokeNative('notifyDownloadCompleted', {
                  'taskId': taskId,
                  'fileName': _tasks[idx].fileName,
                  'savePath': _tasks[idx].savePath,
                }),
              );
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
          final failureCode = DownloadFailureMapper.mapException(e);
          final cleanMsg = failureCode.localizedMessage();
          _tasks[idx] = t.copyWith(
            status: DownloadStatus.failed,
            errorMessage: cleanMsg,
            speedBytesPerSec: 0.0,
          );
          logEvent(taskId, 'ERROR', 'Failure ($failureCode): $e');
          AnalyticsService.trackDownloadFailed(
            errorType: failureCode.name,
            httpStatus: failureCode == DownloadFailureCode.http403
                ? 403
                : (failureCode == DownloadFailureCode.http404 ? 404 : null),
          );
          await saveImmediate();
          notifyListeners();
          unawaited(
            _invokeNative('notifyDownloadFailed', {
              'taskId': taskId,
              'fileName': _tasks[idx].fileName,
              'errorMessage': cleanMsg,
            }),
          );
          if (failureCode == DownloadFailureCode.noConnection) {
            _scheduleNetworkRetry(taskId);
          }
        }
      }
      _processQueue();
    }
  }

  void _scheduleNetworkRetry(String taskId) {
    _networkRetryTimers[taskId]?.cancel();
    _networkRetryTimers[taskId] = Timer(const Duration(seconds: 5), () {
      _networkRetryTimers.remove(taskId);
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx >= 0 && _tasks[idx].status == DownloadStatus.failed) {
        logEvent(taskId, 'INFO', 'Automatic network retry triggered');
        retryDownload(taskId);
      }
    });
  }

  String cleanErrorMessageForTesting(dynamic error) =>
      _cleanErrorMessage(error);

  void setTaskFailureForTesting(String taskId, String error) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx >= 0) {
      _tasks[idx] = _tasks[idx].copyWith(
        status: DownloadStatus.failed,
        errorMessage: error,
        speedBytesPerSec: 0.0,
      );
      saveImmediate();
      notifyListeners();
    }
  }

  String _cleanErrorMessage(dynamic error) {
    return DownloadFailureMapper.cleanErrorMessage(error);
  }

  Future<String> _resolveUniqueFilePath(String dirPath, String fileName) async {
    var candidate = p.join(dirPath, fileName);
    if (!await File(candidate).exists()) {
      return candidate;
    }

    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex > 0 ? fileName.substring(dotIndex) : '';

    var counter = 1;
    while (await File(p.join(dirPath, '$base($counter)$ext')).exists()) {
      counter++;
    }
    return p.join(dirPath, '$base($counter)$ext');
  }
}
