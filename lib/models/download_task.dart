import '../core/constants.dart';
import '../core/segment_planner.dart';
import '../core/utils.dart';
import 'download_status.dart';

/// Represents a single logged event in the download's history ring buffer.
class TaskLogEvent {
  final DateTime timestamp;
  final String level; // INFO, WARN, ERROR, PROGRESS
  final String message;

  const TaskLogEvent({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level,
    'message': message,
  };

  factory TaskLogEvent.fromJson(Map<String, dynamic> json) {
    return TaskLogEvent(
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      level: json['level'] as String? ?? 'INFO',
      message: json['message'] as String? ?? '',
    );
  }
}

/// Represents a single download item tracked by NetGet.
class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final bool resumable;
  final double speedBytesPerSec;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;

  // Desktop-grade & Segmented Download additions
  final DownloadCategory category;
  final int connectionCount;
  final String? etag;
  final String? lastModified;
  final String? referrer;
  final String queueName;
  final List<DownloadSegment> segments;
  final List<double> speedSamples; // 60-sample history for sparkline
  final List<TaskLogEvent> eventLog; // up to 200 events ring buffer
  final int elapsedSeconds;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.totalBytes = -1,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.resumable = true,
    this.speedBytesPerSec = 0.0,
    this.errorMessage,
    required this.createdAt,
    this.completedAt,
    this.category = DownloadCategory.other,
    this.connectionCount = NetGetConstants.defaultConnections,
    this.etag,
    this.lastModified,
    this.referrer,
    this.queueName = NetGetConstants.defaultQueueName,
    this.segments = const [],
    this.speedSamples = const [],
    this.eventLog = const [],
    this.elapsedSeconds = 0,
  });

  /// Progress fraction from 0.0 to 1.0, or null if total size is unknown.
  double? get progress {
    if (totalBytes <= 0) return null;
    final val = downloadedBytes / totalBytes;
    if (val < 0.0) return 0.0;
    if (val > 1.0) return 1.0;
    return val;
  }

  /// Percentage formatted string, e.g. "45.0%" or null if indeterminate.
  String? get progressPercentage {
    final p = progress;
    if (p == null) return null;
    return '${(p * 100).toStringAsFixed(1)}%';
  }

  /// Estimated time remaining in seconds, or null if not calculable.
  int? get etaSeconds {
    if (totalBytes <= 0 || speedBytesPerSec <= 0) return null;
    final remainingBytes = totalBytes - downloadedBytes;
    if (remainingBytes <= 0) return 0;
    return (remainingBytes / speedBytesPerSec).round();
  }

  /// Average download speed in bytes/sec.
  double get averageSpeedBytesPerSec {
    if (elapsedSeconds <= 0 || downloadedBytes <= 0) return speedBytesPerSec;
    return downloadedBytes / elapsedSeconds;
  }

  DownloadTask copyWith({
    String? id,
    String? url,
    String? fileName,
    String? savePath,
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    bool? resumable,
    double? speedBytesPerSec,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? completedAt,
    DownloadCategory? category,
    int? connectionCount,
    String? etag,
    String? lastModified,
    String? referrer,
    String? queueName,
    List<DownloadSegment>? segments,
    List<double>? speedSamples,
    List<TaskLogEvent>? eventLog,
    int? elapsedSeconds,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      savePath: savePath ?? this.savePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      resumable: resumable ?? this.resumable,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      category: category ?? this.category,
      connectionCount: connectionCount ?? this.connectionCount,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      referrer: referrer ?? this.referrer,
      queueName: queueName ?? this.queueName,
      segments: segments ?? this.segments,
      speedSamples: speedSamples ?? this.speedSamples,
      eventLog: eventLog ?? this.eventLog,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'fileName': fileName,
      'savePath': savePath,
      'totalBytes': totalBytes,
      'downloadedBytes': downloadedBytes,
      'status': status.name,
      'resumable': resumable,
      'speedBytesPerSec': speedBytesPerSec,
      'errorMessage': errorMessage,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'category': category.name,
      'connectionCount': connectionCount,
      'etag': etag,
      'lastModified': lastModified,
      'referrer': referrer,
      'queueName': queueName,
      'segments': segments.map((s) => s.toJson()).toList(),
      'elapsedSeconds': elapsedSeconds,
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'] as String? ?? 'download';
    DownloadCategory parsedCategory = DownloadCategory.other;
    if (json['category'] != null) {
      parsedCategory = DownloadCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => NetGetUtils.classifyCategory(fileName),
      );
    } else {
      parsedCategory = NetGetUtils.classifyCategory(fileName);
    }

    final segmentsRaw = json['segments'] as List<dynamic>?;
    final parsedSegments = segmentsRaw != null
        ? segmentsRaw
              .whereType<Map<String, dynamic>>()
              .map((s) => DownloadSegment.fromJson(s))
              .toList()
        : <DownloadSegment>[];

    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: fileName,
      savePath: json['savePath'] as String? ?? '',
      totalBytes: json['totalBytes'] as int? ?? -1,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.queued,
      ),
      resumable: json['resumable'] as bool? ?? true,
      speedBytesPerSec: (json['speedBytesPerSec'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['errorMessage'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
      category: parsedCategory,
      connectionCount:
          json['connectionCount'] as int? ?? NetGetConstants.defaultConnections,
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
      referrer: json['referrer'] as String?,
      queueName:
          json['queueName'] as String? ?? NetGetConstants.defaultQueueName,
      segments: parsedSegments,
      elapsedSeconds: json['elapsedSeconds'] as int? ?? 0,
    );
  }
}
