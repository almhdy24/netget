import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/utils.dart';

/// Custom painter for rendering live 60-sample speed sparkline graph.
/// Reuses Paint and TextPainter instances to prevent memory churn during high-frequency updates.
class SpeedGraphPainter extends CustomPainter {
  final List<double> samples;
  final bool isDark;
  final Color primaryColor;
  final Color backgroundColor;
  final Color borderColor;
  final Color gridColor;
  final Color textColor;

  late final Paint _bgPaint;
  late final Paint _borderPaint;
  late final Paint _gridPaint;
  late final Paint _fillPaint;
  late final Paint _linePaint;
  late final Paint _dotPaint;
  final TextPainter _textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );
  final Path _fillPath = Path();
  final Path _linePath = Path();

  SpeedGraphPainter({
    required this.samples,
    required this.isDark,
    required this.primaryColor,
    Color? backgroundColor,
    Color? borderColor,
    Color? gridColor,
    Color? textColor,
  }) : backgroundColor =
           backgroundColor ??
           (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
       borderColor =
           borderColor ??
           (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
       gridColor =
           gridColor ??
           (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
       textColor =
           textColor ??
           (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)) {
    _bgPaint = Paint()
      ..color = this.backgroundColor
      ..style = PaintingStyle.fill;
    _borderPaint = Paint()
      ..color = this.borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    _gridPaint = Paint()
      ..color = this.gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    _fillPaint = Paint()..style = PaintingStyle.fill;
    _linePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    // Background & border
    canvas.drawRRect(rrect, _bgPaint);
    canvas.drawRRect(rrect, _borderPaint);

    // Grid lines (horizontal)
    canvas.drawLine(
      Offset(0, size.height * 0.25),
      Offset(size.width, size.height * 0.25),
      _gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      _gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.75),
      Offset(size.width, size.height * 0.75),
      _gridPaint,
    );

    // Vertical time marks (quarter marks)
    for (var i = 1; i <= 3; i++) {
      final x = size.width * (i / 4.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), _gridPaint);
    }

    if (samples.isEmpty) return;

    final maxSpeed = max(1024.0, samples.reduce(max));
    const totalPoints = 60;
    final startIndex = max(0, samples.length - totalPoints);
    final effectiveSamples = samples.sublist(startIndex);

    if (effectiveSamples.length >= 2) {
      final stepX = size.width / (totalPoints - 1);
      final xOffset = size.width - (effectiveSamples.length - 1) * stepX;

      _fillPath.reset();
      _linePath.reset();

      final firstX = xOffset;
      final firstNorm = (effectiveSamples[0] / maxSpeed).clamp(0.0, 1.0);
      final firstY = size.height - 6 - (firstNorm * (size.height - 12));

      _fillPath.moveTo(firstX, size.height);
      _fillPath.lineTo(firstX, firstY);
      _linePath.moveTo(firstX, firstY);

      Offset lastPoint = Offset(firstX, firstY);

      for (var i = 1; i < effectiveSamples.length; i++) {
        final x = xOffset + (i * stepX);
        final norm = (effectiveSamples[i] / maxSpeed).clamp(0.0, 1.0);
        final y = size.height - 6 - (norm * (size.height - 12));
        _fillPath.lineTo(x, y);
        _linePath.lineTo(x, y);
        lastPoint = Offset(x, y);
      }

      _fillPath.lineTo(lastPoint.dx, size.height);
      _fillPath.close();

      _fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.25),
          primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(rect);

      canvas.drawPath(_fillPath, _fillPaint);
      canvas.drawPath(_linePath, _linePaint);
      canvas.drawCircle(lastPoint, 3.0, _dotPaint);
    }

    // Peak speed label
    final maxLabel = NetGetUtils.formatSpeed(maxSpeed);
    _textPainter.text = TextSpan(
      text: 'Peak: $maxLabel',
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: textColor,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    _textPainter.layout();
    _textPainter.paint(canvas, const Offset(6, 4));

    // Time markings label ("-60s" ... "Now")
    _textPainter.text = TextSpan(
      text: 'Now',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w500,
        color: textColor.withValues(alpha: 0.8),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    _textPainter.layout();
    _textPainter.paint(
      canvas,
      Offset(
        size.width - _textPainter.width - 6,
        size.height - _textPainter.height - 4,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant SpeedGraphPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.isDark != isDark ||
        oldDelegate.primaryColor != primaryColor;
  }
}
