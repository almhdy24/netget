import 'download_status.dart';

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
    };
  }

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String? ?? 'download',
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
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'] as String)
          : null,
    );
  }
}
