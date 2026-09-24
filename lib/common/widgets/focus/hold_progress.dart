import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 长按确定的进度反馈环。
///
/// 沿圆角矩形轮廓顺时针推进，对应 blbl 的 `HoldProgressRingRenderer`。
/// 没有这个反馈，用户无法判断"确定"是没按到还是会触发长按。
class HoldProgressRing extends StatelessWidget {
  const HoldProgressRing({
    super.key,
    required this.progress,
    this.radius = TvFocusSpec.radius,
    this.strokeWidth = 3,
    this.inset = 2,
  });

  /// 0→1
  final double progress;
  final BorderRadius radius;
  final double strokeWidth;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: EdgeInsets.all(inset),
      child: CustomPaint(
        painter: _HoldProgressPainter(
          progress: progress.clamp(0.0, 1.0),
          radius: radius,
          strokeWidth: strokeWidth,
          color: colorScheme.primary,
          trackColor: colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

class _HoldProgressPainter extends CustomPainter {
  _HoldProgressPainter({
    required this.progress,
    required this.radius,
    required this.strokeWidth,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final BorderRadius radius;
  final double strokeWidth;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(
      rect.deflate(strokeWidth / 2),
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawRRect(rrect, track);

    if (progress <= 0) return;
    final path = Path()..addRRect(rrect);
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    // 从右侧中点起顺时针推进，视觉上贴近"读条"
    final metrics = path.computeMetrics().first;
    final start = metrics.length / 4;
    canvas.drawPath(
      metrics.extractPath(
        start,
        start + metrics.length * progress,
      ),
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_HoldProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}
