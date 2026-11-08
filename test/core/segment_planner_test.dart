import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';

void main() {
  group('SegmentPlanner', () {
    test(
      'planInitialSegments returns single segment for totalBytes <= 0 or non-resumable',
      () {
        final s1 = SegmentPlanner.planInitialSegments(
          totalBytes: -1,
          connectionCount: 4,
          resumable: true,
        );
        expect(s1.length, 1);
        expect(s1.first.startByte, 0);
        expect(s1.first.endByte, -1);

        final s2 = SegmentPlanner.planInitialSegments(
          totalBytes: 1000000,
          connectionCount: 4,
          resumable: false,
        );
        expect(s2.length, 1);
        expect(s2.first.startByte, 0);
        expect(s2.first.endByte, 999999);
      },
    );

    test(
      'planInitialSegments partitions large file into multiple contiguous ranges',
      () {
        final total = 1024 * 1024 * 4; // 4 MB
        final segments = SegmentPlanner.planInitialSegments(
          totalBytes: total,
          connectionCount: 4,
          resumable: true,
        );
        expect(segments.length, 4);
        expect(segments.first.startByte, 0);
        expect(segments.last.endByte, total - 1);

        // Verify contiguity
        for (var i = 0; i < segments.length - 1; i++) {
          expect(segments[i].endByte + 1, segments[i + 1].startByte);
        }
      },
    );

    test('DownloadSegment is immutable', () {
      const seg = DownloadSegment(
        index: 0,
        startByte: 0,
        endByte: 1000,
        downloadedBytes: 100,
      );
      final updated = seg.copyWith(downloadedBytes: 200);
      expect(seg.downloadedBytes, 100);
      expect(updated.downloadedBytes, 200);
    });

    test(
      'splitLargestSegment produces a new segment and does not mutate input',
      () {
        final initialSegments = [
          const DownloadSegment(
            index: 0,
            startByte: 0,
            endByte: 1000000,
            downloadedBytes: 100000,
          ),
        ];

        final result = SegmentPlanner.splitLargestSegment(
          initialSegments,
          minThreshold: 256 * 1024,
        );

        expect(result, isNotNull);
        // Input list should remain unmodified
        expect(initialSegments.length, 1);
        expect(initialSegments.first.endByte, 1000000);

        // Output segments should have 2 segments
        expect(result!.segments.length, 2);
        final first = result.segments[0];
        final second = result.segments[1];
        expect(first.endByte + 1, second.startByte);
        expect(second.endByte, 1000000);
        expect(result.newSegment, second);
      },
    );

    test(
      'splitLargestSegment returns null when remaining bytes < minThreshold',
      () {
        final initialSegments = [
          const DownloadSegment(
            index: 0,
            startByte: 0,
            endByte: 1000,
            downloadedBytes: 900,
          ),
        ];

        final result = SegmentPlanner.splitLargestSegment(
          initialSegments,
          minThreshold: 256 * 1024,
        );

        expect(result, isNull);
      },
    );
  });
}
