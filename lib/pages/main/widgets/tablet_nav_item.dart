import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 平板抽屉导航项的圆角：**焦点环和选中指示条共用这一个常量**
/// （`_sideBar()` 也把它传给 `NavigationDrawerTheme.indicatorShape`），
/// 改一处两边一起变。
const tabletNavTileRadius = BorderRadius.all(Radius.circular(16));

/// 平板导航栏（设置项「优化平板导航栏」，`optTabletNav`）里的一枚导航项
/// （首页 / 动态 / 我的）。
///
/// 为什么不用框架的 [NavigationDrawerDestination]：那个 destination 内部的
/// `InkWell` **自己建焦点节点**，外面拿不到（框架的 `wrapChild` 没留扩展点，
/// 和 `TabBar` 是同一类问题），于是焦点预选框画不出来。而
/// [NavigationDrawer.children] 官方就允许混自定义控件（"and/or customized
/// widgets like headlines and dividers"），所以这条路不需要动 material 的补丁
/// ——补丁要重新套一遍 pub 缓存才生效，能用应用层解决就不走它。
///
/// 复刻的部分都贴着框架的写法，版面和手感不变：
/// - 选中指示条直接用框架的 [NavigationIndicator]，连那条 500ms 的横向展开
///   动画（框架里是 `wrapChild` 的 `_SelectableAnimatedBuilder`）一起搬过来；
/// - 图标 / 文字 / 指示条的颜色和尺寸都读 [NavigationDrawerTheme]，页面上那份
///   `NavigationDrawerTheme` 仍是唯一的出处（[icon] 走 `IconTheme.merge`、
///   [label] 走 `DefaultTextStyle`，和框架的 destination 一样）；
/// - `tilePadding`（`symmetric(vertical: 5, horizontal: 12)`）与
///   `tileHeight`（56）保持框架默认值。
///
/// 多出来的是焦点态：[FocusRing] 给圆角矩形描边 + 12% 底纹 + 1.04 倍缩放
/// （blbl 的 `item_sidebar_nav.xml`：10dp 圆角 + 2dp 描边只在聚焦时出现 +
/// `blbl_focus_scale`）。形状是圆角矩形而不是圆形——这一枚是"一整格 tab"，
/// 圆形环只留给头像 / 消息 / 搜索那几颗圆按钮。
///
/// 环**只框住格子本体**（那 56 高的 [SizedBox]，也就是选中指示条那 72×56 的
/// 范围），框架的 `tilePadding` 留在环外面：这样描边正好压在指示条的边上、
/// 12% 底纹就是这一枚自己的背景色（"预选框框住各自的背景色"），放大 4% 多出来
/// 的 1.4dp 也落在留白里，不会被抽屉视口裁掉两侧。
class TabletNavItem extends StatefulWidget {
  const TabletNavItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
    this.debugLabel = 'TabletNavItem',
  });

  final String label;

  /// 未选中 / 选中时的图标（动态页的未读角标在外面套好再传进来）。
  final Widget icon;
  final Widget selectedIcon;

  final bool selected;
  final VoidCallback onTap;

  /// 焦点节点的调试标签（排查"焦点停在哪儿"用）。
  final String debugLabel;

  @override
  State<TabletNavItem> createState() => _TabletNavItemState();
}

class _TabletNavItemState extends State<TabletNavItem>
    with SingleTickerProviderStateMixin {
  /// 选中指示条的展开动画。时长对齐框架 destination 的那一条
  /// （`_SelectableAnimatedBuilder(duration: 500ms)`，缓动交给
  /// [NavigationIndicator] 自己那两段曲线）。
  late final AnimationController _selected = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.selected ? 1.0 : 0.0,
  );

  @override
  void didUpdateWidget(TabletNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    widget.selected ? _selected.forward() : _selected.reverse();
  }

  @override
  void dispose() {
    _selected.dispose();
    super.dispose();
  }

  /// 格子的外圈留白，框架的 `tilePadding` 默认值。
  ///
  /// 它留在 [FocusRing] **外面**，于是环只框住 56 高的格子本体——也就是选中
  /// 指示条那 72×56 的范围，描边恰好压在指示条的边上（见 [build]）；
  /// 同时它还兼作缩放余量：1.04 倍只多出 1.4dp，5/12 的留白装得下。
  static const _tilePadding = EdgeInsets.symmetric(vertical: 5, horizontal: 12);

  /// 格子本体：选中指示条 + 图标 + 文字，不含外圈的 [_tilePadding]。
  ///
  /// [focusNode] 为 null 时（手柄模式关掉）由内部控件自己建节点。
  Widget _tile(BuildContext context, FocusNode? focusNode) {
    final colorScheme = ColorScheme.of(context);
    final drawerTheme = NavigationDrawerTheme.of(context);
    final states = <WidgetState>{if (widget.selected) WidgetState.selected};
    final indicatorSize = drawerTheme.indicatorSize ?? const Size(336.0, 56.0);
    final indicatorShape =
        drawerTheme.indicatorShape ??
        const RoundedRectangleBorder(borderRadius: tabletNavTileRadius);

    return Semantics(
      selected: widget.selected,
      container: true,
      child: SizedBox(
        height: drawerTheme.tileHeight ?? 56.0,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            focusNode: focusNode,
            // 焦点视觉由 FocusRing 负责（同 TvCard）
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            customBorder: indicatorShape,
            onTap: widget.onTap,
            child: Stack(
              alignment: Alignment.center,
              children: [
                NavigationIndicator(
                  animation: _selected,
                  // 不传的话指示条会退成 `ColorScheme.secondary`，
                  // 而抽屉的默认值是 `secondaryContainer`（框架那份 defaults
                  // 是私有的，拿不到）
                  color:
                      drawerTheme.indicatorColor ??
                      colorScheme.secondaryContainer,
                  shape: indicatorShape,
                  width: indicatorSize.width,
                  height: indicatorSize.height,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTheme.merge(
                      data:
                          drawerTheme.iconTheme?.resolve(states) ??
                          const IconThemeData(size: 28),
                      child: widget.selected
                          ? widget.selectedIcon
                          : widget.icon,
                    ),
                    const SizedBox(height: 4),
                    DefaultTextStyle(
                      style:
                          drawerTheme.labelTextStyle?.resolve(states) ??
                          Theme.of(context).textTheme.labelMedium!,
                      child: Text(widget.label),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = Pref.tvFocus
        ? FocusRing(
            debugLabel: widget.debugLabel,
            radius: tabletNavTileRadius,
            // 底纹（blbl 的 `blbl_focus_bg_round`）与顶部标签栏同一档不透明度
            fillColor: ColorScheme.of(
              context,
            ).primary.withValues(alpha: TvFocusSpec.tabFillAlpha),
            builder: (context, focusNode, _) => _tile(context, focusNode),
          )
        // 手柄模式关掉时一个节点都不多（准则 6「默认零侵入」）
        : _tile(context, null);

    return Padding(padding: _tilePadding, child: tile);
  }
}
