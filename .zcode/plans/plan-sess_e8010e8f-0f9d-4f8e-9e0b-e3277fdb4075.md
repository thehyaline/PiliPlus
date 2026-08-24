## 需求 1:正在直播板块与动态列表的衔接

**根因**:动态列表使用自定义瀑布流 delegate(`lib/utils/waterfall.dart` 的 `SliverWaterfallFlowDelegateWithMaxCrossAxisExtent`)。当设置了"动态列表最大列数"且实际列数受限时,`getCrossAxisOffset`(waterfall.dart:131-143)会把卡片网格**整体水平居中**,导致板块与卡片之间出现大片空白,板块看起来"绑定在屏幕边缘"。板块与列表容器本身是紧贴的(0 间距),卡片与板块之间的 12px 间距来自动态列表自身的 `SliverPadding`(left/right 12),用户希望保留这 12px。

**改动**:

1. `lib/utils/waterfall.dart`
   - `SliverWaterfallFlowDelegateWithMaxCrossAxisExtent` 新增字段 `final LivePanelPosition? alignTo`(import `live_panel_position.dart`),构造参数可选。
   - `getCrossAxisOffset`:列数受限时,居中偏移 `remaining` 按 `alignTo` 处理 —— `left` 时不加偏移(靠左),`right` 时加 `remaining * 2`(靠右),`null` 保持居中。
   - `shouldRelayout` 增加 `alignTo` 比较,保证切换设置时重排。
   - `DynMixin` 中保留原 `dynGridDelegate`(默认居中,其他页面如会员动态、我的回复等不受影响),新增 `dynGridDelegateOf({LivePanelPosition? alignTo})` 带参版本。

2. `lib/pages/dynamics_tab/view.dart`
   - `_buildBody` 的 `SliverWaterfallFlow` 改用 `dynGridDelegateOf(alignTo: ...)`:
     - 板块显示时(`dynamicsController.livePanelPosition.value != hidden && context.showNavbar`)传 `livePanelPosition`,卡片区域靠板块一侧对齐,与板块保持 12px 间距;
     - 否则传 `null`,恢复居中。
   - `_buildBody` 已在 `Obx` 中(`view.dart:60`),设置变化时自动重建 delegate。

## 需求 2:正在直播板块底部留空隙

**参考** `lib/pages/mine/view.dart:97-102` 的 bottomPad 逻辑:导航栏在底部(非侧边栏且竖屏)时留固定空隙,否则移动端仅留系统手势条高度,桌面端为 0。

**改动**:

1. `lib/pages/dynamics/view.dart` —— `livePanelPart` 中计算 bottomPad(与 mine 页条件一致,import `platform_utils.dart`):
   ```dart
   final double bottomPad =
       !_mainController.useSideBar && MediaQuery.sizeOf(context).isPortrait
       ? 100
       : PlatformUtils.isMobile
       ? MediaQuery.viewPaddingOf(context).bottom
       : 0;
   ```
   数值用 100(与动态列表底部 `SliverPadding` 的 `bottom: 100` 一致,保证板块与列表底部对齐;mine 页的 152 含"两板块 200→174 缩减"的补偿,板块无此补偿)。`livePanelPart` 在 `Obx` builder 内调用,`MediaQuery.sizeOf` 会注册依赖,窗口缩放时自动重建。
   - 将 bottomPad 作为新参数传给 `LivePanelSection`。

2. `lib/pages/dynamics/widgets/live_panel_section.dart`
   - 新增 `final double bottomPad;` 参数(默认 0 或必填,跟随现有 `position` 参数风格)。
   - Padding 的 `EdgeInsets.only` 增加 `bottom: bottomPad`。Column 是 `mainAxisSize.min`,内容不足或超长时底部空隙都能保留。

## 验证方式

- `flutter analyze` 通过。
- 手动场景:设置"动态列表最大列数"(如 4)+ 板块左侧 → 卡片靠左对齐,与板块间约 12px;板块右侧 → 卡片靠右对齐;板块隐藏或窗口 < 800 → 卡片恢复居中;宽屏竖窗(底部导航栏)时板块底部留空隙,横屏桌面端无多余留白。