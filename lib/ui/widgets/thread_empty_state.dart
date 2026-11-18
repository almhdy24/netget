import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';
import 'empty_state_view.dart';

/// Empty state widget with custom-drawn woven threads illustration,
/// reinforcing NetGet's «خيوط» identity and «ما بنبدأ من الصفر» ethos.
class ThreadEmptyState extends StatelessWidget {
  final VoidCallback? onAddPressed;

  const ThreadEmptyState({super.key, this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return EmptyStateView(
      illustration: SizedBox(
        width: 140,
        height: 140,
        child: CustomPaint(
          painter: _WovenThreadsPainter(
            amber: ThreadTokens.desertAmber,
            blue: ThreadTokens.nileBlue,
            terracotta: ThreadTokens.clayTerracotta,
          ),
        ),
      ),
      title: isArabic ? 'ما بنبدأ من الصفر' : 'We Never Start from Zero',
      message: isArabic
          ? 'لا توجد تحميلات حالياً.\nأضف رابطاً لتحميل صامد يستأنف دائماً حيث توقف.'
          : 'No downloads yet.\nAdd a link for resilient downloads that never start from scratch.',
      buttonText: isArabic ? 'إضافة تحميل جديد' : 'Add URL',
      onButtonPressed: onAddPressed,
    );
  }
}

class _WovenThreadsPainter extends CustomPainter {
  final Color amber;
  final Color blue;
  final Color terracotta;

  _WovenThreadsPainter({
    required this.amber,
    required this.blue,
    required this.terracotta,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer subtle ring
    final ringPaint = Paint()
      ..color = blue.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, size.width * 0.44, ringPaint);

    // Draw stylized woven bezier threads
    final p1 = Paint()
      ..color = amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final path1 = Path();
    path1.moveTo(size.width * 0.2, size.height * 0.7);
    path1.cubicTo(
      size.width * 0.35,
      size.height * 0.2,
      size.width * 0.65,
      size.height * 0.8,
      size.width * 0.8,
      size.height * 0.3,
    );
    canvas.drawPath(path1, p1);

    final p2 = Paint()
      ..color = blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final path2 = Path();
    path2.moveTo(size.width * 0.25, size.height * 0.3);
    path2.cubicTo(
      size.width * 0.4,
      size.height * 0.85,
      size.width * 0.6,
      size.height * 0.15,
      size.width * 0.75,
      size.height * 0.7,
    );
    canvas.drawPath(path2, p2);

    final p3 = Paint()
      ..color = terracotta
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final path3 = Path();
    path3.moveTo(size.width * 0.15, size.height * 0.45);
    path3.cubicTo(
      size.width * 0.45,
      size.height * 0.5,
      size.width * 0.55,
      size.height * 0.5,
      size.width * 0.85,
      size.height * 0.55,
    );
    canvas.drawPath(path3, p3);

    // Central connection node
    final nodePaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5.0, nodePaint);
  }

  @override
  bool shouldRepaint(covariant _WovenThreadsPainter oldDelegate) => false;
}
