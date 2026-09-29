import 'package:PiliPlus/common/widgets/focus/tv_input_mode.dart';
import 'package:PiliPlus/common/widgets/focus/tv_nav_bar.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/focus/tv_tab_bar.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 返回键在**页面内部**先退一级（`appBack()` 里排在拦截栈和弹窗之后、退路由之前）。
///
/// 手柄 B / 遥控器返回 / 键盘 Esc 按下去，用户想的不一定是"离开这一页"，更常见的是
/// "退一级"。所以从里往外排了三档，任何一档做成了这一下返回就用掉，一档都做不了
/// 才去退页面：
///
/// 1. **内容区 → 顶部标签栏**：焦点在列表 / 网格里（[TvRegions.inContentRegion]）
///    且这一页有标签栏时，焦点回到栏上**当前选中的那一栏**（[TvTabBarHandle]）
///    ——和方向键"从内容按 ↑ 进栏"的落点是同一条（见 `TvTabEntryLock`），
///    用户看到的就是"预选框回到了顶上那一栏"；
/// 2. **标签栏 → 默认栏**：焦点已经在栏上（[TvTabBars.nearestToFocus]，任意一栏）
///    时切回这一页的**默认栏**（[TvTabBarHandle.defaultIndex] = 这条栏**打开时**
///    选中的那一栏，不是硬编码的第 0 栏）；
/// 3. **默认栏 → 导航栏所选项**：已经在默认栏上了就往下够，把焦点交给主界面
///    导航栏里当前选中的那一格（底栏 / 平板侧栏，见 [TvNavBar]；它不在视口里
///    就不送）。
///
/// 三档都做不了（焦点不在内容区、这一页没标签栏、导航栏看不见）返回 false，
/// 返回键照旧往下走：首页的"回首页"、安卓返回键退出那一套都在 `appBack()` 的
/// 下一档里，一个字都不用改。
///
/// **门槛：只有按键来的那一下才算**（[TvInputMode.fromKeys]）。鼠标用户点完东西
/// 按 Esc、或者按鼠标侧键，期望的是退页面，不该被这三级截走——鼠标侧键那一下是
/// `PointerDownEvent`，"最近一次交互是不是指针"正好判得出来。于是触摸 / 鼠标用户
/// 完全不受影响，这条阶梯只长在手柄 / 遥控器 / 键盘身上。
///
/// 为什么落点全用"当前选中的那一栏 / 那一格"而不是"第一栏 / 第一格"：这两级都是
/// **退回去**，用户回到的是"我刚才在哪儿"，不是"这一页的起点"。
abstract final class TvFocusBack {
  /// 处理一次返回键；返回 true 表示这一下已经被页面内部用掉了（别再退页面）。
  static bool handle() {
    if (!Pref.tvFocus || !TvInputMode.fromKeys) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (_toPageTabBar(focus)) return true;
    return _fromTabBarToNavBar();
  }

  /// 第 1 档：内容区 → 这一页的顶部标签栏，落在**当前选中的**那一栏上。
  static bool _toPageTabBar(FocusNode? focus) {
    if (!TvRegions.inContentRegion(focus)) return false;
    // 焦点已经在某条标签栏上时这一档不成立（那是第 2 档的事）。区域种类本该
    // 说明这件事，但标签栏区域的登记方不一定标了 kind（竖排那条就没标），
    // 所以这里再按"栏"查一遍，不靠登记方自觉。
    if (TvTabBars.nearestToFocus() != null) return false;
    final bar = TvTabBars.onPageOf(focus);
    final selected = bar?.selectedIndex;
    if (bar == null || selected == null) return false;
    return bar.focusTab(selected);
  }

  /// 第 2、3 档：焦点在标签栏上 → 默认栏；已经在默认栏 → 导航栏所选项。
  static bool _fromTabBarToNavBar() {
    final bar = TvTabBars.nearestToFocus();
    if (bar == null) return false;
    // 焦点浮在栏的区域上（不在任何标签上）时 `focusedIndex` 为 null，
    // 也按"还没到默认栏"处理：送过去就是落回默认栏
    final target = bar.defaultIndex;
    if (target != null && bar.focusedIndex != target && bar.focusTab(target)) {
      return true;
    }
    // 已经在默认栏上了（或者这一页只有那一栏）：焦点往下够到导航栏所选项。
    // 栏上按返回而导航栏又看不见（侧栏被收起、底栏滑出去了）时返回 false——
    // 这一下返回继续往下走，交给"退页面 / 回首页"。
    return TvNavBar.focusSelected();
  }
}
