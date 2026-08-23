import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 搜索框宽度适配：竖屏（手机布局）时占满可用宽度，横屏/宽屏时限制在 500 内保持居中；
/// 断点切换时用隐式动画平滑过渡宽度，避免拉伸窗口时宽度突变。
class SearchBarWidth extends StatelessWidget {
  const SearchBarWidth({
    super.key,
    required this.isPortrait,
    required this.child,
  });

  final bool isPortrait;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final maxWidth = isPortrait ? available : math.min(available, 500.0);
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: maxWidth, end: maxWidth),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubicEmphasized,
          builder: (context, width, child) => ConstrainedBox(
            constraints: BoxConstraints(minWidth: 200, maxWidth: width),
            child: child,
          ),
          child: child,
        );
      },
    );
  }
}
