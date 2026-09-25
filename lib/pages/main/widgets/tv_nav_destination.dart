import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/pages/main/widgets/tablet_nav_item.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 给**框架自己搭的**导航项套焦点预选框（`NavigationBar` / `NavigationRail`
/// 的 destination，见 `pages/main/view.dart`）。
///
/// 和 `TabletNavItem` 只差一件事：那一个是自己搭的格子，`FocusRing` 的节点
/// 直接交给里面的 `InkWell`（准则 1「一个卡片一个焦点节点」）；这两支是
/// **框架的控件**，内部那个 `InkWell` 自己建焦点节点（框架的 `wrapChild` 没留
/// 扩展点，和 `TabBar` 是同一类问题），外面拿不到。
///
/// 所以这里换个挂法：把 [FocusRing] 的节点当成一层**外壳**套在 destination
/// 外面，描边和底纹就画在这一格的矩形上，真正接住焦点的还是里面框架那个
/// `InkWell`。这一招成立是因为 `FocusNode.hasFocus` 的语义是"**自己或子树里**
/// 持有焦点"（`focus_manager.dart`：`primaryFocus.ancestors.contains(this)`）——
/// 焦点落在里面的 `InkWell` 上时，外壳节点照样算 `hasFocus`，环就亮。
///
/// 外壳节点只是"环的挂点"，不该成为落点，所以 `canRequestFocus: false`：
/// 方向键遍历（`traversalDescendants` 按这个标志筛）和 `focusAt`（鼠标点击）
/// 都会跳过它，确定键也仍然由里面的 `InkWell` 走框架的 `ActivateIntent`，
/// 焦点行为一点没变。顺手 `Theme.focusColor = transparent` 压掉框架自带的
/// 那层 focus 底纹，视觉统一交给 [FocusRing]（和 `listTileFocusRing` 同一个理由）。
///
/// 形状沿用抽屉导航项那一套：16dp 圆角 + 12% 主题色底纹
/// （[tabletNavTileRadius]，blbl 的 `blbl_focus_bg_round.xml`）——底栏、侧栏、
/// 抽屉里的"一格 tab"是同一个东西，形状该一致。
class TvNavDestination extends StatelessWidget {
  const TvNavDestination({
    super.key,
    required this.debugLabel,
    required this.child,
    this.scale = TvFocusSpec.scale,
  });

  /// 焦点节点的调试标签（排查"焦点停在哪儿"用）。
  final String debugLabel;

  /// 框架的 destination 本体。
  final Widget child;

  /// 聚焦时的缩放倍数，见 [FocusRing.scale]。
  ///
  /// 底栏那一格上下都贴着栏边（选中的那一格更是紧贴屏幕底边），放大 4% 会把
  /// 描边和 12% 底纹顶到栏外面去，所以底栏传 1.0；默认值留给"四周有余量"的
  /// 位置（抽屉里的导航项就是这个手感）。
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return child;
    return FocusRing(
      debugLabel: debugLabel,
      radius: tabletNavTileRadius,
      scale: scale,
      fillColor: ColorScheme.of(
        context,
      ).primary.withValues(alpha: TvFocusSpec.tabFillAlpha),
      // 环的挂点，不是落点：能聚焦的是里面框架那个 InkWell（见类说明）
      canRequestFocus: false,
      builder: (context, node, _) => Focus(
        focusNode: node,
        canRequestFocus: false,
        child: Theme(
          data: Theme.of(context).copyWith(focusColor: Colors.transparent),
          child: child,
        ),
      ),
    );
  }
}
