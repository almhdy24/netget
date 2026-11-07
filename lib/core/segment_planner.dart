import 'dart:math';

/// Represents a single byte range segment within a file.
class DownloadSegment {
  final int index;
  final int startByte;
  int endByte; // inclusive, or -1 if unknown length
  int downloadedBytes;
  bool isCompleted;

  DownloadSegment({
    required this.index,
    required this.startByte,
    required this.endByte,
    this.downloadedBytes = 0,
    this.isCompleted = false,
  });

  /// Current file offset for resuming/writing this segment.
  int get currentOffset => startByte + downloadedBytes;

  /// Total size of this segment in bytes (-1 if unbounded).
  int get segmentLength {
    if (endByte < 0) return -1;
    return endByte - startByte + 1;
  }

  /// Remaining bytes left to download in this segment (-1 if unbounded).
  int get remainingBytes {
    if (endByte < 0) return -1;
    final rem = (endByte + 1) - currentOffset;
    return rem > 0 ? rem : 0;
  }

  /// Whether this segment has finished downloading.
  bool get isFinished {
    if (isCompleted) return true;
    if (endByte >= 0 && currentOffset > endByte) return true;
    return false;
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'startByte': startByte,
    'endByte': endByte,
    'downloadedBytes': downloadedBytes,
    'isCompleted': isCompleted,
  };

  factory DownloadSegment.fromJson(Map<String, dynamic> json) {
    return DownloadSegment(
      index: json['index'] as int,
      startByte: json['startByte'] as int,
      endByte: json['endByte'] as int,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );
  }

  DownloadSegment copyWith({
    int? index,
    int? startByte,
    int? endByte,
    int? downloadedBytes,
    bool? isCompleted,
  }) {
    return DownloadSegment(
      index: index ?? this.index,
      startByte: startByte ?? this.startByte,
      endByte: endByte ?? this.endByte,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

/// Pure logic for initial segment partitioning and dynamic re-splitting.
class SegmentPlanner {
  /// Minimum segment chunk size worth splitting (256 KB).
  static const int minSplitThreshold = 256 * 1024;

  /// Creates initial segments for a download.
  /// If [totalBytes] <= 0 or not [resumable], creates a single segment [0..-1].
  /// Otherwise divides [totalBytes] into [connectionCount] (clamped between 1 and 16).
  static List<DownloadSegment> planInitialSegments({
    required int totalBytes,
    required int connectionCount,
    required bool resumable,
  }) {
    if (totalBytes <= 0 || !resumable || connectionCount <= 1) {
      return [
        DownloadSegment(
          index: 0,
          startByte: 0,
          endByte: totalBytes > 0 ? totalBytes - 1 : -1,
        ),
      ];
    }

    final connections = connectionCount.clamp(1, 16);
    // Don't split into more segments than there are 128KB chunks
    final effectiveConnections = min(
      connections,
      max(1, totalBytes ~/ (128 * 1024)),
    );
    if (effectiveConnections <= 1) {
      return [DownloadSegment(index: 0, startByte: 0, endByte: totalBytes - 1)];
    }

    final segmentSize = totalBytes ~/ effectiveConnections;
    final segments = <DownloadSegment>[];

    for (var i = 0; i < effectiveConnections; i++) {
      final start = i * segmentSize;
      final end = (i == effectiveConnections - 1)
          ? totalBytes - 1
          : (start + segmentSize - 1);
      segments.add(DownloadSegment(index: i, startByte: start, endByte: end));
    }

    return segments;
  }

  /// Dynamic Re-splitting:
  /// When a segment finishes, find the active segment with the largest remaining bytes.
  /// If it has at least [minThreshold] bytes left, split its remaining range in half,
  /// truncate the existing segment's endByte, and return a new DownloadSegment for the top half.
  /// Returns null if no segment can be meaningfully split.
  static DownloadSegment? splitLargestSegment(
    List<DownloadSegment> segments, {
    int minThreshold = minSplitThreshold,
  }) {
    DownloadSegment? candidate;
    int maxRemaining = 0;

    for (final seg in segments) {
      if (seg.isFinished || seg.endByte < 0) continue;
      final rem = seg.remainingBytes;
      if (rem > maxRemaining && rem >= minThreshold) {
        maxRemaining = rem;
        candidate = seg;
      }
    }

    if (candidate == null) return null;

    final curOffset = candidate.currentOffset;
    final originalEnd = candidate.endByte;
    final remaining = originalEnd - curOffset + 1;
    if (remaining < minThreshold) return null;

    // Split point: candidate keeps lower half, new segment gets upper half
    final half = remaining ~/ 2;
    final newCandidateEnd = curOffset + half - 1;
    final newSegStart = newCandidateEnd + 1;

    candidate.endByte = newCandidateEnd;

    final newIndex = segments.length;
    final newSegment = DownloadSegment(
      index: newIndex,
      startByte: newSegStart,
      endByte: originalEnd,
    );

    segments.add(newSegment);
    return newSegment;
  }
}
