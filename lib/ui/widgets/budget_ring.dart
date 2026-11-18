import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

/// Circular progress ring visualizing monthly budget consumption,
/// contrasting metered cellular usage against free off-peak window data.
class BudgetRing extends StatelessWidget {
  final int countedBytes;
  final int freeBytes;
  final int limitBytes;
  final double size;
  final double strokeWidth;
  final Widget? centerChild;

  const BudgetRing({
    super.key,
    required this.countedBytes,
    required this.freeBytes,
    required this.limitBytes,
    this.size = 140.0,
    this.strokeWidth = 10.0,
    this.centerChild,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final trackColor = isDark
        ? const Color(0xFF262E3B)
        : const Color(0xFFE2E8F0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _BudgetRingPainter(
              countedBytes: countedBytes,
              freeBytes: freeBytes,
              limitBytes: limitBytes,
              strokeWidth: strokeWidth,
              trackColor: trackColor,
              countedColor: ThreadTokens.clayTerracotta,
              freeColor: ThreadTokens.nileBlue,
            ),
          ),
          if (centerChild != null) centerChild!,
        ],
      ),
    );
  }
}

class _BudgetRingPainter extends CustomPainter {
  final int countedBytes;
  final int freeBytes;
  final int limitBytes;
  final double strokeWidth;
  final Color trackColor;
  final Color countedColor;
  final Color freeColor;

  _BudgetRingPainter({
    required this.countedBytes,
    required this.freeBytes,
    required this.limitBytes,
    required this.strokeWidth,
    required this.trackColor,
    required this.countedColor,
    required this.freeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw full background circle
    canvas.drawCircle(center, radius, trackPaint);

    if (limitBytes <= 0) return;

    final totalCapacity = limitBytes > 0
        ? limitBytes
        : (countedBytes + freeBytes);
    if (totalCapacity <= 0) return;

    final countedFrac = (countedBytes / totalCapacity).clamp(0.0, 1.0);
    final freeFrac = (freeBytes / totalCapacity).clamp(0.0, 1.0 - countedFrac);

    const startAngle = -math.pi / 2;
    final countedSweep = countedFrac * 2 * math.pi;
    final freeSweep = freeFrac * 2 * math.pi;

    if (countedSweep > 0) {
      final countedPaint = Paint()
        ..color = countedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        countedSweep,
        false,
        countedPaint,
      );
    }

    if (freeSweep > 0) {
      final freePaint = Paint()
        ..color = freeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + countedSweep,
        freeSweep,
        false,
        freePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BudgetRingPainter oldDelegate) {
    return oldDelegate.countedBytes != countedBytes ||
        oldDelegate.freeBytes != freeBytes ||
        oldDelegate.limitBytes != limitBytes ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
