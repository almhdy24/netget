import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netget/core/segment_planner.dart';
import 'package:netget/ui/details/segment_map_painter.dart';
import 'package:netget/ui/details/speed_graph_painter.dart';

void main() {
  test(
    'CHARACTERIZATION: SegmentMapPainter shouldRepaint returns false when same segments list is mutated in-place',
    () {
      final segments = [
        const DownloadSegment(
          index: 0,
          startByte: 0,
          endByte: 1000,
          downloadedBytes: 100,
        ),
      ];

      final painter1 = SegmentMapPainter(
        segments: segments,
        totalBytes: 1000,
        isCompleted: false,
        isDark: false,
        primaryColor: Colors.blue,
      );

      // Progress occurs: segment downloadedBytes increases
      segments[0] = segments[0].copyWith(downloadedBytes: 500);

      final painter2 = SegmentMapPainter(
        segments: segments,
        totalBytes: 1000,
        isCompleted: false,
        isDark: false,
        primaryColor: Colors.blue,
      );

      // In buggy code: oldDelegate.segments != segments evaluates to false because it is the exact same list instance!
      // Result: shouldRepaint returns false, and the UI never paints the new progress!
      expect(
        painter2.shouldRepaint(painter1),
        isTrue,
        reason:
            'SegmentMapPainter must request repaint when segment progress changes even if list reference was shared',
      );
    },
  );

  test(
    'CHARACTERIZATION: SpeedGraphPainter shouldRepaint returns false when samples list is appended to',
    () {
      final samples = <double>[1000.0, 2000.0];

      final painter1 = SpeedGraphPainter(
        samples: samples,
        isDark: false,
        primaryColor: Colors.blue,
      );

      // New speed sample is added to the in-memory list
      samples.add(3000.0);

      final painter2 = SpeedGraphPainter(
        samples: samples,
        isDark: false,
        primaryColor: Colors.blue,
      );

      // In buggy code: oldDelegate.samples != samples is false because it is the exact same list instance!
      expect(
        painter2.shouldRepaint(painter1),
        isTrue,
        reason: 'SpeedGraphPainter must repaint when new speed samples arrive',
      );
    },
  );
}
