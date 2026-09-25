import 'package:PiliPlus/common/widgets/focus/tv_button.dart';
import 'package:material_ui/material_ui.dart';

class ComBtn extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final double width;
  final double height;
  final String? tooltip;

  /// 把这一颗的焦点节点交出去（默认由 [TvButton] 自己内部建）。
  ///
  /// 直播页上栏的返回键靠它登记 `TvLabels.playerBack` 锚点：进栏锁
  /// （`TvEntryLock`）在播放器那一层，够不到按钮自己的 State，只能经锚点拿节点。
  final FocusNode? focusNode;

  const ComBtn({
    super.key,
    required this.icon,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.width = 34,
    this.height = 34,
    this.tooltip,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final child = TvButton(
      debugLabel: tooltip ?? 'ComBtn',
      focusNode: focusNode,
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      child: SizedBox(
        width: width,
        height: height,
        child: GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onSecondaryTap,
          behavior: HitTestBehavior.opaque,
          child: icon,
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: child);
    }
    return child;
  }
}
