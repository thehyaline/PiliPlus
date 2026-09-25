import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

Widget iconButton({
  BuildContext? context,
  String? tooltip,
  required Widget icon,
  required VoidCallback? onPressed,
  double size = 36,
  double? iconSize,
  Color? bgColor,
  Color? iconColor,
}) {
  Color? backgroundColor = bgColor;
  Color? foregroundColor = iconColor;
  if (context != null) {
    final colorScheme = ColorScheme.of(context);
    backgroundColor = colorScheme.secondaryContainer;
    foregroundColor = colorScheme.onSecondaryContainer;
  }
  // `FocusRing` 把节点交给 `IconButton`，整棵子树还是只有一个焦点节点，
  // 只是多一个按键聚焦时的描边；触摸和老模式（`Pref.tvFocus` 关）看不到
  // `circle: true`：图标按钮是方的，描边应该贴着外接圆走——和兜底环
  // （`TvFocusOverlay`）对裸 `IconButton` 的形状判定是同一套
  return FocusRing(
    debugLabel: tooltip ?? 'IconButton',
    circle: true,
    builder: (context, focusNode, focused) => SizedBox(
      width: size,
      height: size,
      child: IconButton(
        focusNode: focusNode,
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          iconSize: iconSize ?? size / 2,
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
        ),
      ),
    ),
  );
}
