import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:material_ui/material_ui.dart';

/// 把"只能点"的控件接进手柄体系：确定键 = 点击，Y 键 = 次要点击，外加焦点环。
///
/// 播放器里绝大多数控件都是 `GestureDetector`（不是 `InkWell`/`ButtonStyleButton`），
/// 框架不会给它们发 `ActivateIntent`，所以得在这里补一个 [Actions]——注意
/// 它必须是 [Focus] 的**祖先**：`Actions.invoke` 是从焦点所在的 element 往上找的。
///
/// 它不画任何视觉，只是焦点外壳；`Pref.tvFocus` 关掉时原样返回 [child]。
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.autofocus = false,
    this.focusNode,
    this.debugLabel = 'TvButton',
  });

  final Widget child;

  /// 确定键（手柄 A / 遥控器确定 / 回车 / 空格）。
  final VoidCallback? onTap;

  /// Y 键（手柄）/ 菜单键（遥控器）/ 鼠标右键。
  final VoidCallback? onSecondaryTap;

  final bool autofocus;
  final FocusNode? focusNode;
  final String debugLabel;

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) {
      return child;
    }
    return FocusRing(
      focusNode: focusNode,
      debugLabel: debugLabel,
      radius: TvFocusSpec.playerRadius,
      borderWidth: TvFocusSpec.playerBorderWidth,
      scale: TvFocusSpec.playerScale,
      // 播放器控件的预选框是**圆形**的（对齐电视端"圆形预选框"的手感）：
      // 播放器按钮都是 30~42 见方的小方块，圆角矩形看着像在框一个按钮，
      // 圆形看着像在"Hover 这一颗"。视频页和直播页一致。
      circle: true,
      // 没有确定键行为就没什么可停的（例如占位用的空按钮）
      canRequestFocus: onTap != null,
      onKeyEvent: (node, event) {
        if (onSecondaryTap != null && TvKeys.isMore(event)) {
          if (TvKeys.isFirstPress(event)) {
            onSecondaryTap!();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      builder: (context, node, focused) => Actions(
        actions: <Type, Action<Intent>>{
          if (onTap != null)
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onTap!();
                return null;
              },
            ),
        },
        child: Focus(
          focusNode: node,
          autofocus: autofocus,
          debugLabel: debugLabel,
          child: child,
        ),
      ),
    );
  }
}
