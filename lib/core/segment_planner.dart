import 'dart:math';
import 'constants.dart';

class DownloadSegment {
  final int index;
  final int startByte;
  final int endByte; // inclusive, or -1 if unknown length
  final int downloadedBytes;
  final bool isCompleted;

  const DownloadSegment({
    required this.index,
    required this.startByte,
    required this.endByte,
    this.downloadedBytes = 0,
    this.isCompleted = false,
  });

  int get currentOffset => startByte + downloadedBytes;

  int get segmentLength {
    if (endByte < 0) return -1;
    return endByte - startByte + 1;
  }

  int get remainingBytes {
    if (endByte < 0) return -1;
    final rem = (endByte + 1) - currentOffset;
    return rem > 0 ? rem : 0;
  }

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

class SegmentSplitResult {
  final List<DownloadSegment> segments;
  final DownloadSegment newSegment;

  const SegmentSplitResult({required this.segments, required this.newSegment});
}

class SegmentPlanner {
  static const int minSplitThreshold = NetGetConstants.minSplitThresholdBytes;

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

    final connections = connectionCount.clamp(
      1,
      NetGetConstants.maxConnections,
    );
    final effectiveConnections = min(
      connections,
      max(1, totalBytes ~/ NetGetConstants.minChunkPerConnectionBytes),
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

  static SegmentSplitResult? splitLargestSegment(
    List<DownloadSegment> segments, {
    int minThreshold = minSplitThreshold,
  }) {
    if (segments.isEmpty || minThreshold <= 0) return null;

    int candidateIdx = -1;
    int maxRemaining = 0;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.isFinished || seg.endByte < 0) continue;
      final rem = seg.remainingBytes;
      if (rem > maxRemaining && rem >= minThreshold) {
        maxRemaining = rem;
        candidateIdx = i;
      }
    }

    if (candidateIdx < 0) return null;

    final candidate = segments[candidateIdx];
    final curOffset = candidate.currentOffset;
    final originalEnd = candidate.endByte;
    final remaining = originalEnd - curOffset + 1;
    if (remaining < minThreshold) return null;

    final half = remaining ~/ 2;
    final newCandidateEnd = curOffset + half - 1;
    final newSegStart = newCandidateEnd + 1;

    final updatedCandidate = candidate.copyWith(endByte: newCandidateEnd);
    final newSegment = DownloadSegment(
      index: segments.length,
      startByte: newSegStart,
      endByte: originalEnd,
    );

    final updatedList = List<DownloadSegment>.from(segments);
    updatedList[candidateIdx] = updatedCandidate;
    updatedList.add(newSegment);

    return SegmentSplitResult(
      segments: List.unmodifiable(updatedList),
      newSegment: newSegment,
    );
  }
}
