import 'package:PiliPlus/models/common/theme/theme_color_type.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:material_ui/material_ui.dart';

/// 当前程序设置的当前主题色；Android 动态取色生效时取主题方案主色
///
/// 传入 [theme]（通常为 `Theme.of(context)`）时，调用方会随主题变更自动重建
Color currentThemeColor([ThemeData? theme]) {
  if (ThemeUtils.isDynamicColor) {
    return (theme ?? ThemeUtils.theme).colorScheme.primary;
  }
  return colorThemeTypes[Pref.customColor].color;
}

/// 是否近无彩色（灰、白等）：RGB 三通道最大最小差小于 7/255
bool _isNearGrey(Color color) {
  final channels = [color.r, color.g, color.b]..sort();
  return channels.last - channels.first < 0.07;
}

/// 背景色过浅或近无彩色时是否应改用深色前景
bool themeColorNeedsDarkFg(Color bg) {
  final lum = bg.computeLuminance();
  return lum > 0.4 || (_isNearGrey(bg) && lum > 0.25);
}

/// 头像直播中标签：主题色胶囊底 + 信号波动画 + “直播中”文字
///
/// 胶囊底色取程序设置的当前主题色（[currentThemeColor]），
/// 主题色过浅（白、浅黄等）或近灰色时，文字与动画自动改用深色以保证可读性。
/// 外层 [FittedBox] 使标签在小头像上整体等比缩小，内容始终完整在胶囊内。
/// 动画复刻自 assets/images/live/signal.svg（SMIL 动画 flutter_svg 不支持）：
/// 三个圆按 0.4s 间隔错开，1.2s 周期，半径 0→11/24 视口、透明度 1→0，
/// 缓动曲线 .52,.6,.25,.99
class LiveTag extends StatelessWidget {
  const LiveTag({
    super.key,
    this.fontSize = 10,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  });

  final double fontSize;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // Theme.of 使本组件依赖主题，程序设置修改主题色后已显示的标签自动重建
    final bg = currentThemeColor(Theme.of(context));
    final fg = themeColorNeedsDarkFg(bg) ? Colors.black87 : Colors.white;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LiveSignalIcon(size: fontSize + 3, color: fg),
            const SizedBox(width: 3),
            Text(
              '直播中',
              strutStyle: StrutStyle(height: 1, leading: 0, fontSize: fontSize),
              style: TextStyle(
                height: 1,
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 直播头像标准描边：与直播标签同主题色的圆形边框
///
/// 颜色在自身 build 中取当前主题色并依赖 Theme，
/// 程序设置修改主题色后已显示的边框自动重建
class LiveAvatarBorder extends StatelessWidget {
  const LiveAvatarBorder({super.key, required this.child, this.width = 2});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = currentThemeColor(Theme.of(context));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          left: -width,
          top: -width,
          right: -width,
          bottom: -width,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: width),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveSignalIcon extends StatefulWidget {
  const _LiveSignalIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_LiveSignalIcon> createState() => _LiveSignalIconState();
}

class _LiveSignalIconState extends State<_LiveSignalIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _LiveSignalPainter(progress: _controller, color: widget.color),
    );
  }
}

class _LiveSignalPainter extends CustomPainter {
  _LiveSignalPainter({required this.progress, required this.color})
    : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  static const _ease = Cubic(0.52, 0.6, 0.25, 0.99);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 11 / 24;
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final t = (progress.value - i / 3) % 1.0;
      final e = _ease.transform(t);
      paint.color = color.withValues(alpha: (1 - e).clamp(0.0, 1.0));
      canvas.drawCircle(center, maxRadius * e, paint);
    }
  }

  @override
  bool shouldRepaint(_LiveSignalPainter oldDelegate) => true;
}
