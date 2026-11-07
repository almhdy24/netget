import 'package:flutter/material.dart';
import '../../core/segment_planner.dart';

/// Custom painter for rendering IDM-style connection segments block map.
class SegmentMapPainter extends CustomPainter {
  final List<DownloadSegment> segments;
  final int totalBytes;
  final bool isCompleted;
  final bool isDark;
  final Color primaryColor;

  SegmentMapPainter({
    required this.segments,
    required this.totalBytes,
    required this.isCompleted,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty || totalBytes <= 0) {
      _paintSingleBar(canvas, size);
      return;
    }

    final blockCount = segments.length;
    const double spacing = 4.0;
    final totalSpacing = spacing * (blockCount - 1);
    final availableWidth = size.width - totalSpacing;
    final blockWidth = (availableWidth / blockCount).clamp(16.0, size.width);

    for (var i = 0; i < blockCount; i++) {
      final seg = segments[i];
      final left = i * (blockWidth + spacing);
      final rect = Rect.fromLTWH(left, 0, blockWidth, size.height);

      // Background
      final bgPaint = Paint()
        ..color = isDark ? const Color(0xFF1E232B) : const Color(0xFFEAEEF4)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        bgPaint,
      );

      // Fill progress
      double fraction = 0.0;
      if (isCompleted || seg.isCompleted) {
        fraction = 1.0;
      } else if (seg.endByte > seg.startByte) {
        final totalSeg = seg.endByte - seg.startByte + 1;
        fraction = (seg.downloadedBytes / totalSeg).clamp(0.0, 1.0);
      } else if (seg.downloadedBytes > 0) {
        fraction = 1.0;
      }

      if (fraction > 0) {
        final fillRect = Rect.fromLTWH(
          left,
          0,
          blockWidth * fraction,
          size.height,
        );
        final fillPaint = Paint()
          ..color = isCompleted || seg.isCompleted
              ? const Color(0xFF2E7D32)
              : primaryColor
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, const Radius.circular(4)),
          fillPaint,
        );
      }

      // Border
      final borderPaint = Paint()
        ..color = isDark ? const Color(0xFF333B46) : const Color(0xFFD2D8E2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        borderPaint,
      );

      // Label (Conn #)
      final textSpan = TextSpan(
        text: 'C${seg.index + 1}',
        style: TextStyle(
          color: isDark ? Colors.white70 : Colors.black87,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final textX = left + (blockWidth - textPainter.width) / 2;
      final textY = (size.height - textPainter.height) / 2;
      textPainter.paint(canvas, Offset(textX, textY));
    }
  }

  void _paintSingleBar(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF1E232B) : const Color(0xFFEAEEF4)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      bgPaint,
    );

    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF333B46) : const Color(0xFFD2D8E2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant SegmentMapPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.totalBytes != totalBytes ||
        oldDelegate.isCompleted != isCompleted;
  }
}
