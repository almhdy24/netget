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
import '../data/task_store.dart';
import '../models/app_settings.dart';
import '../models/data_budget.dart';
import '../models/download_status.dart';
import '../models/download_task.dart';
import 'analytics_service.dart';
import 'data_budget_service.dart';
import 'multi_connection_downloader.dart';
import 'storage_service.dart';

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
  final StorageService _storageService;
  final DataBudgetService _budgetService;
  AppSettings _settings;
  final bool autoResumeInterrupted;

  late final TaskStore _store;
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
  final Map<String, DateTime> _taskStartTimes = {};
  final Map<String, int> _taskBaseElapsedSeconds = {};
  final Map<String, QueueSchedule> _queueSchedules = {};
  Timer? _schedulerTimer;
  Timer? _budgetTimer;
  String _cachedNetworkType = 'wifi';
  DateTime _lastNetworkTypeCheck = DateTime.fromMillisecondsSinceEpoch(0);
  SpeedMode _speedMode = SpeedMode.unlimited;
  final List<String> _namedQueues = [NetGetConstants.defaultQueueName];
  final Map<String, bool> _activeQueues = {
    NetGetConstants.defaultQueueName: true,
  };
  final Map<String, Timer> _networkRetryTimers = {};

  /// Retrieves a task-specific ValueNotifier without mutating state in build or creating placeholder tasks.
  ValueNotifier<DownloadTask>? getTaskNotifier(String taskId) =>
      _store.getNotifier(taskId);

  @visibleForTesting
  void updateTaskForTesting(DownloadTask task) {
    _store.update(task.id, (_) => task, notifyAggregate: true);
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
    final task = _store.getById(taskId);
    if (task != null && task.status == DownloadStatus.downloading) {
      final samples = _taskSpeedSamples.putIfAbsent(taskId, () => []);
      samples.add(speedBytesPerSec);
      if (samples.length > 60) samples.removeAt(0);

      final startTime = _taskStartTimes.putIfAbsent(taskId, clock);
      final sessionElapsed = clock().difference(startTime).inSeconds;
      final currentElapsed =
          (_taskBaseElapsedSeconds[taskId] ?? task.elapsedSeconds) +
          sessionElapsed;

      final prevDownloaded = task.downloadedBytes;
      final deltaBytes = downloadedBytes - prevDownloaded;
      if (deltaBytes > 0) {
        _recordUsageAsync(taskId, deltaBytes);
      }

      final updated = _store.update(
        taskId,
        (t) => t.copyWith(
          downloadedBytes: downloadedBytes,
          totalBytes: (totalBytes != null && totalBytes > 0)
              ? totalBytes
              : t.totalBytes,
          speedBytesPerSec: speedBytesPerSec,
          elapsedSeconds: currentElapsed,
          segments: segments ?? t.segments,
        ),
        notifyAggregate: true,
      );
      if (updated != null) {
        _syncActiveDownloadsToNative();
      }
    }
  }

  final Set<String> _startingTasks = {};

  Future<void> _recordUsageAsync(String taskId, int deltaBytes) async {
    try {
      final now = clock();
      if (now.difference(_lastNetworkTypeCheck).inSeconds > 2) {
        _cachedNetworkType = await _budgetService.getNetworkType();
        _lastNetworkTypeCheck = now;
      }
      final isFree = _budgetService.isFreeWindow(
        freeWindows: _settings.freeWindows,
        now: now,
      );
      final netType = _cachedNetworkType == 'wifi'
          ? 'wifi'
          : (isFree ? 'free_mobile' : 'mobile');

      await _budgetService.recordUsage(
        taskId: taskId,
        bytes: deltaBytes,
        networkType: netType,
        timestamp: now,
      );
    } catch (e, st) {
      debugPrint('recordUsageAsync error: $e\n$st');
    }
  }

  /// Default connections setting from AppSettings.
  int get defaultConnections => _settings.connectionsPerDownload;
  set defaultConnections(int val) {
    _settings = _settings.copyWith(connectionsPerDownload: val);
  }

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

    final downloadingTasks = tasks
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

  bool _isDisposed = false;

  /// Throttled save: max 1 save per second across progress ticks.
  void scheduleThrottledSave() {
    if (_isDisposed) return;
    final now = clock();
    final elapsedMs = now.difference(_lastSaveTime).inMilliseconds;
    if (elapsedMs >= 1000) {
      _saveThrottleTimer?.cancel();
      _saveThrottleTimer = null;
      _hasPendingSave = false;
      _lastSaveTime = now;
      _repository.saveTasks(_store.tasks);
    } else {
      _hasPendingSave = true;
      if (_saveThrottleTimer == null || !_saveThrottleTimer!.isActive) {
        final waitMs = 1000 - elapsedMs;
        _saveThrottleTimer = Timer(Duration(milliseconds: waitMs), () {
          if (_hasPendingSave && !_isDisposed) {
            _hasPendingSave = false;
            _lastSaveTime = clock();
            _repository.saveTasks(_store.tasks);
          }
        });
      }
    }
  }

  /// Immediate save for lifecycle state transitions (pause, cancel, complete, delete, add).
  Future<void> saveImmediate() async {
    if (_isDisposed) return;
    _saveThrottleTimer?.cancel();
    _saveThrottleTimer = null;
    _hasPendingSave = false;
    _lastSaveTime = clock();
    await _repository.saveTasks(_store.tasks);
  }

  DownloadManager({
    required DownloadRepository repository,
    HttpClient Function()? clientFactory,
    Future<Directory> Function()? downloadsDirResolver,
    StorageService? storageService,
    DataBudgetService? budgetService,
    AppSettings settings = const AppSettings(),
    this.autoResumeInterrupted = true,
  }) : _repository = repository,
       _clientFactory = clientFactory,
       _downloadsDirResolver = downloadsDirResolver,
       _storageService = storageService ?? StorageService.instance,
       _budgetService = budgetService ?? DataBudgetService(),
       _settings = settings {
    _speedMode = settings.speedMode;
    _store = TaskStore(
      onTasksChanged: () {
        if (!_isDisposed) notifyListeners();
      },
      onTaskPersist: (task) {
        if (!_isDisposed) _repository.saveTask(task);
      },
      onScheduleSave: (tasks) {
        if (!_isDisposed) scheduleThrottledSave();
      },
    );
  }

  AppSettings get settings => _settings;
  DataBudgetService get budgetService => _budgetService;

  /// Updates runtime settings, adjusting speed limits, concurrency, and evaluating data budget rules.
  void updateSettings(AppSettings newSettings) {
    _settings = newSettings;
    if (_speedMode != newSettings.speedMode) {
      setSpeedMode(newSettings.speedMode);
    }
    evaluatePolicyAndWindows();
    notifyListeners();
  }

  List<DownloadTask> get tasks => _store.tasks;

  List<DownloadTask> get activeTasks =>
      tasks.where((t) => t.status.isActive).toList();

  List<DownloadTask> get pausedTasks =>
      tasks.where((t) => t.status.isPaused).toList();

  List<DownloadTask> get completedTasks =>
      tasks.where((t) => t.status.isCompleted).toList();

  List<DownloadTask> get failedTasks =>
      tasks.where((t) => t.status.isFailed).toList();

  int get totalDownloadedBytes =>
      tasks.fold<int>(0, (sum, task) => sum + task.downloadedBytes);

  double get currentTotalSpeed => tasks
      .where((t) => t.status == DownloadStatus.downloading)
      .fold<double>(0.0, (sum, task) => sum + task.speedBytesPerSec);

  int get queuedCount =>
      tasks.where((t) => t.status == DownloadStatus.queued).length;

  int get completedTodayCount {
    final now = DateTime.now();
    return tasks.where((t) {
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
    for (final ctx in _activeContexts.values) {
      ctx.multiDownloader?.tokenBucket?.updateRate(mode.bytesPerSec);
    }
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
      return _store.tasks.firstWhere((t) => t.url.trim() == clean);
    } catch (_) {
      return null;
    }
  }

  /// Initializes the manager and loads existing persisted tasks.
  Future<void> init({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) return;
    final loaded = await _repository.loadTasks();
    _store.init(loaded);
    _isInitialized = true;
    _startSchedulerTimer();
    _startBudgetTimer();
    _initNativeBridge();
    notifyListeners();
  }

  /// Automatically re-queues and resumes tasks that were interrupted (in downloading state when process terminated).
  Future<void> resumeInterruptedTasks() async {
    final interrupted = tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .toList();
    for (final task in interrupted) {
      _store.update(
        task.id,
        (t) => t.copyWith(status: DownloadStatus.queued, speedBytesPerSec: 0.0),
        notifyAggregate: true,
      );
      await resumeDownload(task.id);
    }
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
            if (event['event'] == 'networkChanged') {
              evaluatePolicyAndWindows();
              return;
            }
            final taskId = event['taskId'] as String?;
            final downloaded = (event['downloadedBytes'] as num?)?.toInt();
            final speed = (event['speedBytesPerSec'] as num?)?.toDouble();
            if (taskId != null) {
              _store.update(
                taskId,
                (t) => t.copyWith(
                  downloadedBytes: downloaded ?? t.downloadedBytes,
                  speedBytesPerSec: speed ?? t.speedBytesPerSec,
                ),
                notifyAggregate: true,
              );
            }
          }
        }, onError: (_) {});
      } catch (_) {}
    }
  }

  /// Evaluates active and paused tasks against data budget and network policies.
  /// Auto-pauses tasks that are no longer allowed (e.g. WiFi-only on cellular or outside free window),
  /// and auto-resumes tasks that were paused by budget/network when conditions are met.
  Future<void> evaluatePolicyAndWindows() async {
    final netType = await _budgetService.getNetworkType();
    _cachedNetworkType = netType;
    _lastNetworkTypeCheck = clock();
    final isWifi = netType == 'wifi';
    final now = clock();

    final downloading = tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .toList();
    for (final task in downloading) {
      final check = await _budgetService.checkAllowed(
        policy: task.networkPolicy,
        settings: _settings,
        isWifiOverride: isWifi,
        now: now,
      );
      if (!check.isAllowed) {
        await pauseDownload(task.id, reason: check.pauseReason);
      }
    }

    final pausedForBudget = tasks
        .where(
          (t) =>
              t.status == DownloadStatus.paused &&
              (t.pauseReason == 'network' || t.pauseReason == 'budget'),
        )
        .toList();
    for (final task in pausedForBudget) {
      final check = await _budgetService.checkAllowed(
        policy: task.networkPolicy,
        settings: _settings,
        isWifiOverride: isWifi,
        now: now,
      );
      if (check.isAllowed) {
        await resumeDownload(task.id);
      }
    }

    _processQueue();
  }

  void _startBudgetTimer() {
    _budgetTimer?.cancel();
    _budgetTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      evaluatePolicyAndWindows();
    });
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
    NetworkPolicy? networkPolicy,
    List<String>? mirrors,
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
        'task_${DateTime.now().millisecondsSinceEpoch}_${_store.length + 1}';
    final rawName = (customFileName != null && customFileName.trim().isNotEmpty)
        ? customFileName.trim()
        : NetGetUtils.extractFileNameFromUrl(cleanUrl);
    final fileName = NetGetUtils.sanitizeFileName(rawName);

    final resolvedCategory = category ?? NetGetUtils.classifyCategory(fileName);

    final String savePath;
    if (_downloadsDirResolver != null) {
      final downloadsDir = await _downloadsDirResolver();
      savePath = await _resolveUniqueFilePath(downloadsDir.path, fileName);
    } else {
      savePath = await _storageService.getPartFilePath(id);
    }

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
      networkPolicy: networkPolicy ?? _settings.defaultNetworkPolicy,
      mirrors: mirrors ?? const [],
    );

    logEvent(id, 'INFO', 'Download added: $fileName');
    if (!startNow) {
      logEvent(id, 'INFO', 'Download marked for later');
    }

    _store.add(task);
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
  /// If file metadata mismatches and [forceRestartIfMismatch] is true, resets progress to byte 0.
  Future<void> refreshTaskUrl(
    String taskId,
    String newUrl, {
    bool forceRestartIfMismatch = false,
  }) async {
    final current = _store.getById(taskId);
    if (current == null) {
      throw Exception('Task not found');
    }
    final analysis = await analyzeUrl(newUrl);

    final sizeMismatch =
        current.totalBytes > 0 &&
        analysis.totalBytes > 0 &&
        current.totalBytes != analysis.totalBytes;

    final etagMismatch =
        current.etag != null &&
        analysis.etag != null &&
        current.etag!.isNotEmpty &&
        analysis.etag!.isNotEmpty &&
        current.etag != analysis.etag;

    if (sizeMismatch || etagMismatch) {
      if (!forceRestartIfMismatch) {
        if (sizeMismatch) {
          throw Exception(
            'Size mismatch: Existing file is ${NetGetUtils.formatBytes(current.totalBytes)}, '
            'but new link is ${NetGetUtils.formatBytes(analysis.totalBytes)}.',
          );
        } else {
          throw Exception(
            'ETag mismatch: Existing file ETag is "${current.etag}", but new link returned "${analysis.etag}". '
            'The remote file has changed and cannot be safely resumed.',
          );
        }
      }
      try {
        final f = File(current.savePath);
        if (await f.exists()) {
          final raf = await f.open(mode: FileMode.write);
          await raf.truncate(0);
          await raf.close();
        }
      } catch (_) {}
      _store.update(
        taskId,
        (t) => t.copyWith(
          url: newUrl.trim(),
          totalBytes: analysis.totalBytes > 0
              ? analysis.totalBytes
              : t.totalBytes,
          downloadedBytes: 0,
          segments: [],
          etag: analysis.etag,
          lastModified: analysis.lastModified,
          clearPauseReason: true,
          clearError: true,
          status: DownloadStatus.queued,
        ),
        notifyAggregate: true,
      );
    } else {
      // Strict Last-Modified check if provided by both
      if (current.lastModified != null &&
          analysis.lastModified != null &&
          current.lastModified!.isNotEmpty &&
          analysis.lastModified!.isNotEmpty &&
          current.lastModified != analysis.lastModified) {
        if (!forceRestartIfMismatch) {
          throw Exception(
            'Last-Modified mismatch: Existing file timestamp is "${current.lastModified}", '
            'but new link returned "${analysis.lastModified}".',
          );
        }
      }

      // Verify resume support
      if (current.resumable && !analysis.resumable && !forceRestartIfMismatch) {
        throw Exception(
          'Resume unsupported: The new link does not support HTTP Range requests for partial downloads.',
        );
      }

      _store.update(
        taskId,
        (t) => t.copyWith(
          url: newUrl.trim(),
          totalBytes: analysis.totalBytes > 0
              ? analysis.totalBytes
              : t.totalBytes,
          etag: analysis.etag ?? t.etag,
          lastModified: analysis.lastModified ?? t.lastModified,
          clearPauseReason: true,
          clearError: true,
          status: DownloadStatus.queued,
        ),
        notifyAggregate: true,
      );
    }

    logEvent(taskId, 'INFO', 'Download URL refreshed: $newUrl');
    await saveImmediate();
    _processQueue();
  }

  /// Adds a mirror URL to an existing task.
  Future<void> addMirror(String taskId, String mirrorUrl) async {
    final clean = mirrorUrl.trim();
    if (clean.isEmpty) return;
    final current = _store.getById(taskId);
    if (current == null) return;
    if (current.mirrors.contains(clean) || current.url == clean) return;
    final updatedMirrors = List<String>.from(current.mirrors)..add(clean);
    _store.update(
      taskId,
      (t) => t.copyWith(mirrors: updatedMirrors),
      notifyAggregate: true,
    );
    logEvent(taskId, 'INFO', 'Added mirror: $clean');
    await saveImmediate();
  }

  /// Removes a mirror URL from an existing task.
  Future<void> removeMirror(String taskId, String mirrorUrl) async {
    final current = _store.getById(taskId);
    if (current == null) return;
    final clean = mirrorUrl.trim();
    final updatedMirrors = List<String>.from(current.mirrors)..remove(clean);
    _store.update(
      taskId,
      (t) => t.copyWith(mirrors: updatedMirrors),
      notifyAggregate: true,
    );
    logEvent(taskId, 'INFO', 'Removed mirror: $clean');
    await saveImmediate();
  }

  /// Probes candidate mirrors and returns the first one matching the task's properties.
  Future<String?> _findWorkingMirror(DownloadTask task) async {
    if (task.mirrors.isEmpty) return null;
    for (final mirror in task.mirrors) {
      final cleanMirror = mirror.trim();
      if (cleanMirror.isEmpty || cleanMirror == task.url.trim()) continue;
      try {
        final analysis = await analyzeUrl(cleanMirror);
        // Verify size match if existing task has known totalBytes
        if (task.totalBytes > 0 && analysis.totalBytes > 0) {
          if (task.totalBytes == analysis.totalBytes) {
            return cleanMirror;
          }
        } else if (task.etag != null &&
            analysis.etag != null &&
            task.etag!.isNotEmpty &&
            analysis.etag!.isNotEmpty) {
          if (task.etag == analysis.etag) {
            return cleanMirror;
          }
        } else if (analysis.totalBytes > 0 || analysis.resumable) {
          return cleanMirror;
        }
      } catch (e) {
        logEvent(task.id, 'WARN', 'Mirror probe failed for $cleanMirror: $e');
      }
    }
    return null;
  }

  /// Opens a URL in external web browser.
  Future<void> openInBrowser(String url) async {
    final clean = url.trim();
    if (clean.isEmpty) return;
    await _invokeNative('openBrowser', {'url': clean});
  }

  /// Restarts download from scratch (deletes partial file).
  Future<void> reDownload(String taskId) async {
    _networkRetryTimers.remove(taskId)?.cancel();
    final task = _store.getById(taskId);
    if (task == null) return;

    if (task.status.isActive) {
      await cancelDownload(taskId, deleteFile: true);
    } else {
      try {
        final f = File(task.savePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }

    _store.update(
      taskId,
      (t) => t.copyWith(
        downloadedBytes: 0,
        status: DownloadStatus.queued,
        speedBytesPerSec: 0.0,
        clearError: true,
        clearCompletedAt: true,
        elapsedSeconds: 0,
        segments: SegmentPlanner.planInitialSegments(
          totalBytes: t.totalBytes,
          connectionCount: t.connectionCount,
          resumable: t.resumable,
        ),
      ),
      notifyAggregate: true,
    );

    _taskStartTimes.remove(taskId);
    _taskBaseElapsedSeconds.remove(taskId);
    _taskSpeedSamples[taskId] = [];
    logEvent(taskId, 'INFO', 'Restarted download from 0 B');

    await saveImmediate();
    _processQueue();
  }

  /// Pauses all active/queued downloads.
  Future<void> pauseAll() async {
    final active = tasks
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
    final paused = tasks
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
  Future<void> pauseDownload(String id, {String? reason}) async {
    _networkRetryTimers.remove(id)?.cancel();
    final task = _store.getById(id);
    if (task == null) return;

    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.queued &&
        task.status != DownloadStatus.paused) {
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

    _taskBaseElapsedSeconds[id] = task.elapsedSeconds;
    _taskStartTimes.remove(id);

    _store.update(
      id,
      (t) => t.copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSec: 0.0,
        pauseReason: reason,
        clearPauseReason: reason == null,
      ),
      notifyAggregate: true,
    );

    logEvent(
      id,
      'INFO',
      reason != null ? 'Download paused ($reason)' : 'Download paused',
    );
    await saveImmediate();
    AnalyticsService.trackDownloadPaused();

    _processQueue();
  }

  /// Resumes a paused or failed task.
  Future<void> resumeDownload(String id) async {
    _networkRetryTimers.remove(id)?.cancel();
    final task = _store.getById(id);
    if (task == null) return;

    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return;
    }

    _taskBaseElapsedSeconds[id] = task.elapsedSeconds;
    _taskStartTimes.remove(id);

    _store.update(
      id,
      (t) => t.copyWith(
        status: DownloadStatus.queued,
        clearError: true,
        clearPauseReason: true,
        speedBytesPerSec: 0.0,
      ),
      notifyAggregate: true,
    );

    logEvent(id, 'INFO', 'Download queued for resume');
    await saveImmediate();
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
    final task = _store.getById(id);
    if (task == null) return;

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

    _taskStartTimes.remove(id);
    _taskBaseElapsedSeconds.remove(id);

    _store.update(
      id,
      (t) => t.copyWith(
        status: DownloadStatus.cancelled,
        speedBytesPerSec: 0.0,
        downloadedBytes: deleteFile ? 0 : t.downloadedBytes,
      ),
      notifyAggregate: true,
    );

    logEvent(id, 'WARN', 'Download cancelled');
    await saveImmediate();
    AnalyticsService.trackDownloadCancelled();

    _processQueue();
  }

  /// Deletes a task from history, optionally deleting the file from storage.
  Future<void> deleteTask(String id, {bool deleteFile = false}) async {
    _networkRetryTimers.remove(id)?.cancel();
    final task = _store.getById(id);
    if (task == null) return;

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

    _store.remove(id);
    _taskLogs.remove(id);
    _taskSpeedSamples.remove(id);
    _taskStartTimes.remove(id);
    _taskBaseElapsedSeconds.remove(id);

    await saveImmediate();
    notifyListeners();
  }

  /// Clears all completed tasks from history.
  Future<void> clearCompleted({bool deleteFiles = false}) async {
    final completed = tasks.where((t) => t.status.isCompleted).toList();
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
      _taskStartTimes.remove(task.id);
      _taskBaseElapsedSeconds.remove(task.id);
    }
    _store.removeWhere((t) => t.status.isCompleted);
    await saveImmediate();
    notifyListeners();
  }

  /// Opt-in details stream that emits at 3 Hz (every 333 ms) while open.
  Stream<TaskDetailsUpdate> watchTaskDetails(String taskId) {
    late StreamController<TaskDetailsUpdate> controller;
    Timer? timer;

    void emitLatest() {
      if (controller.isClosed) return;
      final task = _store.getById(taskId);
      if (task == null) return;
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
      final elapsed = task.elapsedSeconds;

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
    final queuedInThisQueue = tasks
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
    final activeInThisQueue = tasks
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
    _isDisposed = true;
    _schedulerTimer?.cancel();
    _budgetTimer?.cancel();
    _saveThrottleTimer?.cancel();
    for (final t in _networkRetryTimers.values) {
      t.cancel();
    }
    _networkRetryTimers.clear();
    _store.dispose();
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
    final downloadingCount = tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .length;

    final availableSlots = _settings.maxConcurrent - downloadingCount;
    if (availableSlots <= 0) return;

    final queuedTasks = tasks
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
      ..connectionTimeout = NetGetConstants.connectTimeout;
    if (kDebugMode &&
        Platform.environment.containsKey('NETGET_ACCEPT_BAD_CERTS')) {
      // ignore: avoid_print
      print(
        '[SECURITY WARNING] Insecure badCertificateCallback enabled by environment flag',
      );
      client.badCertificateCallback = ((cert, host, port) => true);
    }
    return client;
  }

  Future<void> _startDownloading(String taskId) async {
    if (_startingTasks.contains(taskId)) return;
    _startingTasks.add(taskId);
    try {
      final task = _store.getById(taskId);
      if (task == null || task.status == DownloadStatus.downloading) return;

      final currentTask = _store.update(
        taskId,
        (t) => t.copyWith(
          status: DownloadStatus.downloading,
          speedBytesPerSec: 0.0,
          clearError: true,
        ),
        notifyAggregate: true,
      );
      if (currentTask == null) return;
      logEvent(taskId, 'PROGRESS', 'Connecting to server...');
      AnalyticsService.trackDownloadStarted(
        connectionCount: currentTask.connectionCount,
      );

      final check = await _budgetService.checkAllowed(
        policy: currentTask.networkPolicy,
        settings: _settings,
        now: clock(),
      );

      // Re-check task status after the async checkAllowed await.
      // If the task was cancelled, paused, or deleted during the await, abort start.
      final freshTask = _store.getById(taskId);
      if (freshTask == null || freshTask.status != DownloadStatus.downloading) {
        return;
      }

      if (!check.isAllowed) {
        _store.update(
          taskId,
          (t) => t.copyWith(
            status: DownloadStatus.paused,
            pauseReason: check.pauseReason,
            speedBytesPerSec: 0.0,
          ),
          notifyAggregate: true,
        );
        logEvent(
          taskId,
          'PAUSED',
          'Download paused due to network policy (${check.pauseReason})',
        );
        return;
      }

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
          _store.update(
            taskId,
            (t) => t.copyWith(
              downloadedBytes: t.totalBytes,
              status: DownloadStatus.completed,
              speedBytesPerSec: 0.0,
              completedAt: t.completedAt ?? DateTime.now(),
            ),
            notifyAggregate: true,
          );
          logEvent(taskId, 'INFO', 'File already verified complete');
          _activeContexts.remove(taskId);
          client.close(force: true);
          await saveImmediate();
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
          _store.update(
            taskId,
            (t) => t.copyWith(downloadedBytes: 0, segments: []),
          );
        }

        final uri = Uri.parse(currentTask.url);

        // Unified engine: all downloads route through MultiConnectionDownloader
        final multiDownloader = MultiConnectionDownloader(
          id: taskId,
          uri: uri,
          savePath: currentTask.savePath,
          connectionCount: currentTask.connectionCount,
          speedLimitBytesPerSec: _speedMode.bytesPerSec,
          etag: currentTask.etag,
          lastModified: currentTask.lastModified,
          expectedFileName: currentTask.fileName,
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
            final flushedBytes = segs.fold<int>(
              0,
              (sum, s) => sum + s.downloadedBytes,
            );
            _store.update(
              taskId,
              (t) => t.copyWith(segments: segs, downloadedBytes: flushedBytes),
            );
            scheduleThrottledSave();
          },
          onLog: (lvl, msg) {
            logEvent(taskId, lvl, msg);
          },
        );

        ctx.multiDownloader = multiDownloader;

        await multiDownloader.start();
        if (ctx.isPaused ||
            ctx.isCancelled ||
            multiDownloader.isPaused ||
            multiDownloader.isCancelled) {
          _activeContexts.remove(taskId);
          client.close(force: true);
          return;
        }

        final currentDownloading = _store.getById(taskId);
        if (currentDownloading != null &&
            currentDownloading.status == DownloadStatus.downloading) {
          String finalSavePath = currentDownloading.savePath;

          // If the download was saved to a .part file, finalize it to public location
          if (finalSavePath.endsWith('.part')) {
            try {
              final targetDir = await _storageService
                  .getPublicDownloadDirectory(
                    category: currentDownloading.category,
                  );
              final targetPath = await _storageService.resolveTargetFilePath(
                fileName:
                    multiDownloader.suggestedFileName ??
                    currentDownloading.fileName,
                category: currentDownloading.category,
                customFolderPath: targetDir.path,
              );
              finalSavePath = await _storageService.finalizeDownload(
                partFilePath: currentDownloading.savePath,
                targetFilePath: targetPath,
                expectedBytes: multiDownloader.totalBytes > 0
                    ? multiDownloader.totalBytes
                    : currentDownloading.downloadedBytes,
              );
            } catch (e) {
              logEvent(
                taskId,
                'WARN',
                'Finalization to public directory fallback: $e',
              );
            }
          }

          final updatedFileName =
              multiDownloader.suggestedFileName ?? currentDownloading.fileName;

          final completedTask = _store.update(
            taskId,
            (t) => t.copyWith(
              status: DownloadStatus.completed,
              fileName: updatedFileName,
              savePath: finalSavePath,
              downloadedBytes: multiDownloader.totalBytes > 0
                  ? multiDownloader.totalBytes
                  : t.downloadedBytes,
              totalBytes: multiDownloader.totalBytes > 0
                  ? multiDownloader.totalBytes
                  : t.totalBytes,
              etag: multiDownloader.etag ?? t.etag,
              lastModified: multiDownloader.lastModified ?? t.lastModified,
              resumable: multiDownloader.isRangeSupported,
              speedBytesPerSec: 0.0,
              completedAt: DateTime.now(),
              segments: multiDownloader.segments,
            ),
            notifyAggregate: true,
          )!;
          logEvent(taskId, 'INFO', 'Download completed successfully!');
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
          unawaited(
            _invokeNative('notifyDownloadCompleted', {
              'taskId': taskId,
              'fileName': completedTask.fileName,
              'savePath': completedTask.savePath,
            }),
          );
        }
        _activeContexts.remove(taskId);
        client.close(force: true);
        _processQueue();
        return;
      } catch (e) {
        _activeContexts.remove(taskId);
        client?.close(force: true);

        if (ctx.isPaused || ctx.isCancelled) {
          return;
        }

        if (e is HtmlServedInsteadOfFileException) {
          _store.update(
            taskId,
            (t) => t.copyWith(
              status: DownloadStatus.paused,
              pauseReason: 'html_instead_of_file',
              errorMessage: 'ملف HTML بدلاً من الملف الأصلي — تحقق من الرابط',
              speedBytesPerSec: 0.0,
            ),
            notifyAggregate: true,
          );
          logEvent(
            taskId,
            'WARN',
            'Download paused: HTML page served instead of file ($e)',
          );
          AnalyticsService.trackDownloadFailed(
            errorType: 'html_instead_of_file',
          );
          await saveImmediate();
          _processQueue();
          return;
        }

        if (e is DiskSpaceException ||
            (e is FileSystemException &&
                (e.message.contains('Insufficient disk space') ||
                    e.message.contains('No space left on device') ||
                    e.osError?.errorCode == 28 ||
                    e.message.toLowerCase().contains('no space')))) {
          _store.update(
            taskId,
            (t) => t.copyWith(
              status: DownloadStatus.paused,
              pauseReason: 'storage',
              errorMessage:
                  'Disk is full. Please free up storage space to resume download.',
              speedBytesPerSec: 0.0,
            ),
            notifyAggregate: true,
          );
          logEvent(taskId, 'ERROR', 'Disk full: $e');
          AnalyticsService.trackDownloadFailed(errorType: 'storage_full');
          await saveImmediate();
          _processQueue();
          return;
        }

        // Automatic mirror failover if mirrors are configured for this task
        final currentT = _store.getById(taskId);
        if (currentT != null && currentT.mirrors.isNotEmpty) {
          final workingMirror = await _findWorkingMirror(currentT);
          if (workingMirror != null) {
            final updatedMirrors = List<String>.from(currentT.mirrors)
              ..remove(workingMirror)
              ..add(currentT.url);
            _store.update(
              taskId,
              (t) => t.copyWith(
                url: workingMirror,
                mirrors: updatedMirrors,
                status: DownloadStatus.queued,
                clearError: true,
                clearPauseReason: true,
              ),
              notifyAggregate: true,
            );
            logEvent(
              taskId,
              'INFO',
              'Failover: transparently switched to mirror $workingMirror',
            );
            await saveImmediate();
            _startingTasks.remove(taskId);
            _processQueue();
            return;
          }
        }

        if (e is HttpException &&
            (e.message.contains('401') ||
                e.message.contains('403') ||
                e.message.contains('410'))) {
          _store.update(
            taskId,
            (t) => t.copyWith(
              status: DownloadStatus.paused,
              pauseReason: 'urlExpired',
              errorMessage: 'Link expired. Please refresh the download link.',
              speedBytesPerSec: 0.0,
            ),
            notifyAggregate: true,
          );
          logEvent(taskId, 'WARN', 'Download URL expired: $e');
          AnalyticsService.trackDownloadFailed(
            errorType: 'url_expired',
            httpStatus: e.message.contains('401')
                ? 401
                : (e.message.contains('403') ? 403 : 410),
          );
          await saveImmediate();
          _processQueue();
          return;
        }

        final failedCurrentT = _store.getById(taskId);
        if (failedCurrentT != null &&
            !failedCurrentT.status.isPaused &&
            !failedCurrentT.status.isCancelled) {
          final failureCode = DownloadFailureMapper.mapException(e);
          final cleanMsg = failureCode.localizedMessage();
          final failedTask = _store.update(
            taskId,
            (t) => t.copyWith(
              status: DownloadStatus.failed,
              errorMessage: cleanMsg,
              speedBytesPerSec: 0.0,
            ),
            notifyAggregate: true,
          )!;
          logEvent(taskId, 'ERROR', 'Failure ($failureCode): $e');
          AnalyticsService.trackDownloadFailed(
            errorType: failureCode.name,
            httpStatus: failureCode == DownloadFailureCode.http403
                ? 403
                : (failureCode == DownloadFailureCode.http404 ? 404 : null),
          );
          await saveImmediate();
          unawaited(
            _invokeNative('notifyDownloadFailed', {
              'taskId': taskId,
              'fileName': failedTask.fileName,
              'errorMessage': cleanMsg,
            }),
          );
          if (failureCode == DownloadFailureCode.noConnection) {
            _scheduleNetworkRetry(taskId);
          }
        }
        _processQueue();
      }
    } finally {
      _startingTasks.remove(taskId);
    }
  }

  void _scheduleNetworkRetry(String taskId) {
    _networkRetryTimers[taskId]?.cancel();
    _networkRetryTimers[taskId] = Timer(const Duration(seconds: 5), () {
      _networkRetryTimers.remove(taskId);
      final task = _store.getById(taskId);
      if (task != null && task.status == DownloadStatus.failed) {
        logEvent(taskId, 'INFO', 'Automatic network retry triggered');
        retryDownload(taskId);
      }
    });
  }

  String cleanErrorMessageForTesting(dynamic error) =>
      _cleanErrorMessage(error);

  void setTaskFailureForTesting(String taskId, String error) {
    _store.update(
      taskId,
      (t) => t.copyWith(
        status: DownloadStatus.failed,
        errorMessage: error,
        speedBytesPerSec: 0.0,
      ),
      notifyAggregate: true,
    );
    saveImmediate();
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
