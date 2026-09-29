import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 主界面导航栏（底栏三支 / 平板侧栏）的登记表：给返回键一个"退到最后一级"的落点。
///
/// 登记的只有一件事——**第 index 格该把焦点送到哪个节点上**（[register]）。
/// 各写法各自登记各的：
///
/// - M3 底栏（`TvNavDestination`，默认写法）：登记的是**外壳**节点
///   （`canRequestFocus: false`，见那个类的说明）。真正接住焦点的是框架
///   destination 内部那个 `InkWell`，所以 [focusItem] 要往下钻一层；
/// - 平板侧栏（`TabletNavItem`）：登记的就是格子自己（`FocusRing` 的节点直接
///   交给里面的 `InkWell`）。
///
/// 没登记的两支——`FloatingNavigationBar` 和 M2 的 `BottomNavigationBar`——
/// [focusSelected] 自然返回 false，调用方按"这一步做不了"处理：返回键那一档
/// 直接跳过，退回原来的"退页面 / 回首页"（见 `docs/tv_focus.md` 的「已知省略」）。
///
/// 这一层只回答"**在哪儿**"，不回答"该不该送"：[focusItem] 里那几道有效性检查
/// （在视口里、属于最上面那层路由、画得出来）和别处同一套，见 [TvRegions]。
abstract final class TvNavBar {
  /// 下标 → 那一格。后登记的顶掉先登记的（同一时刻只有一套导航栏活着）。
  ///
  /// **只增不删**：节点的生死由 [FocusRing] 自己管（它在 `dispose` 里销毁
  /// 自己建的节点），这里够不着那个时机。过期的那几条由 [focusItem] 的有效性
  /// 检查挡掉——节点摘下来之后 `isPainted` 为假，送不过去。
  static final Map<int, _NavItem> _items = {};

  /// 登记第 [index] 格。
  ///
  /// [selected] 是"这一格现在是不是选中的那一格"——返回键最后一级要的就是它，
  /// 所以每次 build 都要按当前的选中态重新登记（同一个节点、状态变了要更新）。
  ///
  /// 可以在 `build` 里反复调（同 [TvRegions.registerAnchor]）：内容和状态都没变
  /// 就直接跳过。
  static void register(int index, FocusNode node, {required bool selected}) {
    if (index < 0) return;
    final old = _items[index];
    if (old != null && identical(old.node, node) && old.selected == selected) {
      return;
    }
    _items[index] = _NavItem(node, selected: selected);
  }

  /// 把焦点送到第 [index] 格；返回 false 表示这一格没登记、或者现在送不过去
  /// （不在视口里 / 属于被盖住的路由 / 手柄模式关着）。
  static bool focusItem(int index) {
    if (!Pref.tvFocus) return false;
    final item = _items[index];
    if (item == null) return false;
    final node = item.node;
    if (!TvRegions.isPainted(node) || !TvRegions.isCurrentRoute(node.context)) {
      return false;
    }
    // 不在视口里就不送：底栏是 `AnimatedSlide` 滑出去的（平移不裁剪，
    // `isPainted` 拦不住），送过去等于把预选框画到窗口外面
    final rect = node.rect;
    final viewSize = TvFocusSpec.viewSizeOf(node.context);
    if (viewSize != null && !rect.overlaps(Offset.zero & viewSize)) return false;
    // 外壳节点（M3 destination）自己接不住焦点，往下钻到第一个可聚焦的后代
    var target = node;
    if (!target.canRequestFocus) {
      FocusNode? inner;
      for (final child in node.traversalDescendants) {
        inner = child;
        break;
      }
      if (inner == null) return false;
      target = inner;
    }
    target.requestFocus();
    return true;
  }

  /// 把焦点交给**当前选中**的那一格；没选中态可送（或它看不见）时返回 false。
  ///
  /// "选中的那一格"由登记方说（每一格自己知道 `selectedIndex == index`）：
  /// 底栏和侧栏的选中态来源不同（一个是 `_mainController.selectedIndex`，
  /// 一个还要看平板布局），在这里统一问一遍即可。
  static bool focusSelected() {
    for (final entry in _items.entries) {
      if (!entry.value.selected) continue;
      if (focusItem(entry.key)) return true;
    }
    return false;
  }
}

/// 登记表里的一条：挂点 + 它现在是不是选中的那一格。
class _NavItem {
  const _NavItem(this.node, {required this.selected});

  final FocusNode node;
  final bool selected;
}
