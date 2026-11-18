import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';
import '../../core/segment_planner.dart';

/// A custom progress bar visualizing concurrent connection threads (خيوط التحميل)
/// as distinct, woven strands across the file's byte range.
class ThreadBar extends StatelessWidget {
  final List<DownloadSegment> segments;
  final int totalBytes;
  final int downloadedBytes;
  final bool isDownloading;
  final double height;
  final BorderRadius borderRadius;

  const ThreadBar({
    super.key,
    required this.segments,
    required this.totalBytes,
    required this.downloadedBytes,
    this.isDownloading = false,
    this.height = 6.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(3.0)),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final trackColor = isDark
        ? const Color(0xFF262E3B)
        : const Color(0xFFE2E8F0);

    return ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _ThreadBarPainter(
          segments: segments,
          totalBytes: totalBytes,
          downloadedBytes: downloadedBytes,
          isDownloading: isDownloading,
          trackColor: trackColor,
          fallbackColor: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThreadBarPainter extends CustomPainter {
  final List<DownloadSegment> segments;
  final int totalBytes;
  final int downloadedBytes;
  final bool isDownloading;
  final Color trackColor;
  final Color fallbackColor;

  _ThreadBarPainter({
    required this.segments,
    required this.totalBytes,
    required this.downloadedBytes,
    required this.isDownloading,
    required this.trackColor,
    required this.fallbackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.fill;

    // Draw background track
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), trackPaint);

    if (totalBytes <= 0) {
      // Indeterminate state: draw subtle animated or pulsing segment
      final indeterminatePaint = Paint()
        ..color = fallbackColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * 0.3, size.height),
        indeterminatePaint,
      );
      return;
    }

    if (segments.isEmpty) {
      // Single connection / fallback: uniform progress bar
      final frac = (downloadedBytes / totalBytes).clamp(0.0, 1.0);
      final fillPaint = Paint()
        ..color = fallbackColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * frac, size.height),
        fillPaint,
      );
      return;
    }

    // Paint multi-thread segments
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final segStartFrac = (seg.startByte / totalBytes).clamp(0.0, 1.0);
      final maxLen = seg.segmentLength > 0
          ? seg.segmentLength
          : seg.downloadedBytes;
      final downloadedInSeg = seg.downloadedBytes.clamp(0, maxLen);
      final segProgressFrac = ((seg.startByte + downloadedInSeg) / totalBytes)
          .clamp(0.0, 1.0);

      final startX = segStartFrac * size.width;
      final progressWidth = (segProgressFrac - segStartFrac) * size.width;

      if (progressWidth > 0) {
        final threadColor = ThreadTokens.threadColor(seg.index);
        final segmentPaint = Paint()
          ..color = threadColor
          ..style = PaintingStyle.fill;

        canvas.drawRect(
          Rect.fromLTWH(startX, 0, progressWidth, size.height),
          segmentPaint,
        );

        // Subtle divider hairline between segments
        final dividerPaint = Paint()
          ..color = trackColor.withValues(alpha: 0.5)
          ..strokeWidth = 0.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(startX, 0),
          Offset(startX, size.height),
          dividerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThreadBarPainter oldDelegate) {
    return oldDelegate.downloadedBytes != downloadedBytes ||
        oldDelegate.totalBytes != totalBytes ||
        oldDelegate.segments != segments ||
        oldDelegate.isDownloading != isDownloading;
  }
}
