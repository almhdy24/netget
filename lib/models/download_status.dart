/// Status of a download task.
enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled;

  bool get isActive => this == queued || this == downloading;
  bool get isPaused => this == paused;
  bool get isCompleted => this == completed;
  bool get isFailed => this == failed;
  bool get isCancelled => this == cancelled;

  String get label {
    switch (this) {
      case DownloadStatus.queued:
        return 'Queued';
      case DownloadStatus.downloading:
        return 'Downloading';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.completed:
        return 'Completed';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.cancelled:
        return 'Cancelled';
    }
  }
}
