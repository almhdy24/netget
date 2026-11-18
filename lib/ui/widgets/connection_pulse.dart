import 'package:flutter/material.dart';
import '../../core/design_tokens.dart';

/// Animated pulse indicator reflecting network connection thread activity.
class ConnectionPulse extends StatefulWidget {
  final bool isActive;
  final int connectionCount;
  final Color? color;
  final double size;

  const ConnectionPulse({
    super.key,
    required this.isActive,
    this.connectionCount = 1,
    this.color,
    this.size = 10.0,
  });

  @override
  State<ConnectionPulse> createState() => _ConnectionPulseState();
}

class _ConnectionPulseState extends State<ConnectionPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _animation = Tween<double>(
      begin: 0.8,
      end: 1.3,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isActive) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant ConnectionPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor =
        widget.color ??
        (widget.isActive ? ThreadTokens.nileBlue : theme.disabledColor);

    if (!widget.isActive) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: baseColor.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size * _animation.value,
              height: widget.size * _animation.value,
              decoration: BoxDecoration(
                color: baseColor.withValues(
                  alpha: (0.45 / _animation.value).clamp(0.0, 1.0),
                ),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: widget.size * 0.7,
              height: widget.size * 0.7,
              decoration: BoxDecoration(
                color: baseColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        );
      },
    );
  }
}
