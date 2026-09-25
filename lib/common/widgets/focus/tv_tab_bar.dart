import 'dart:async';

import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 顶部标签栏的手柄 / 遥控器适配：直接替换 `TabBar` 用。
///
/// 参数和 `TabBar` 完全一样，只是多一个 [regionLabel]。它做四件事：
///
/// 1. 给每个标签一个**自己的** [FocusNode]。框架的 `TabBar` 不给这个口子
///    （每个标签就是一个 `InkWell`，节点由它自建），所以是配合
///    `lib/scripts/material/tabs.patch` 里的 `buildTabFocusNode` 用的。
/// 2. 用 [FocusRing] 画预选框：1.04 倍缩放 + 2dp 主题色描边 + 一层淡淡底纹
///    （blbl 的 `blbl_focus_scale` + `blbl_focus_bg_round`），比 `InkWell`
///    自带的那点 `focusColor` 明显得多。
/// 3. 焦点落到某个标签上就立刻切到那一栏（对齐 blbl 的
///    `tabSwitchFollowsFocus`），可以在设置里关掉（`Pref.tabSwitchOnFocus`）。
/// 4. 把整条标签栏包成一个 [TvRegion]，于是 L1/R1 在**任何**页面都能切栏
///    （见 [TvTabBars]；页面自己声明的 `TvSectionSwitcher` 优先）。
/// 5. **进栏锁**：焦点从栏外进到标签栏上时，落点固定在当前选中的那一栏
///    （见 [TvTabEntryLock]）——方向键是几何寻焦，它只会落到正上方那个标签上，
///    于是"在第三栏的内容里按 ↑"会跳到第三栏的预选框、甚至把页面切走。
///
/// `Pref.tvFocus` 关掉时整条路径都是空操作：不建焦点节点、不画预选框、
/// 不包区域，结构退回成和原来的 `TabBar` 一模一样。
class TvTabBar extends TabBar {
  const TvTabBar({
    super.key,
    required super.tabs,
    required this.regionLabel,
    super.controller,
    super.scrollController,
    super.isScrollable,
    super.padding,
    super.indicatorColor,
    super.automaticIndicatorColorAdjustment,
    super.indicatorWeight,
    super.indicatorPadding,
    super.indicator,
    super.indicatorSize,
    super.dividerColor,
    super.dividerHeight,
    super.labelColor,
    super.labelStyle,
    super.labelPadding,
    super.unselectedLabelColor,
    super.unselectedLabelStyle,
    super.dragStartBehavior,
    super.overlayColor,
    super.mouseCursor,
    super.enableFeedback,
    super.onTap,
    super.onHover,
    super.onFocusChange,
    super.physics,
    super.splashFactory,
    super.splashBorderRadius,
    super.tabAlignment,
    super.textScaler,
    super.indicatorAnimation,
    this.switchOnFocus,
    this.onFocusTab,
  });

  /// 焦点区域标签，见 [TvRegion.debugLabel]。**同一个页面里要唯一**，
  /// 否则 `TvRegions.focusFirst` 会找错地方。
  final String regionLabel;

  /// 焦点落到标签上时是否立刻切到那一栏；不传则实时读 [Pref.tabSwitchOnFocus]。
  final bool? switchOnFocus;

  /// 覆写"焦点即切换"的动作。
  ///
  /// 给"标签不是换页而是滚到某个区块"的页面用（视频详情页）：这样点标签和
  /// 焦点落在标签上执行的是同一件事。不传则用 `TabController.animateTo`。
  final ValueChanged<int>? onFocusTab;

  @override
  State<TabBar> createState() => TvTabBarState();
}

class TvTabBarState extends TabBarState implements TvTabBarHandle {
  TvTabBar get _tabBar => widget as TvTabBar;

  /// 每个标签的焦点节点（下标就是标签下标）。
  ///
  /// 只增不减、只在 [dispose] 里销毁：标签数量变少时（视频页重建
  /// `TabController`）那些节点已经不在树上，销毁它们等于在别人的
  /// `Focus` 还挂着的时候把节点废掉，不值得为这点内存冒险。
  final List<FocusNode> _nodes = [];

  /// 进栏锁，见 [TvTabEntryLock]。
  late final TvTabEntryLock _entryLock = TvTabEntryLock(
    nodes: () => _nodes,
    selected: () => _effectiveController?.index,
  );

  @override
  void dispose() {
    _entryLock.dispose();
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes.clear();
    super.dispose();
  }

  /// 拿到这一栏的 `TabController`。
  ///
  /// 有的页面（PGC 索引、充电榜）用的是 `DefaultTabController`，没有现成的
  /// 控制器可传，所以要从上下文里取。每次都现取：`DefaultTabController` 和
  /// `TabBar.controller` 都可能在重建时被换掉（视频页就是这么干的）。
  TabController? get _effectiveController {
    final controller = widget.controller;
    if (controller != null) return controller;
    if (!mounted) return null;
    return DefaultTabController.maybeOf(context);
  }

  /// 第 [index] 个标签的焦点节点；不需要（没开手柄模式 / 越界）时返回 null。
  FocusNode? _nodeAt(int index) {
    if (!Pref.tvFocus) return null;
    if (index < 0 || index >= _tabBar.tabs.length) return null;
    while (_nodes.length <= index) {
      final i = _nodes.length;
      final node = FocusNode(debugLabel: '${_tabBar.regionLabel}[$i]')
        ..addListener(() => _handleTabFocus(i));
      _nodes.add(node);
    }
    return _nodes[index];
  }

  void _handleTabFocus(int index) {
    if (!mounted) return;
    if (!_nodes[index].hasFocus) {
      _entryLock.onBlurred();
      return;
    }
    // 从栏外进来：落点锁在当前选中的那一栏，不做别的
    // （这里必须先于"焦点即切换"判断，否则预选框会先按位置跳一下再被拉回来）
    if (_entryLock.shouldLandOnSelected(index)) {
      final target = _effectiveController?.index;
      if (target != null) focusTab(target);
      return;
    }
    if (!(_tabBar.switchOnFocus ?? Pref.tabSwitchOnFocus)) return;
    final onFocusTab = _tabBar.onFocusTab;
    if (onFocusTab != null) {
      onFocusTab(index);
      return;
    }
    final controller = _effectiveController;
    if (controller == null || controller.index == index) return;
    controller.animateTo(index);
  }

  @override
  void focusTab(int index) => _nodeAt(index)?.requestFocus();

  @override
  bool switchBy(int offset) {
    final controller = _effectiveController;
    if (controller == null) return false;
    final target = controller.index + offset;
    if (target < 0 || target >= controller.length) return false;
    controller.animateTo(target);
    // 等这一帧把新栏建出来，下一帧再把焦点送过去（和首页 `_switchTab` 同一套）；
    // 焦点一落上去，"焦点即切换"那条路也会跑到，这里是提前把焦点摆好，
    // 免得用户看到"栏切了但预选框还留在原来那一栏"。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusTab(target);
    });
    return true;
  }

  // 补丁里 `_TabBarState` 暴露的三个扩展点。

  @override
  FocusNode? buildTabFocusNode(int index) => _nodeAt(index);

  @override
  Widget buildTabShell(int index, Widget child) {
    final node = _nodeAt(index);
    // 没开手柄模式：`child` 原样返回，`InkWell` 自己建节点
    if (node == null) return child;
    return FocusRing(
      focusNode: node,
      radius: TvFocusSpec.tabRadius,
      fillColor: ColorScheme.of(
        context,
      ).primary.withValues(alpha: TvFocusSpec.tabFillAlpha),
      debugLabel: '${_tabBar.regionLabel}[$index]',
      builder: (_, _, _) => child,
    );
  }

  @override
  Widget buildTabBarRoot(Widget child) => TvRegion(
    debugLabel: _tabBar.regionLabel,
    // 标成标签栏：进页面时预选框该落到内容区，内容区还没建出来才退到这条栏上
    // （见 `TvRegions.entryNodeFor`）
    kind: TvRegionKind.tabBar,
    child: child,
  );
}

/// 进栏锁：焦点**从栏外进到标签栏上**时，落点固定在当前选中的那一栏。
///
/// 方向键走的是几何寻焦，它只认位置：从内容区按 ↑ 会落到正上方那个标签上。
/// 于是"在第三栏的内容里按 ↑"看到的预选框跳到了第三栏——几何上没错，但手柄
/// 用户想的是"回到标签栏"，落点自然该是当前那一栏（顺便还会触发一次切换，
/// 也就是"手都没碰标签，页面自己跳走了"）。所以进栏一律锁过去。
///
/// **栏内**的 ←/→ 不能锁：那时候本来就该按位置在标签之间走，锁住就动不了了。
/// 区分办法是"这一批焦点变化**之前**，栏里有没有焦点"——注意不能直接问"还有
/// 没有兄弟节点持有焦点"：`requestFocus` 是延迟到 microtask 才生效的，监听器
/// 被调到的时候这一批已经全部应用完了，栏内移动的旧节点早就失焦，那样每次
/// 栏内移动都会被误判成"从外面进来"。所以进栏读的是上一次记下的值，出栏之后
/// （下一个 microtask，那时栏里确实没人了）才复位。
class TvTabEntryLock {
  TvTabEntryLock({required this.nodes, required this.selected});

  /// 本栏的标签焦点节点，下标就是标签下标。
  final List<FocusNode> Function() nodes;

  /// 当前选中的标签下标；拿不到控制器时返回 null。
  final int? Function() selected;

  /// 这一批焦点变化**之前**，栏里是不是已经有焦点。
  bool _inside = false;
  bool _disposed = false;

  /// 在标签节点**拿到**焦点时调。返回 true 表示这次落点要改成"当前选中的
  /// 那一栏"：调用方把焦点挪过去即可，别再做别的（尤其别执行"焦点即切换"，
  /// 那会让预选框按位置先跳一下再被拉回来）。
  ///
  /// 栏内移动、落点本来就是选中那栏、拿不到控制器时都返回 false。
  bool shouldLandOnSelected(int index) {
    final wasInside = _inside;
    _inside = true;
    if (wasInside) return false;
    final target = selected();
    return target != null && target != index;
  }

  /// 在标签节点**失去**焦点时调。栏里还有别的标签接着（栏内移动）就不算出去。
  void onBlurred() {
    scheduleMicrotask(() {
      if (_disposed) return;
      if (!nodes().any((node) => node.hasFocus)) _inside = false;
    });
  }

  void dispose() => _disposed = true;
}

/// 标签栏对"外部切栏请求"暴露的能力。
abstract interface class TvTabBarHandle {
  /// 把焦点送到第 [index] 个标签上（顺带触发"焦点即切换"）。
  void focusTab(int index);

  /// 相对当前栏切 [offset] 栏（`-1` 上一栏 / `+1` 下一栏），焦点跟着走。
  ///
  /// 返回 false 表示越界或者拿不到控制器——按键已经被消费掉了，
  /// 调用方不用再做别的。
  bool switchBy(int offset);
}

/// 找"焦点现在所在的标签栏"。
///
/// [TvSectionSwitcher] 是页面**主动声明**的切栏动作（首页要在切栏之后把焦点
/// 送进新栏的第一张卡、视频页是滚到对应的区块），有它就先听它的；页面没声明
/// 时走这里，让 L1/R1 在任何一个有 [TvTabBar] 的页面都能切栏，不用逐页写样板。
///
/// 不需要注册表：从当前焦点往上走，第一个碰到的标签栏就是**最内层**那一个
/// （页面里套标签栏的情况，例如播放器面板里的标签栏，也能正确定位）。
abstract final class TvTabBars {
  /// 从当前焦点往上找最近的一个标签栏；焦点不在任何标签栏里时返回 null。
  static TvTabBarHandle? nearestToFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    TvTabBarHandle? found;
    context.visitAncestorElements((element) {
      // 声明成 Object?：`is` 只在"目标类型是被测类型的子类型"时才窄化，
      // 而 `State<StatefulWidget>` 和 `TvTabBarHandle` 是两棵树上的人
      final Object? state = element is StatefulElement ? element.state : null;
      if (state is TvTabBarHandle) {
        found = state;
        // 越往上越外，第一个命中的就是最内层的
        return false;
      }
      return true;
    });
    return found;
  }

  /// 切到上一栏 / 下一栏。返回 false 表示焦点不在标签栏里，或者已经到头了。
  static bool switchSection({required bool prev}) =>
      nearestToFocus()?.switchBy(prev ? -1 : 1) ?? false;
}
