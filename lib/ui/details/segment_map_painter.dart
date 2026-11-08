import 'package:flutter/material.dart';
import '../../core/segment_planner.dart';

/// Custom painter for rendering IDM-style connection segments block map.
/// Reuses Paint and TextPainter instances to avoid GC allocations during high-frequency updates.
class SegmentMapPainter extends CustomPainter {
  final List<DownloadSegment> segments;
  final int totalBytes;
  final bool isCompleted;
  final bool isDark;
  final Color primaryColor;
  final Color completedColor;
  final Color trackColor;
  final Color borderColor;
  final Color textColor;

  late final Paint _bgPaint;
  late final Paint _fillPaint;
  late final Paint _borderPaint;
  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );

  SegmentMapPainter({
    required this.segments,
    required this.totalBytes,
    required this.isCompleted,
    required this.isDark,
    required this.primaryColor,
    Color? completedColor,
    Color? trackColor,
    Color? borderColor,
    Color? textColor,
  }) : completedColor = completedColor ?? const Color(0xFF15803D),
       trackColor =
           trackColor ??
           (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
       borderColor =
           borderColor ??
           (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
       textColor =
           textColor ??
           (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)) {
    _bgPaint = Paint()
      ..color = this.trackColor
      ..style = PaintingStyle.fill;
    _fillPaint = Paint()..style = PaintingStyle.fill;
    _borderPaint = Paint()
      ..color = this.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty || totalBytes <= 0) {
      _paintSingleBar(canvas, size);
      return;
    }

    final blockCount = segments.length;
    const spacing = 3.0;
    final totalSpacing = spacing * (blockCount - 1);
    final availableWidth = size.width - totalSpacing;
    final blockWidth = (availableWidth / blockCount).clamp(16.0, size.width);

    for (var i = 0; i < blockCount; i++) {
      final seg = segments[i];
      final left = i * (blockWidth + spacing);
      final rect = Rect.fromLTWH(left, 0, blockWidth, size.height);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

      // Background
      canvas.drawRRect(rrect, _bgPaint);

      // Fill progress
      var fraction = 0.0;
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
        _fillPaint.color = isCompleted || seg.isCompleted
            ? completedColor
            : primaryColor;
        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, const Radius.circular(3)),
          _fillPaint,
        );
      }

      // Border
      canvas.drawRRect(rrect, _borderPaint);

      // Label (C1, C2, ...) with tabular figures
      _textPainter.text = TextSpan(
        text: 'C${seg.index + 1}',
        style: TextStyle(
          color: textColor,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      _textPainter.layout();

      final textX = left + (blockWidth - _textPainter.width) / 2;
      final textY = (size.height - _textPainter.height) / 2;
      _textPainter.paint(canvas, Offset(textX, textY));
    }
  }

  void _paintSingleBar(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
    canvas.drawRRect(rrect, _bgPaint);
    canvas.drawRRect(rrect, _borderPaint);
  }

  @override
  bool shouldRepaint(covariant SegmentMapPainter oldDelegate) {
    return oldDelegate.segments != segments ||
        oldDelegate.totalBytes != totalBytes ||
        oldDelegate.isCompleted != isCompleted ||
        oldDelegate.isDark != isDark ||
        oldDelegate.primaryColor != primaryColor;
  }
}
