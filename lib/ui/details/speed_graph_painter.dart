import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/utils.dart';

/// Custom painter for rendering live 60-sample speed sparkline graph.
class SpeedGraphPainter extends CustomPainter {
  final List<double> samples;
  final bool isDark;
  final Color primaryColor;

  SpeedGraphPainter({
    required this.samples,
    required this.isDark,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background canvas rect
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF13161A) : const Color(0xFFF6F8FB)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      bgPaint,
    );

    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF2B313B) : const Color(0xFFE2E6ED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      borderPaint,
    );

    // Grid lines (top, middle, bottom)
    final gridPaint = Paint()
      ..color = isDark ? const Color(0xFF222730) : const Color(0xFFE6EBF2)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height * 0.25),
      Offset(size.width, size.height * 0.25),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.75),
      Offset(size.width, size.height * 0.75),
      gridPaint,
    );

    // Vertical time marks (every 15 samples out of 60)
    for (var i = 1; i <= 3; i++) {
      final x = size.width * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (samples.isEmpty) return;

    // Determine max speed ceiling
    final maxSpeed = max(1024.0, samples.reduce(max));

    // Pad samples to 60 points if less than 60
    final points = <Offset>[];
    const totalPoints = 60;
    final startIndex = max(0, samples.length - totalPoints);
    final effectiveSamples = samples.sublist(startIndex);

    final stepX = size.width / (totalPoints - 1);
    final xOffset = size.width - (effectiveSamples.length - 1) * stepX;

    for (var i = 0; i < effectiveSamples.length; i++) {
      final s = effectiveSamples[i];
      final x = xOffset + (i * stepX);
      final normalized = (s / maxSpeed).clamp(0.0, 1.0);
      // Leave 8px margin top and bottom
      final y = size.height - 8 - (normalized * (size.height - 16));
      points.add(Offset(x, y));
    }

    if (points.length >= 2) {
      // Area fill path
      final fillPath = Path();
      fillPath.moveTo(points.first.dx, size.height);
      for (final pt in points) {
        fillPath.lineTo(pt.dx, pt.dy);
      }
      fillPath.lineTo(points.last.dx, size.height);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primaryColor.withValues(alpha: 0.35),
            primaryColor.withValues(alpha: 0.0),
          ],
        ).createShader(rect)
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);

      // Line stroke path
      final linePath = Path();
      linePath.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        linePath.lineTo(points[i].dx, points[i].dy);
      }

      final linePaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, linePaint);

      // Dot on last point
      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points.last, 3.5, dotPaint);
    }

    // Peak speed label
    final maxLabel = NetGetUtils.formatSpeed(maxSpeed);
    final textSpan = TextSpan(
      text: 'Peak: $maxLabel',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white60 : Colors.black54,
        fontFamily: 'monospace',
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, const Offset(8, 6));

    // Time markings label (e.g. "60s ago ... Now")
    final timeSpan = TextSpan(
      text: '60s ago',
      style: TextStyle(
        fontSize: 9,
        color: isDark ? Colors.white38 : Colors.black38,
        fontFamily: 'monospace',
      ),
    );
    final timePainter = TextPainter(
      text: timeSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    timePainter.paint(canvas, Offset(8, size.height - timePainter.height - 4));

    final nowSpan = TextSpan(
      text: 'Now',
      style: TextStyle(
        fontSize: 9,
        color: isDark ? Colors.white38 : Colors.black38,
        fontFamily: 'monospace',
      ),
    );
    final nowPainter = TextPainter(
      text: nowSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    nowPainter.paint(
      canvas,
      Offset(
        size.width - nowPainter.width - 8,
        size.height - nowPainter.height - 4,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant SpeedGraphPainter oldDelegate) {
    return oldDelegate.samples != samples;
  }
}
