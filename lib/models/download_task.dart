import '../core/constants.dart';
import '../core/segment_planner.dart';
import '../core/utils.dart';
import 'data_budget.dart';
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
  final int rev;
  final String? checksumExpected;
  final String? checksumActual;
  final String? checksumAlgorithm;
  final String? pauseReason;
  final NetworkPolicy networkPolicy;
  final List<String> mirrors;
  final int interruptionsRecovered;
  final int bytesPreservedByResume;

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
    this.rev = 0,
    this.checksumExpected,
    this.checksumActual,
    this.checksumAlgorithm,
    this.pauseReason,
    this.networkPolicy = NetworkPolicy.anyNetwork,
    this.mirrors = const [],
    this.interruptionsRecovered = 0,
    this.bytesPreservedByResume = 0,
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

  /// Whether actual and expected checksums match.
  bool get isIntegrityVerified {
    if (checksumExpected == null || checksumActual == null) return false;
    final exp = checksumExpected!.trim().toLowerCase();
    final act = checksumActual!.trim().toLowerCase();
    return exp.isNotEmpty && exp == act;
  }

  /// Whether checksum verification failed (both exist but do not match).
  bool get hasChecksumMismatch {
    if (checksumExpected == null || checksumActual == null) return false;
    final exp = checksumExpected!.trim().toLowerCase();
    final act = checksumActual!.trim().toLowerCase();
    return exp.isNotEmpty && act.isNotEmpty && exp != act;
  }

  static const Object _sentinel = Object();

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
    Object? errorMessage = _sentinel,
    bool clearError = false,
    DateTime? createdAt,
    Object? completedAt = _sentinel,
    bool clearCompletedAt = false,
    DownloadCategory? category,
    int? connectionCount,
    Object? etag = _sentinel,
    bool clearEtag = false,
    Object? lastModified = _sentinel,
    bool clearLastModified = false,
    Object? referrer = _sentinel,
    bool clearReferrer = false,
    String? queueName,
    List<DownloadSegment>? segments,
    List<double>? speedSamples,
    List<TaskLogEvent>? eventLog,
    int? elapsedSeconds,
    int? rev,
    Object? checksumExpected = _sentinel,
    bool clearChecksumExpected = false,
    Object? checksumActual = _sentinel,
    bool clearChecksumActual = false,
    Object? checksumAlgorithm = _sentinel,
    bool clearChecksumAlgorithm = false,
    Object? pauseReason = _sentinel,
    bool clearPauseReason = false,
    NetworkPolicy? networkPolicy,
    List<String>? mirrors,
    int? interruptionsRecovered,
    int? bytesPreservedByResume,
  }) {
    final String? resolvedErrorMessage;
    if (clearError) {
      resolvedErrorMessage = null;
    } else if (!identical(errorMessage, _sentinel)) {
      resolvedErrorMessage = errorMessage as String?;
    } else if ((status == DownloadStatus.queued ||
            status == DownloadStatus.downloading ||
            status == DownloadStatus.completed) &&
        this.errorMessage != null &&
        identical(errorMessage, _sentinel)) {
      resolvedErrorMessage = null;
    } else {
      resolvedErrorMessage = this.errorMessage;
    }

    final DateTime? resolvedCompletedAt;
    if (clearCompletedAt) {
      resolvedCompletedAt = null;
    } else if (!identical(completedAt, _sentinel)) {
      resolvedCompletedAt = completedAt as DateTime?;
    } else {
      resolvedCompletedAt = this.completedAt;
    }

    final String? resolvedEtag;
    if (clearEtag) {
      resolvedEtag = null;
    } else if (!identical(etag, _sentinel)) {
      resolvedEtag = etag as String?;
    } else {
      resolvedEtag = this.etag;
    }

    final String? resolvedLastModified;
    if (clearLastModified) {
      resolvedLastModified = null;
    } else if (!identical(lastModified, _sentinel)) {
      resolvedLastModified = lastModified as String?;
    } else {
      resolvedLastModified = this.lastModified;
    }

    final String? resolvedReferrer;
    if (clearReferrer) {
      resolvedReferrer = null;
    } else if (!identical(referrer, _sentinel)) {
      resolvedReferrer = referrer as String?;
    } else {
      resolvedReferrer = this.referrer;
    }

    final String? resolvedChecksumExpected;
    if (clearChecksumExpected) {
      resolvedChecksumExpected = null;
    } else if (!identical(checksumExpected, _sentinel)) {
      resolvedChecksumExpected = checksumExpected as String?;
    } else {
      resolvedChecksumExpected = this.checksumExpected;
    }

    final String? resolvedChecksumActual;
    if (clearChecksumActual) {
      resolvedChecksumActual = null;
    } else if (!identical(checksumActual, _sentinel)) {
      resolvedChecksumActual = checksumActual as String?;
    } else {
      resolvedChecksumActual = this.checksumActual;
    }

    final String? resolvedChecksumAlgorithm;
    if (clearChecksumAlgorithm) {
      resolvedChecksumAlgorithm = null;
    } else if (!identical(checksumAlgorithm, _sentinel)) {
      resolvedChecksumAlgorithm = checksumAlgorithm as String?;
    } else {
      resolvedChecksumAlgorithm = this.checksumAlgorithm;
    }

    final String? resolvedPauseReason;
    if (clearPauseReason) {
      resolvedPauseReason = null;
    } else if (!identical(pauseReason, _sentinel)) {
      resolvedPauseReason = pauseReason as String?;
    } else {
      resolvedPauseReason = this.pauseReason;
    }

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
      errorMessage: resolvedErrorMessage,
      createdAt: createdAt ?? this.createdAt,
      completedAt: resolvedCompletedAt,
      category: category ?? this.category,
      connectionCount: connectionCount ?? this.connectionCount,
      etag: resolvedEtag,
      lastModified: resolvedLastModified,
      referrer: resolvedReferrer,
      queueName: queueName ?? this.queueName,
      segments: segments ?? this.segments,
      speedSamples: speedSamples ?? this.speedSamples,
      eventLog: eventLog ?? this.eventLog,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      rev: rev ?? (this.rev + 1),
      checksumExpected: resolvedChecksumExpected,
      checksumActual: resolvedChecksumActual,
      checksumAlgorithm: resolvedChecksumAlgorithm,
      pauseReason: resolvedPauseReason,
      networkPolicy: networkPolicy ?? this.networkPolicy,
      mirrors: mirrors ?? this.mirrors,
      interruptionsRecovered:
          interruptionsRecovered ?? this.interruptionsRecovered,
      bytesPreservedByResume:
          bytesPreservedByResume ?? this.bytesPreservedByResume,
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
      'rev': rev,
      'checksumExpected': checksumExpected,
      'checksumActual': checksumActual,
      'checksumAlgorithm': checksumAlgorithm,
      'pauseReason': pauseReason,
      'networkPolicy': networkPolicy.name,
      'mirrors': mirrors,
      'interruptionsRecovered': interruptionsRecovered,
      'bytesPreservedByResume': bytesPreservedByResume,
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
      rev: json['rev'] as int? ?? 0,
      checksumExpected: json['checksumExpected'] as String?,
      checksumActual: json['checksumActual'] as String?,
      checksumAlgorithm: json['checksumAlgorithm'] as String?,
      pauseReason: json['pauseReason'] as String?,
      networkPolicy: NetworkPolicy.fromString(json['networkPolicy'] as String?),
      mirrors:
          (json['mirrors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      interruptionsRecovered: json['interruptionsRecovered'] as int? ?? 0,
      bytesPreservedByResume: json['bytesPreservedByResume'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DownloadTask &&
        other.id == id &&
        other.url == url &&
        other.fileName == fileName &&
        other.savePath == savePath &&
        other.totalBytes == totalBytes &&
        other.downloadedBytes == downloadedBytes &&
        other.status == status &&
        other.resumable == resumable &&
        other.speedBytesPerSec == speedBytesPerSec &&
        other.errorMessage == errorMessage &&
        other.createdAt == createdAt &&
        other.completedAt == completedAt &&
        other.category == category &&
        other.connectionCount == connectionCount &&
        other.etag == etag &&
        other.lastModified == lastModified &&
        other.referrer == referrer &&
        other.queueName == queueName &&
        other.elapsedSeconds == elapsedSeconds &&
        other.rev == rev &&
        other.checksumExpected == checksumExpected &&
        other.checksumActual == checksumActual &&
        other.checksumAlgorithm == checksumAlgorithm &&
        other.pauseReason == pauseReason &&
        other.networkPolicy == networkPolicy &&
        other.interruptionsRecovered == interruptionsRecovered &&
        other.bytesPreservedByResume == bytesPreservedByResume;
  }

  @override
  int get hashCode => Object.hash(
    id,
    status,
    downloadedBytes,
    totalBytes,
    speedBytesPerSec,
    etag,
    lastModified,
    rev,
    checksumExpected,
    pauseReason,
  );
}
