import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 手柄上的滑块（音量、倍速、字号、颜色……）。
///
/// 框架的 `Slider` 在 traditional 导航模式下把**四个**方向键全绑成"调节"
/// （`slider.dart` 的 `_traditionalNavShortcutMap`），于是手柄一旦停在滑块上，
/// 方向键就再也走不出去——按上/下是调值，按左/右还是调值。
///
/// 这里把这一格单独切成 [NavigationMode.directional]：框架只绑左右键，
/// 上下键留给"走出这一格"（`slider.dart` 的注释原文就是
/// "The vertical inputs are not handled to allow navigating out of the slider"）。
/// 触摸、鼠标完全不受影响（快捷键映射只作用于键盘按键）。
///
/// 滑块的焦点视觉是它自带的（拇指高亮 + 光圈），不再叠 [FocusRing]：
/// 滑块没有可以直接接管的 `FocusNode`（`Slider.focusNode` 是内部创建的），
/// 硬套反而会把节点的所有权搞乱。
class TvSlider extends StatelessWidget {
  const TvSlider({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return child;
    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(navigationMode: NavigationMode.directional),
      child: child,
    );
  }
}
