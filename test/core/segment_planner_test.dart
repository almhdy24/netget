import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';

void main() {
  group('SegmentPlanner', () {
    test('creates single segment if totalBytes <= 0 or not resumable', () {
      final segs1 = SegmentPlanner.planInitialSegments(
        totalBytes: -1,
        connectionCount: 4,
        resumable: true,
      );
      expect(segs1.length, 1);
      expect(segs1.first.startByte, 0);
      expect(segs1.first.endByte, -1);

      final segs2 = SegmentPlanner.planInitialSegments(
        totalBytes: 1000000,
        connectionCount: 4,
        resumable: false,
      );
      expect(segs2.length, 1);
      expect(segs2.first.startByte, 0);
      expect(segs2.first.endByte, 999999);
    });

    test('partitions totalBytes evenly across connection count', () {
      final total = 4 * 1024 * 1024; // 4 MB
      final segs = SegmentPlanner.planInitialSegments(
        totalBytes: total,
        connectionCount: 4,
        resumable: true,
      );

      expect(segs.length, 4);
      expect(segs[0].startByte, 0);
      expect(segs[0].endByte, 1048576 - 1);
      expect(segs[3].endByte, total - 1);

      // Verify contiguous bytes without gaps or overlaps
      for (var i = 0; i < segs.length - 1; i++) {
        expect(segs[i].endByte + 1, segs[i + 1].startByte);
      }
    });

    test(
      'splitLargestSegment dynamically splits candidate remaining bytes in half',
      () {
        final seg1 = DownloadSegment(
          index: 0,
          startByte: 0,
          endByte: 1048575,
          downloadedBytes: 1048576, // Finished
          isCompleted: true,
        );
        final seg2 = DownloadSegment(
          index: 1,
          startByte: 1048576,
          endByte: 3145727, // 2 MB total, 0 downloaded
          downloadedBytes: 0,
        );

        final segments = [seg1, seg2];
        final newSeg = SegmentPlanner.splitLargestSegment(
          segments,
          minThreshold: 256 * 1024,
        );

        expect(newSeg, isNotNull);
        expect(segments.length, 3);

        // Candidate endByte should be truncated, new segment takes upper half
        expect(seg2.endByte + 1, newSeg!.startByte);
        expect(newSeg.endByte, 3145727);
      },
    );

    test('returns null when remaining bytes are smaller than threshold', () {
      final seg = DownloadSegment(
        index: 0,
        startByte: 0,
        endByte: 10000,
        downloadedBytes: 9000,
      );
      final result = SegmentPlanner.splitLargestSegment([
        seg,
      ], minThreshold: 256 * 1024);
      expect(result, isNull);
    });
  });
}
