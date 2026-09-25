# 手柄 / 键盘 / 遥控器 焦点准则

本文是 PiliPlus 的 10-foot（TV / 手柄 / 遥控器）交互准则。新增或修改页面时请遵循；
不符合准则的地方，请先在本文补一条规则说明理由，再写代码。

参考实现是 Android 项目 blbl（`E:\Repo\blbl`），它用 1030 行 `DpadGridController`
+ 一套 `blbl_focus_*` 资源实现了同样的目标。**Flutter 已经内建了其中大部分能力，
我们只补缺口**，不要移植 blbl 的控件级焦点控制器。

---

## 0. 先看清楚 Flutter 已经给了什么

以下能力**默认就生效**，不要重复实现：

| 能力 | 实现位置 |
| --- | --- |
| 方向键 = 二维几何寻焦 | `WidgetsApp._defaultShortcuts` 把 `arrowUp/Down/Left/Right` 映射为 `DirectionalFocusIntent`；`ReadingOrderTraversalPolicy` + `DirectionalFocusTraversalPolicyMixin.inDirection()` 做矩形比较 |
| 确定键 = 激活 | `enter`(Android 66) / `select`(DPAD_CENTER 23) / `gameButtonA`(96) / `space` 都映射为 `ActivateIntent`，`InkWell` 在自己的 `Actions` 里注册了 `ActivateIntent`（`ink_well.dart`） |
| 焦点跟随滚动 | `FocusTraversalPolicy.defaultTraversalRequestFocusCallback` 调用 `Scrollable.ensureVisible` |
| 按键从焦点节点向外派发 | `FocusManager` 从 `primaryFocus` 开始、沿祖先链**由内向外**调 `onKeyEvent`，谁先返回 `handled` 谁说了算。这是"卡片拦截确定键做长按"的依据 |
| 新路由自动接管焦点 | `routes.dart` 的 `_ModalScopeState` → `setFirstFocus(routeScope)`；路由 scope 的方向键逃逸是 `stop`，不会串到下层路由 |
| 触摸 / 按键自动切换高亮 | `FocusManager.instance.highlightMode`：触摸 → `touch`，按键 → `traditional`。等价于 blbl 的 `isInTouchMode` |
| 退出编辑态 | `escape` → `DismissIntent`（`TextField` 已处理）；`tab` → `NextFocusIntent` |

**不要**自己截获方向键做焦点移动，除非准则 2 列出的四类场景。

### 三个必须知道的行为细节

1. **方向键只认几何，且有硬门槛**：找 `right` 时要求候选的 `rect.center.dx >= 当前.rect.right`，
   `down` 要求 `center.dy >= 当前.rect.bottom`（`focus_traversal.dart` 的
   `_sortAndFilterHorizontally/_sortAndFilterVertically`）。
   推论：**在卡片内部、位于卡片矩形之内的子按钮，方向键永远选不中它**，
   只有 Tab（读序遍历）能走进卡片。所以"卡片里有多个焦点"的表现是
   「Tab 乱跳」+「Row 布局里中心点落在封面右侧的按钮被 `→` 选中」。

2. **走到边界默认什么都不发生**：`FocusScopeNode.directionalTraversalEdgeBehavior`
   默认是 `TraversalEdgeBehavior.stop`（`focus_manager.dart` 构造函数默认值），
   `_onEdgeForDirection` 直接 `return false`。手柄上这就像"卡住了"——
   这是"网格最后一排按 ↓ 没反应"的根因，由 `TvRegion` 修掉（准则 2）。

3. **焦点节点销毁后，焦点上浮到包含它的 scope**：`FocusManager._markDetached`
   把 `_primaryFocus` 置空，随后 `FocusScopeNode._removeChild` 让**父 scope 自己**
   接管焦点——在网格里就是 `TvRegion` 的节点；只有连这个 scope 都没了，
   `applyFocusChangesIfNeeded` 才把 `_markedForFocus` 设为 `rootScope`。
   两者都不是"落到旁边的卡片上"。表现就是焦点框消失、方向键要重按几次才回来，
   由 `TvFocusMemory` 修掉（准则 3）。

### 键位词表（Android scan code，见 `keyboard_maps.g.dart`）

| scanCode | LogicalKeyboardKey | 用途 |
| --- | --- | --- |
| 19/20/21/22 | `arrowUp/Down/Left/Right` | 方向 |
| 23 | `select` | 遥控器确定 |
| 66 | `enter` | 键盘/手柄确定 |
| 96 | `gameButtonA` | 手柄 A → 确定 |
| 97 | `gameButtonB` | 手柄 B → **返回** |
| 99/100 | `gameButtonX/Y` | X 未分配；Y → **更多** |
| 102/103 | `gameButtonLeft1/Right1` | L1/R1 → 上一栏 / 下一栏 |
| 104/105 | `gameButtonLeft2/Right2` | L2/R2 → 播放器快退/快进 |
| 82 | `contextMenu` | 遥控器菜单键 → **更多** |
| 108/109 | `gameButtonStart/Select` | 更多 / 返回 |
| 85/87/88/89/90 | `mediaPlayPause / TrackNext / TrackPrevious / Rewind / FastForward` | 媒体键（播放器） |
| 111 | `escape` | 返回（桌面） |

> Android 的 `KEYCODE_BACK`(4) 由系统直接 `popRoute`，**根本不会到达 Flutter 框架**，
> 所以返回键的适配只在桌面（Esc/鼠标侧键）和外接手柄（B）上才有意义。

统一使用 `package:PiliPlus/utils/tv_keys.dart` 里的判定函数，不要在页面里散写
`LogicalKeyboardKey` 比较。注意这些集合都是 `static final` 而不是 `const`：
`LogicalKeyboardKey` 重写了 `==`，`const Set` 装不下它（会报
`const_set_element_not_primitive_equality`）。

---

## 1. 一个卡片 = 一个焦点节点

卡片的封面、标题、UP 主名、角标、卡内按钮**全部**移出焦点树：

```dart
TvCardSubAction(child: 卡内次要按钮)   // 内部就是 ExcludeFocus
```

- 触摸/鼠标照常可点（`ExcludeFocus` 只影响焦点，不影响命中测试）。
- 卡内操作改由**长按确定 / 手柄 Y** 进入（见准则 3）。
- 反面教材：`VideoCardV` 里 `VideoPopupMenu` 自带 `FocusNode`，会让 Tab
  钻进卡片内部（`Row` 布局下还会被 `→` 选中）。
- 例外：**整卡都是可点区域**的横向卡片（`VideoCardH`）里，如果子按钮在视觉上
  明显超出封面范围（例如右侧的「稍后再看」），要么一并 `ExcludeFocus`，
  要么承认它是独立焦点——但一个 cell 的焦点数**不允许超过 2**。

⚠️ 焦点能不能落到卡片上，是 `InkWell` 说了算：它内部那个 `Focus` 的
`canRequestFocus` 取自 `_canRequestFocus = enabled && widget.canRequestFocus`，
而 `enabled`（`isWidgetEnabled`）**只看它自己有没有手势回调**
（`onTap != null || onLongPress != null || ...`）。所以：

- 一个只配了 `onMore` / `onHold` 这类"按键专用"动作、没配 `onTap` 的卡片，
  会被 `InkWell` 判成不可用，`requestFocus()` 静默失败——手柄上就是"这一格怎么按都选不中"。
  `TvCard` 已经给这种情况补了空 `onTap`（见 `_effectiveOnTap`）。
- 反过来，**全无动作的卡片保持不可聚焦**是对的（纯展示的占位格不该被方向键选中）。

⚠️ 但"能聚焦"和"按确定有反应"是两回事：框架的确定键走
`Shortcuts` → `ActivateIntent` → `InkWell.activateOnIntent`，而那个回调**只在
`onTap != null` 时才真的触发**。所以"点击语义全在 `onTapDown` / `onTapUp` 上"的
控件（典型是简介里的点赞键：按下开始计时、抬起按计时长短判定点赞还是三连）
手感就是"能停住、按确定没反应"。修法是在焦点节点上自己接管确定键，
把按下/抬起这一对补给原逻辑（见 `ActionItem._handleKey`）：

| 键 | 行为 |
| --- | --- |
| 确定（短按） | 点赞 / 取消赞 |
| 确定（按住不放） | 三连（进度弧绕着图标转，和触摸长按一致） |
| 焦点被抢走 | 作废这次按下（对齐 `TvCard`，免得松手后莫名其妙三连） |

这里故意**没有**套 `TvCard` 那 500ms 的长按判定：三连的计时在 `TripleMixin`
自己手里（255ms 开始动画、动画走完才真的三连），换一套时长会让触摸和手柄
对同一颗按钮给出两种结果。

### 案例：评论卡片

评论卡是"一个 cell 里塞了七八个按钮"的典型（回复 / 翻译 / 赞 / 踩 / 更多 /
查看 N 条回复……），全塞进焦点树的话，方向键一旦进去就要按七八下才出得来。
做法：

- 卡片根换成 `TvCard`，整块内容套 `TvCardSubAction`（= `ExcludeFocus`）。
  **确定键短按仍是原来的"回复这条评论"**，触摸行为一点没变。
- 卡内那些次要操作挪进**长按确定 / 手柄 Y 弹出的操作面板**：回复、点赞、
  点踩、翻译 / 显示原文、查看 N 条回复，加上原有的置顶 / 删除 / 举报 / 复制等。
  面板项用 `FocusRing` 包 `ListTile(enabled: true, onTap: null)`——
  `ListTile` 保持原有排版和配色，但没有手势回调就**不会多出一个焦点节点**。
- 点赞/点踩在卡片上没了入口，所以把两个动作从按钮里抽出来（`ZanActions`），
  卡片上的按钮和面板共用一份实现。

**为什么**：blbl 的 `item_video_card.xml` 给子按钮全写了 `android:focusable="false"`，
同时把 `android:stateListAnimator="@animator/blbl_focus_scale"` 放在卡片根上。
一个 cell 一个焦点节点，方向键的移动距离才是可预期的。

## 2. 能靠几何就不写代码

只在以下四类场景允许覆写方向键行为：

1. **播放器 OSD** —— 控件是浮动层，几何顺序和视觉顺序不一致，且方向键在控件隐藏时另有语义。
2. **输入框进入/脱出** —— 确定键要切换"导航态/编辑态"。
3. **跨面板顺序** —— 例如视频详情竖屏「封面 → 简介 → 评论」的期望顺序与几何顺序不符。
4. **Tab / 栏切换** —— 左右边沿切换栏目，走 `TvSectionSwitcher`（L1/R1、`[` `]`）。

其余一律交给几何 traversal。

### 区域边界：`TvRegion`

给每块独立导航区域（网格 / 列表 / 顶栏 / 底栏 / 侧栏）套一层 `TvRegion`，
它只做一件事——把方向键逃逸从 `stop` 改成 `parentScope`：

```dart
TvRegion(debugLabel: 'home-grid', child: CustomScrollView(...))
```

于是「网格最后一排按 ↓ → 底栏」「顶栏按 ↑ → 从网格上面绕回来」这类跨区
移动不需要任何代码。**不要套太碎**：`TvRegion` 同时也是 `TvFocusMemory`
定位"焦点现在在哪一块"的锚点。

两个坑：

- `TvRegion` 里的 `FocusScope` 必须带 `skipTraversal: true`。`FocusScopeNode`
  本身也是外层 scope 的 `traversalDescendants` 成员，跨区域找焦点时它会和
  区域里的卡片抢（几何上区域矩形正好覆盖"下一张卡"的位置）。
- **不要**给 `FocusScope` 传 `canRequestFocus: false`。`FocusScopeNode.traversalDescendants`
  在 `!canRequestFocus` 时直接返回空集合，区域内的遍历会整个失效。
  （`Focus`/`FocusScope` 只在显式传参时才覆盖节点的 `canRequestFocus`，
  不传就沿用节点自己的值。）

### 网格底部翻页不用写代码

给滚动视图加 `cacheExtent`，下一行就一直在焦点树里，方向键找得到、
`ensureVisible` 会把它滚进来：

```dart
CustomScrollView(
  scrollCacheExtent: TvFocusSpec.cacheExtent, // 800
  slivers: [...],
)
```

`cacheExtent` 默认 250，只够半行，所以默认表现是"按到最底一行就卡住"
（`stop` 让焦点原地不动，看起来就是没反应）。
（参数名在新版 Flutter 里叫 `scrollCacheExtent`，旧的 `cacheExtent` 已废弃。）

### 切栏之后要把焦点接走

栏切换（L1/R1）走全局层 → 页面自己声明的 `TvSectionSwitcher`：

```dart
TvSectionSwitcher(
  onPrev: () => _switchTab(-1),
  onNext: () => _switchTab(1),
  child: Column(children: [tabBar, Expanded(child: tabBarView(...))]),
)
```

`TvSectionSwitcher` 用 `getInheritedWidgetOfExactType` 从**当前焦点**往上找，
所以它要包住"焦点所在的整个页面"，不是只包 TabBar。

切栏之后**必须**把焦点接走：`TabBarView` 里的页面还活着，焦点仍留在旧栏那张
看不见的卡片上——这时按确定会打开旧栏的视频。做法是给页面里每块区域一个
**唯一标签**，切完栏按标签把焦点送进新栏：

```dart
// 页面：static const tvRegion = 'home-rcmd-grid';
// 首页：HomeTabType.tvRegion 把栏映射到标签，切栏后
TvRegions.focusFirst(region)                    // 送进新栏第一张卡
  ?? TvRegions.focusFirst('home-tabbar', index: target); // 退路：TabBar 上
```

退路是给**还没接手柄适配的栏**（没有 `TvRegion`）和"新栏停在很下面、首项还没被
懒加载构建出来"准备的：焦点落到 TabBar 上看得见，按 ↓ 还能进新栏的列表，
总比留在一张看不见的卡上好。标签要唯一——同一标签同时活着两个区域时，
后登记的会把先登记的顶掉。

标签栏本身不用写这些样板：换成 `TvTabBar`（见「顶部标签栏：`TvTabBar`」）
之后它自带区域，L1/R1 在任何页面都能切栏。

## 3. 焦点必须可见、不消失、能回来

### 可见（焦点预选框）

单元格一律用 `TvCard` 包一层，普通按钮/列表项/标签页用 `FocusRing`，
两者给出同一套视觉：

```
1.04 倍缩放 + 2px 主题色描边，120ms easeOut
```

（对齐 blbl 的 `blbl_focus_scale.xml`：scale 1.04 / duration 120；`blbl_focus_stroke.xml`：2dp 描边。）
描边画在控件**自己的边界内**（`Positioned.fill` + `Border.all`，`strokeAlign` 默认
`inside`），所以描边本身不会被视口裁切，也不存在和邻卡的 z 序问题。
但**缩放是往外顶的**（1.04 倍 = 每边多出控件尺寸的 2%）：控件紧贴某个
`Clip.hardEdge` 的容器的裁剪边时（抽屉、列表视口），顶出去的那一条会被削平。
贴着裁剪边的控件因此要么**留余量**（平板导航项的 `tilePadding`、抽屉头部给头像留的
4dp，见「主界面导航栏（平板抽屉）」），要么给 `FocusRing` 传 `scale: 1.0` 不放大。

### 兜底：包不进去的那些控件（`TvFocusOverlay`）

`FocusRing` 是"谁用谁画"，可框架自己造的控件外面**包不进去**——最典型的是 `AppBar`
自动生成的返回键：它在 `AppBar` 内部新建（`leading ??= BackButton()`），应用层连一个
widget 都插不进去。各处裸写的 `IconButton`（顶栏右上那排操作键）、`CloseButton`、
`PopupMenuItem`、还没换成 `TvTabBar` 的 `TabBar` 也一样。这些地方焦点停上去只剩框架
自带的那层 `focusColor` 底纹（`onSurfaceVariant` 10% 灰），手柄上看着就是**没有预选框**。

于是一处兜底：`TvFocusOverlay`（`common/widgets/focus/tv_focus_overlay.dart`）挂在
`main.dart` 的 `_builder` 里，位置是 `Navigator` **之上**、`Stack` 的**最后一项**
（`Stack` 最后一项盖在最上面，连 `FlutterSmartDialog` 注入的弹层也一起盖住）：

```dart
builder: FlutterSmartDialog.init(..., builder: _builder),
// _builder 的末尾
Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [
  TvShortcuts(child: child),
  const Positioned.fill(child: TvFocusOverlay()),
]),
```

它每帧看一眼 `FocusManager.primaryFocus`，给**没有环**的落点补一圈 2px 主题色描边
（`TvFocusSpec` 的宽度和圆角：方方正正的小控件画圆，其余圆角矩形）。三条边界：

- **已经有环的不画**：`FocusRing` 建出来时把自己的节点登记进 `TvFocusRings`，兜底层
  见到就让位。登记用的是 `hasFocus` 的语义（**焦点落在子树里祖先也算**），所以
  `TvNavDestination` / `TvTextField` 那种"外壳画环、落点在里面的控件"也让得掉。
- **看不见的不画**：先过 `TvRegions.isPainted`，再和祖先里所有**会裁剪**的盒子求交
  （`describeApproximatePaintClip`），列表滚过之后环不会飘到 AppBar 上去。
- **零侵入**：判定直接读 `FocusRing.highlightEnabled`，所以关掉「手柄/遥控器模式」、
  或者这一下是鼠标来的，一个字都不画（准则 6）。

环的位置是**帧末**采的（`addPostFrameCallback`，搭别人已经在出的帧，自己
不请求帧），代价是移动过程中会慢一帧（见「已确认的取舍」）。

**新写的代码该自己套 `TvCard` / `FocusRing` 还是要套**：兜底层是给"包不进去"的地方
收底的，不是免写环的借口——卡片那套自带 1.04 倍缩放、底纹和长按确定，兜底层只有一根
描边，而且它画在屏幕最上层，不参与控件自己的布局。

### 不消失

焦点落在空白处 = 用户以为程序卡死。三个注意点：

- 网格/列表用 `cacheExtent` 撑住下一行（见准则 2）。
- 长列表刷新、加载更多、删除条目时，先**寄存焦点**再改数据，改完**恢复**：

  ```dart
  TvFocusMemory.park();          // 数据要变之前
  ...刷新 / 删除 / 清空重建...
  TvFocusMemory.restore();       // 变完之后（内部会等重建和布局，按帧重试）
  ```

  位置记的是"区域里第几个可聚焦项"，所以页面不需要给卡片编号；
  删掉第 i 项时可以用 `restore(preferIndex: i)`。
  对应 blbl 的 `DpadGridController.parkFocusInRecyclerViewForLoadMore()` /
  `RefreshFocus.parkFocusForDataSetReset()`。
  只有**焦点确实丢了**（为空 / 上浮到区域本身 / 退到根 scope）才会动手，
  用户自己跑到顶栏去了不会被抢回来。
- 焦点的初始落点由**路由级**的入口机制负责，不用逐页写 `autofocus`：
  见下面「进页面的初始落点」。

### 能回来

退栈（B → A）的焦点恢复，框架自己会做**一半**：B 那层的 scope 被拆掉时，A 的
`_focusedChildren` 里还留着"上一次聚焦的那个节点"，框架把它重新点亮。但这只在
**那个节点还挂在树上**时成立——列表刷新过、Key 变了、卡片被删了，框架就只会把
焦点交给 A 的**路由 scope**：预选框不画，方向键也动不了，得先瞎按一下才回来。

所以补了 `TvFocusReturn`（`common/widgets/focus/tv_focus_return.dart`）：push 的
那一刻记下"上一页焦点待着的地方"（节点 + 所在区域 + 在区域里的序号），退回时
按三级往下退：

1. 那个控件还在 → 直接还给它（**从哪儿进的退到哪儿**）；
2. 控件没了（列表重建过）→ 回到**同一块区域里的同一个序号**，位置大差不差；
3. 连区域都没了 → 走 `TvRegions.entryNodeFor` 那套页面入口规则。

调用点在 `TvRouteFocusObserver` 里，而且**只在焦点浮着时**动手：页面里有控件拿着
焦点时不许抢（那是 `autofocus`、`TvFocusMemory` 的选择）。同一条通路也接住了
"页面自己把焦点弄丢"（列表刷新干掉了聚焦的卡片、切栏重建、锚点被拆）。

⚠️ 判"那个控件还在不在"不能看 `context`：框架只在 `FocusNode.attach` 时写它、
`detach` 时**不清**，而那个 element 常常已经被列表复用给同位置的**另一个**节点了
（没给 Key 的 `Column` / `ListView` 是按位置匹配的）。于是"有 context、矩形有限、
还在屏幕里"全是假象，把焦点送过去等于送进虚空——`TvFocusReturn` 还会当成
"归还成功"而收手，预选框就永远浮着。判据是 `TvRegions.isPainted` 里的第一条：
**节点还挂在焦点树上吗**（挂在树上的非 scope 节点必有一个 scope 祖先）。

同一个路由内焦点被重建，仍然归 `TvFocusMemory`（见上一条）。

### 进页面的初始落点：`TvRouteFocusObserver`

换页时框架只做一件事：把焦点 **scope** 交接给新页面
（`FocusScopeNode.setFirstFocus`）。页面里没有任何**控件**拿到焦点，于是：

- 预选框不画（焦点悬在覆盖整屏的路由 scope 上，不属于任何控件）；
- 第一次按方向键时，框架从这个"整屏矩形"开始做几何寻焦，四个方向都出不去，
  只好兜底回到 scope 自身、再往下沉到**树序第一项**——顶栏的返回键。
  表现就是"进了页面焦点就丢了，一按还跑到左上角去"。

修法不在页面上，而在 `TvRouteFocusObserver`（挂在
`GetMaterialApp.navigatorObservers` 上，见 `lib/main.dart`）：换页之后把焦点送到
`TvRegions.entryNodeFor` 算出来的**入口**上。入口的顺序是：

1. 这一页登记的**锚点**（播放器页面：画面那一层，见 `TvLabels`）；
2. 第一个**内容区**（`TvRegion`，默认 `kind: TvRegionKind.content`）的首项；
3. 标签栏区域（`kind: TvRegionKind.tabBar`，`TvTabBar` 自带）的首项——
   内容区还没建出来时的退路（进栏锁会再把它锁到当前那一栏）；
4. 这一页里**不在顶栏**的第一个可聚焦项（没套区域的页面靠这条）。

两条筛选：

- 顶栏（`AppBar` / `SliverAppBar`）里的控件一律不算入口：AppBar 在树序上排在
  内容前面，不排除掉的话任何带返回键 / 搜索键的页面都会把预选框停在顶栏上。
  想指定别的入口（例如顶栏里的搜索框）就给目标 `autofocus`，或者把它套进一个
  `TvRegion`。
- **看不见的**也不算（没有大小、或者和所在区域/整屏不相交）：列表滚过之后树序
  第一项排在视口**上面**，被 `Offstage` / `KeepAlive` 留住的旧页
  （`TabBarView` 里切走的那些）区域还登记着、项却都不在屏幕上——预选框画在这类
  项上，用户看着和"焦点丢了"没区别。一个看得见的都没有时退回树序第一项。
- 兜底那一下**只兜"画在屏幕外、但还有布局"的项**：`Rect` 不是有限值的连一帧都
  不会画出来（`KeepAlive` 把切走的栏收进桶里之后就是这样，尺寸都是 `NaN`），
  选中它等于真把焦点弄丢了。这时返回"这块区域没有入口"，让流程接着去**下一块
  区域**找——所以"切到第 2 栏、再回首页 / 再进动态页"时，入口是第 2 栏的第一条
  动态，而不是留在树上的第 1 栏那张卡。

**不做**的事同样重要（这些都是"页面自己安排的落点"）：

- 页面里已经**有控件**拿到焦点就不动：`autofocus`（搜索框、播放器画面）、
  退栈时框架还给上一页的焦点、`TvFocusMemory` 恢复的位置，全都不碰；
- 页面还没有像样的入口（列表还在加载、这一页只有顶栏）就先不塞——硬塞只会
  停在返回键上。这时候交给按键层：第一次按方向键/确定键由
  `TvRegions.focusRouteEntry` 再试一次，试到了就把预选框摆到入口上并
  **吃掉这一下**（对齐电视上"第一下先亮出光标"的手感），没试到就放行，
  框架行为照旧；
- 路由自己说了 `requestFocus: false`（"别抢焦点"的弹层）就一个指头都别动；
- `Pref.tvFocus` 关掉时整条路径不生效。

它是一条**看护循环**，不是"换页时送一次"：窗口 90 帧（≈1.5 秒，覆盖 pop 动画
收尾 + 列表懒加载），每帧看一眼焦点，落到控件上就收手。窗口里被别的层盖住
（pop 动画还没收尾、上面又开个弹层）只是"不动手"，**不是放弃**——早先的版本
在这里判一句 `!route.isCurrent` 就收手，于是退回 A 之后预选框再也回不来，
用户得先按一下方向键（那条老路现在由 `TvFocusReturn` 接住，见「能回来」）。

⚠️ 动帧序的时候要小心 `autofocus`：它是**帧末的 microtask** 才应用的，
所以 observer 在换页那一帧之后**跳过一帧**再动手。抢在它前面会把页面自己的
`autofocus` 顶掉——`_Autofocus.applyIfValid` 只看"这个 scope 里有没有
`focusedChild`"，被顶掉之后不会再补。跳过的那一帧同时也让退栈的焦点恢复先落地。

## 4. 焦点框只在按键之后出现（输入源跟踪：`TvInputMode`）

**读**高亮模式的地方用 `FocusManager.instance.highlightMode`（`FocusRing` 已经
读了它），不要自己去监听输入类型。触摸用户永远看不到焦点框，触屏设备上甚至
不需要考虑这个开关。

**切**这个模式的地方集中在一处：`TvInputMode`
（`common/widgets/focus/tv_input_mode.dart`，在 `main()` 里 `init()`）。它装两个
全局监听：

- **鼠标 / 触摸板按下** → `highlightStrategy = alwaysTouch`（预选框立刻收起来），
  并且把焦点交给指针底下那个控件（`TvRegions.focusAt`）——"点哪儿焦点在哪儿"，
  接下来按方向键是从点的地方继续，而不是从"上一次键盘停的地方"继续；
- **任何按键按下**（键盘 / 手柄 / 遥控器都走这一条）→ `alwaysTraditional`，
  预选框回来。抬起不算（不然松开手柄时环会闪一下）；
- **手指 / 触控笔按下** → 只切 `alwaysTouch`，**不动焦点**：触屏用户没有方向键，
  而且手指抬起后那个控件可能已经不在树上了。

`FocusRing` 自己监听了高亮模式的变化（`addHighlightModeListener`），所以已经画着
的那个环**当帧就收起来/回来**，不用等下一次焦点变化。

⚠️ **Flutter 3.47 里鼠标点击这两半框架都没做**，别当 bug 再查一遍：
`_HighlightModeManager.handlePointerEvent` 对 `mouse` / `trackpad` 是**空实现**
（上游 PR #162417 有意为之，理由是"鼠标点击不该被当成触摸"），而 `InkWell`
这类控件点击时从不 `requestFocus`。触摸那半边框架照做，我们接管策略之后得
替它做（策略被钉住之后框架那半边就失效了）。

需要问"这一下是按键还是指针"的地方用 `TvInputMode.fromKeys`（主界面切页交接、
`_selectNav` 就是这么判的）。

## 5. UI 为手柄让路

- 网格左右各留 8dp 安全内边距，避免 1.04 倍缩放被视口裁切
  （blbl：`focus_safe_padding_h = 8dp` + RecyclerView `clipChildren="false"`）。
  Flutter 里用 `TvFocusSpec.safeSpace`。
- 卡片间距 ≥ 12dp 时，1.04 倍缩放的溢出不会压到邻卡，**不需要**处理 z 序。
  如果将来把间距改小，必须同时把缩放降到 `间距 / 2 / 卡片尺寸` 以下。
- 必要时可以缩小或隐藏卡内次要按钮——TV 上没人去点 29×29 的三点按钮。
  成批隐藏时用「遥控器适配」开关把整类卡片降级成"一张卡一个焦点"（见「动态卡片」）。
- **"点哪儿都行"的手势要补一个显式入口**。典型是视频简介：整块简介的展开/收起
  挂在外面一个大 `GestureDetector` 上（点哪里都能展开），手柄碰不到它，
  收起状态下正文、BV 号、标签就永远看不见。补一行「展开简介 / 收起简介」
  （`TvCard`，只在 `Pref.tvFocus` 时出现），位置**固定在正文上方**——
  如果按常规做"收起时在下面、展开时在上面"，按一下确定焦点节点就没了。

## 6. 默认零侵入

所有 TV 专属行为挂在 `Pref.tvFocus`（设置项「手柄/遥控器模式」，默认开）后面：

```dart
if (Pref.tvFocus) { ... }
```

关掉后行为完全退回改动前（`TvCard` 退化成普通 `InkWell`，`TvRegion`
不建 scope，`TvShortcuts` 整层消失），触摸用户感知不到差异。

播放器没有单独的子开关：**「手柄播放器模型」也挂在 `Pref.tvFocus` 下**
（判定 `isPlayerTvMode()`），里面同时包含"非全屏整块画面是一个焦点"
和"全屏下方向键唤栏 / 确定键播放暂停"这两条，**视频页和直播页一样**。
遥控器用户觉得键盘被一起改了（框架区分不出遥控器方向键和键盘方向键），
要老键位就整个关掉「手柄/遥控器模式」。

---

## 顶部标签栏：`TvTabBar`

页面里的 `TabBar` 一律换成 `TvTabBar`：参数完全一样，只多一个 `regionLabel`。
它把"方向键停在标签上"从 `InkWell` 那点 `focusColor` 换成和卡片同一套的预选框，
并且**焦点落到哪一栏就切到哪一栏**。

```dart
SizedBox(
  height: 42,
  child: TvTabBar(
    regionLabel: 'later-tabbar',   // 焦点区域标签，同一页面里要唯一
    controller: _tabController,
    tabs: [...],
  ),
)
```

它做五件事：

1. **每个标签一个自己的 `FocusNode`**，交给 `FocusRing` 画预选框：1.04 倍缩放 +
   2px 主题色描边 + 12% 主题色底纹（`TvFocusSpec.tabRadius` / `tabFillAlpha`，
   对齐 blbl 的 `blbl_focus_scale` + `blbl_focus_bg_round`）。底纹画在标签文字
   **下面**（`FocusRing.fillColor`），所以文字不会被染色。
2. **焦点即切换**：焦点落到某一栏就 `animateTo` 那一栏（对齐 blbl 的
   `tabSwitchFollowsFocus`）。设置项「标签跟随焦点切换」= `Pref.tabSwitchOnFocus`，
   默认开；关掉之后焦点照样有预选框，只是要按确定才切。
3. **进栏锁**：焦点**从栏外进到标签栏上**时，落点固定在当前选中的那一栏
   （见下）。
4. **自己就是一个 `TvRegion`**：`TvRegions.focusFirst('<label>', index: n)` 照旧
   可用（序号就是标签顺序），L1/R1 也能在**任何**有标签栏的页面切栏。
5. **`Pref.tvFocus` 关掉时完全是空操作**：不建节点、不画环、不包区域，
   结构退回成裸 `TabBar`。

### 进栏锁：从内容区按 ↑ 落到当前那一栏

方向键走的是**几何寻焦**，它只认位置：在第三栏的内容里按 ↑，正上方是第三个
标签，于是预选框跳到第三栏——几何上没错，但手柄用户想的是"回到标签栏"，
而且预选框一落上去，"焦点即切换"还会顺手把页面切走。所以进栏一律锁到当前
选中的那一栏（`TvTabEntryLock`，横排竖排共用同一份）。

**栏内**的 ←/→ 不锁：那时候本来就该按位置在标签之间走。区分办法是"这一批
焦点变化**之前**栏里有没有焦点"——注意不能直接问"还有没有兄弟标签持有焦点"：
`requestFocus` 是延迟到 microtask 才生效的，监听器被调到的时候这一批已经全部
应用完，栏内移动的旧节点早就失焦，那样每次栏内移动都会被误判成"从外面进来"。
所以进栏读的是上一次记下的值，出栏之后（下一个 microtask，那时栏里确实没人了）
才复位。

两个页面把焦点送进标签栏的真实路径（首页 / 视频页 `_switchTab`：先
`animateTo(target)`，下一帧 `TvRegions.focusFirst('<label>', index: target)`）
不受影响：那时它已经是当前栏，锁无事可做。所以 `index:` 参数只在"落点正好是
当前栏"时才有意义——这正好是那两处的用法。

### 为什么要动 `lib/scripts/material/tabs.patch`

框架的 `TabBar` 没有逐标签的焦点扩展点：每个标签就是一个 `InkWell`，节点由它
自建；`_labelPaddings` / `_tabKeys` / `_currentIndex` 全是库私有的，覆写 `build`
会把指示器测量一起丢掉。所以继续走仓库既有的"就地打补丁"路线，
在 `_TabBarState` 上开三个默认等价于原行为的钩子：

| 钩子 | 调用点 | 为什么是这个位置 |
| --- | --- | --- |
| `buildTabFocusNode(index)` | `InkWell(focusNode: ...)` | 标签的焦点节点只能从这里递进去 |
| `buildTabShell(index, child)` | `MergeSemantics` 之后、`applyFillAlignment` 之前 | 壳的盒子要正好等于标签格子；晚一步就会被 `Expanded` 包在外面，环会画到整条栏上 |
| `buildTabBarRoot(child)` | `build` 的 `return` 上 | 整条标签栏包一层 `TvRegion` |

补丁由 `lib/scripts/patch.ps1` 在 `build_windows.bat` / `build_android.bat` 和 CI
里自动套用（先用 `git apply -R --check` 自检，对不上就删掉包重下再套），
所以**改完照常构建**即可，不需要手工动 pub 缓存。

### L1/R1 的两级查找

`TvShortcuts` 收到的 L1/R1（`[` `]`）先找页面自己声明的 `TvSectionSwitcher`
——首页要顺带把焦点送进新栏、视频页是滚到对应区块，它们更懂自己那一页；
没声明才落到"焦点现在所在的标签栏"（`TvTabBars.nearestToFocus`：从焦点沿祖先链
找最近的 `TvTabBarState`，所以套在播放器面板里的标签栏也能正确定位）。
命中之后 `switchBy(±1)` 切栏并把焦点送到新栏的标签上；到头了（第一栏再按 L1、
最后一栏再按 R1）返回 false，按键已经被吃掉，不回退给框架。

### 两个"非标准"用法

- **视频详情页**：它的标签是"滚到某个区块"而不是换页，所以传 `onFocusTab`——
  焦点落上去时执行和点标签同一件事（`animateTo` + `animToTop`）。
  给了 `onFocusTab` 框架就不再自己 `animateTo`。
- **`DynTabBar` / `VerticalTabBar`**：前者改成 `TvTabBar` 的子类（保留自己那三个
  `applyFillAlignment` / `buildTabLabelBar` / `buildIndicator` 覆写）；后者是仓库内
  的完整 fork（左栏竖排，↑/↓ 走标签、←/→ 出栏），在同一份代码里实现了同样三个
  扩展点，参数也一样。

## 主界面导航栏（抽屉 / 底栏 / 侧栏）

主界面一共有四条导航栏：手机底栏的三支（M3 `NavigationBar` / M2
`BottomNavigationBar` / 悬浮胶囊 `FloatingNavigationBar`）和窄侧栏
（`NavigationRail`，手机横屏 / 桌面走这支），外加平板上的这条 96 宽
`NavigationDrawer`（抽屉和侧栏互斥，走 `Pref.optTabletNav`）。**切页的交接口
只有一处**（`_selectNav`），谁当班都一样；差别在焦点环怎么落到"一格 tab"上，见
「底栏与侧栏：`TvNavDestination`」和「按键切页之后把焦点接走」。

先讲平板抽屉。设置项「优化平板导航栏」（`Pref.optTabletNav`，只在平板上、且
导航项多于一个时生效）下，主界面的左侧是一条 96 宽的 `NavigationDrawer`：上面
是头像 / 消息 / 搜索，下面是首页 / 动态 / 我的。**形状按"这一格是什么"分两种**：

| 元素 | 形状 | 出处 |
| --- | --- | --- |
| 头像 / 消息 / 搜索 | 圆（`FocusRing(circle: true)`） | blbl 用 `ShapeableImageView` + `shapeAppearanceOverlay=Circular`，焦点描边贴着圆边 |
| 首页 / 动态 / 我的 | 圆角矩形 16dp + 12% 主题色底纹 | blbl 的 `item_sidebar_nav.xml`（10dp 圆角、描边只在聚焦时出现）+ `blbl_focus_bg_round.xml` |

导航项的 16dp 不是随手定的：抽屉的选中指示条（`indicatorShape`）就是这个形状，
两者共用 `tabletNavTileRadius`（`pages/main/widgets/tablet_nav_item.dart`）——
`_sideBar()` 把它传给 `NavigationDrawerTheme.indicatorShape`，`TabletNavItem`
拿它画焦点环。

焦点环的矩形**就是这一格的矩形**（那 56 高的格子本体，也就是指示条那 72×56 的范围，
同一个 16dp 圆角），描边正好压在指示条的边上：`FocusRing` 只包格子本体，框架的
`tilePadding`（上下 5 / 左右 12）留在环**外面**（`TabletNavItem._tilePadding`）。
于是 12% 底纹就是"这一格自己的背景色"——这正是原来那版做不到的：环包着
`tilePadding` 时是 96×66，比指示条每边宽 12dp、高 5dp，底纹和描边都溢出到格子外面
去了。那圈留白还兼作**缩放余量**：1.04 倍每边多出 1.4dp，而第一枚离导航列表视口的
上沿只有 5dp——原来放大后两侧描边会被 `ListView` 的 `Clip.hardEdge` 削成不到
0.2px 的细线、顶边也被切；现在整圈都落在视口内（`test/tv_focus_test.dart`
的「导航项：环就是这一格自己的矩形，放大后也不出视口」钉着这两条）。

指示条那边有个容易看走眼的地方：框架那份 defaults 假设抽屉有 360 宽、指示条宽
336，而这条抽屉只有 96，`NavigationIndicator` 被父约束夹成了 72×56——**16dp 圆角
是可见的**，只是"和环完全同形"这件事得靠环这边的几何去凑（见上），
不需要去夹 `NavigationIndicator.width`。

### 为什么不用 `NavigationDrawerDestination`

框架的 destination 内部那个 `InkWell` **自己建焦点节点**，外面拿不到——框架的
`wrapChild` 没留扩展点，和 `TabBar` 是同一类问题。标签栏那次是就地打补丁
（`lib/scripts/material/tabs.patch`），这次不用：`NavigationDrawer.children` 官方
就允许混自定义控件（"and/or customized widgets like headlines and dividers"），
所以自己搭一个 `TabletNavItem` 就行，**material 的补丁一个都不用加**（补丁要重新
套一遍 pub 缓存才生效，能用应用层解决就不走它）。

`TabletNavItem` 复刻的部分都贴着框架的写法，版面和手感不变：

- 选中指示条直接用框架导出的 `NavigationIndicator`，连那条 500ms 的横向展开动画
  一起搬（框架里是 `_SelectableAnimatedBuilder`）。注意 `NavigationIndicator`
  要一个真的 `Animation`，`AlwaysStoppedAnimation(0)` 会让那条 40% 宽的指示条
  永远留在那儿；颜色也得显式给——不传会退成 `ColorScheme.secondary`，而抽屉的
  默认值是 `secondaryContainer`（框架那份 defaults 是私有的）。
- 图标 / 文字 / 指示条的颜色和尺寸仍读 `NavigationDrawerTheme`（页面上那份是唯一
  的出处），`tilePadding`（`symmetric(vertical: 5, horizontal: 12)`）与
  `tileHeight`（56）保持框架默认值。
- 焦点节点只有一个：`FocusRing` 把它交给内部 `InkWell`（准则 1）。`onTap` 接的是
  `_selectNav(index)`（原来是直接 `setIndex`）——切页那一下要不要把焦点送进新页面
  由它统一决定（见「按键切页之后把焦点接走」）。

`NavigationDrawer` 上的 `onDestinationSelected` / `selectedIndex` / `tilePadding` /
`indicatorShape` 这几个参数随之删掉——它们只对框架自己的 destination 生效，
留着就是"看着像在起作用"的死参数（`indicatorShape` 挪进了
`NavigationDrawerTheme`，`TabletNavItem` 读的就是它）。

### 头像 / 消息 / 搜索

这三颗是**共用控件**（`home/view.dart` 的 `userAvatar` / `msgBadge`、`main/view.dart`
的 `_searchButton`），平板抽屉、平板侧栏的 `NavigationRail.leading`、手机顶栏
（`customAppBar`）、「我的」页头部用的是同一份。所以圆环加在控件里面：四处一起
带上，形状一致。统一走 `FocusRing` 旁边那个 `circularFocusRing`：

```dart
Widget _searchButton() {
  Widget build(FocusNode? focusNode) => IconButton(focusNode: focusNode, ...);
  return circularFocusRing(debugLabel: '搜索', builder: build);
}
```

它替掉了三份一样的样板：`Pref.tvFocus` 关掉时直接把 `null` 递给 `builder`
（内部控件自己建节点）、**[FocusRing] 连建都不建**——准则 6「默认零侵入」，
节点一个不多。注意读开关的时机：调用点在 `build` 里（`customAppBar` 那种），
所以开关变了会跟着变。

没登录时消息那一格是 `SizedBox.shrink()`：节点没人接，也就进不了焦点遍历
（遍历走的是 element 树），不会多出一个"看不见的落脚点"。

**放大照旧**（1.04 倍，和别的控件一样）：这是焦点框的通用手感，不因为它们是圆按钮
就特殊。代价就是「可见（焦点预选框）」里那条规则——头像在抽屉头部是**第一格**，
紧贴抽屉上沿，而 `Drawer` 的 M3 默认 `clipBehavior` 是 `Clip.hardEdge`、裁剪线就是
抽屉自己的矩形：1.04 倍把环从 34dp 的框里往上顶 0.68dp（+ 描边抗锯齿），正好落在
裁剪线外，环顶被削平一条（像素级量过：同一个头像在抽屉外是完整的圆，在抽屉里顶边
是一条直线）。所以 `_sideBar()` 的头部在抽屉**里面**留了 4dp：

```dart
header: Expanded(
  flex: 4,
  child: Padding(
    padding: const EdgeInsets.only(top: 4),   // 给预选框的缩放让位（同 tilePadding）
    child: userAndSearchVertical(),
  ),
),
```

余量必须在抽屉**里面**（裁剪线内侧）：套在抽屉外面等于连裁剪线一起挪，白留。
`userAndSearchVertical()` 本身不动——`NavigationRail.leading` 和窄侧栏也在用它，
那里没有抽屉上沿要躲（`FocusRing` 直接当 `Expanded` 的孩子还会被拉成整段高度，
得待在 `Column` 里，和 `userAndSearchVertical()` 一样）。这条余量由
`test/tv_focus_test.dart` 的「头像：放大 4% 后环不会被抽屉自己的裁剪线切掉」
看着（把 `top: 4` 去掉那条断言就会炸）。

### 底栏与侧栏：`TvNavDestination`

抽屉那支是**自己搭的格子**，`FocusRing` 的节点能直接交给里面的 `InkWell`；
底栏 / 侧栏是**框架的控件**，内部那个 `InkWell` 自己建焦点节点、外面拿不到
（和 `NavigationDrawerDestination` / `TabBar` 是同一类问题），所以换个挂法：
`TvNavDestination`（`pages/main/widgets/tv_nav_destination.dart`）把 `FocusRing`
的节点当成一层**外壳**套在框架 destination 外面，描边和底纹画在这一格的矩形上，
真正接住焦点的还是里面框架那个 `InkWell`。

这一招能成立靠的是 `FocusNode.hasFocus` 的语义是"**自己或子树里**持有焦点"
（`primaryFocus.ancestors.contains(this)`）：焦点落在里面的 `InkWell` 上时，
外壳节点照样算 `hasFocus`，环就亮。外壳只是"环的挂点"、不是落点，所以
`canRequestFocus: false`——方向键遍历和鼠标点击（`TvRegions.focusAt`）都会跳过
它，确定键照旧走框架的 `ActivateIntent`，**焦点行为一个字节没变**，只是多了个框。
（`test/tv_focus_test.dart` 的「框架的 InkResponse 才是落点，外壳只当环的挂点」
钉着这几条：外壳不在遍历里、里面那枚是唯一落点、按确定仍然回调。）

顺手 `Theme.focusColor = transparent` 压掉框架自带的那层 focus 底纹，视觉统一
交给 `FocusRing`（和 `listTileFocusRing` 同一个理由）；圆角和底纹沿用抽屉那一套
（`tabletNavTileRadius` + `TvFocusSpec.tabFillAlpha`），因为"一格 tab"是同一个东西。

底栏那一支传 `scale: 1.0`：这一格上下都贴着栏边（选中的那格更是紧贴屏幕底边），
放大 4% 会把描边和底纹顶到栏外面去。默认值（1.04 倍）留给"四周有余量"的位置
（比如抽屉里的导航项）。

四条栏里**只有 M3 底栏（`Pref.enableMYBar`，也是默认）套上了**，剩下三种情况
是"套不了"，不是"忘了"：

| 导航栏 | 焦点环 | 为什么 |
| --- | --- | --- |
| M3 `NavigationBar`（默认） | `TvNavDestination` | destination 是 widget，能包 |
| M2 `BottomNavigationBar` | 框架自带的 focus 底纹 | `BottomNavigationBarItem` **是数据类**（`label` / `icon` / `activeIcon`），没有 widget 能包 |
| 悬浮胶囊 `FloatingNavigationBar` | 同上 | 同样收数据类，而且外层有个 `ClipPath` 会把矩形环切成斜边 |
| 窄侧栏 `NavigationRail` | 同上 | `NavigationRailDestination` 也是数据类（`icon` / `label` / `selectedIcon`） |

数据类那三支真要补，得照 `TabletNavItem` 自己搭一列 / 一排格子（复刻框架的版面），
而不是"再包一层"——那是另一件事，先记在这里。**切页交接不受影响**：四条栏的
`onDestinationSelected` / `onTap` 都走同一个 `_selectNav`。

### 按键切页之后把焦点接走

手柄停在底栏上按确定切到「动态」，焦点要是留在底栏那一格上，用户还得再按一次
才能进内容区——**切页和进页面应该是一件事**。所以 `_selectNav` 在切页之后多做了
一步「交接」：

```dart
void _selectNav(int index) {
  _mainController.setIndex(index);
  if (!TvInputMode.fromKeys) return;         // 鼠标/触摸点的不抢
  _handOffNavFocus(_tvRegionOf(navigationBars[index]));
}
```

三个决定：

- **只有按键/手柄触发的切页才送**（`TvInputMode.fromKeys`）：鼠标用户点哪儿焦点
  就在哪儿（鼠标按下已经 `TvRegions.focusAt` 过了），再替他跳一下反而奇怪；
- **目标是"这个导航项对应的当前内容区的首项"**，标签靠各页面自己暴露的常量反查
  （`_tvRegionOf`）：首页看当前选中的子栏（`HomeTabType.tvRegion`，推荐 / 热门 /
  直播各一块，没接适配的分区 / 番剧 / 影视返回 `null`）、动态看当前分类
  （`DynamicsTabPage.tvRegionOf`）、我的整页一块（`MinePage.tvRegion`）。
  为什么不问 `TvRegions.entryNodeFor`：三个页面**共用一条路由**，它只认最先登记的
  那块区域（也就是首页那块），用它交接等于把焦点送进看不见的页面；
- **按帧重试 20 帧**（≈330ms）后放弃：目标区域可能还在加载（切栏那一帧列表是空的），
  等不到就把焦点留在导航项上——看得见、按一下方向键也进得去，比送去一个不存在的
  落点强。重试期间用户自己动了（按了方向键、又切了一栏）就收手，不抢
  （靠"焦点还是不是切页那一刻的那个节点"判定，外加一个自增的代数号
  `_navHandOffId` 让上一轮重试失效）。

所以**被导航栏指着的那三个页面必须给自己的内容区一个 `tvRegion` 标签**，否则
按键切页之后焦点会留在导航项上（这是唯一的"新增页面时的检查清单"里跟导航栏有关
的一条）。

### 已知省略

- **侧栏没套 `TvRegion`**（准则 2 说的"侧栏"）：`TvRegionKind` 只有 `content` /
  `tabBar` 两种，而 `content` 是**进页面的首选落点**（`TvRegions.entryNodeFor`）。
  侧栏标成 `content` 的话，每次切页预选框都会先趴在导航项上。所以先只做"焦点停
  上去有框"，跨区移动照旧按几何走，等第三类 `kind` 有别的用处时再补。
- **不做"进栏即选中项"**：blbl 的 `SidebarFocusHost.requestSelectedNav` 会在焦点
  进侧栏时落到当前页那一项，这里没做——从内容区按 ← 落点按几何走（位置最近的那
  一项）。要的是"导航栏的预选框"，行为先不动。
- **导航项的读屏语义少一条**：框架的 destination 会在 `Semantics(selected:)` 旁边
  再挂一个 "Tab 1 of 3" 的标签（`MaterialLocalizations.tabLabel`），
  `TabletNavItem` 只保留了 `selected`。电视上的读屏用户几乎没有，先不补；
  真要补就是多传两个参数（序号 / 总数）。
- **M2 底栏 / 悬浮胶囊 / 窄侧栏的导航项只有框架自带的 focus 底纹**：
  `BottomNavigationBarItem` 和 `NavigationRailDestination` 都是**数据类**、没有
  widget 能包（`TvNavDestination` 那招用不上），胶囊那支还有个 `ClipPath` 会把
  矩形环切成斜边。要补就得照 `TabletNavItem` 自己搭一列格子（复刻框架的版面），
  是另一件事。M3 底栏（默认那支）已经套好了，切页交接四条栏都有。

## 输入框：两段式焦点（`TvTextField`）

`TextField` 直接交给手柄是不行的：它一拿到焦点就弹软键盘，方向键又被它自己
吃成"移光标"，于是这一格"进得去出不来"——方向键不动、返回键变成退页面、
确定键只能换行/提交。`TvTextField` 因此把焦点拆成两层：

| 状态 | 谁拿焦点 | 软键盘 | 按键 |
| --- | --- | --- | --- |
| **导航态** | 外层节点（画焦点环） | 不弹 | 方向键照常进出这一格 |
| **编辑态** | 输入框自己的节点 | 弹 | 按键都进输入框，只有返回键例外 |

- **进编辑态**：导航态按确定（手柄 A / 遥控器确定）。这就是"按 A 再输入"。
  **抬起也算吃掉**（按下/重复/抬起全部 `handled`），否则抬起那一下会漏成框架的
  一次 `ActivateIntent`。
- **脱出**：编辑态按返回键（B / Esc）→ 焦点交回外层：键盘收起、焦点环还在这一格，
  再按一次确定可以接着改。**退出编辑态不会顺手退出页面**（所以"先脱出、再返回"
  要按两下 B）。
- 硬件键盘直接敲字会**自动进编辑态**（控制字符不算，Tab/Esc/方向键各自还有用途）。
- 输入框自己的节点带 `skipTraversal: true`：方向键在这一格上是"路过"，不是"进去"。
- 触摸行为完全不变：点一下输入框，框架直接把焦点给输入框 = 直接进编辑态、键盘照弹。

```dart
TvTextField(
  // 调用方自己持有输入框节点时必须传进来（老代码的 `requestFocus()`/`unfocus()`
  // 还要用），内部节点则不用管
  editFocusNode: focusNode,
  navFocusNode: navFocusNode,
  builder: (context, node) => TextField(focusNode: node, ...),
)
```

⚠️ 别给里面的 `TextField` 传自己的 `focusNode:`，用 `builder` 给的那个。

⚠️ **页面自己请求焦点时要分模式**：进页面就把焦点交给输入框（老代码写的
`focusNode.requestFocus()`）在手柄模式下等于"一进页面键盘就弹起来"。
所以 `CommonPublishPageState` 一类的宿主多持有一个 `navFocusNode`，
`Pref.tvFocus` 为真时请求它、否则请求输入框自己：

```dart
if (Pref.tvFocus) navFocusNode.requestFocus(); else focusNode.requestFocus();
```

⚠️ 反过来，**触摸点开输入框时不要拦**：面板/占位符（"说点什么吧"）上的那一次
确定/点击本来就代表"我要打字"，直接进编辑态才是对的（如
`dynamics_repost` 的占位符展开）。

⚠️ **搜索页那种"一进来就该能打字"的输入框，里面的 `TextField` 要写
`autofocus: !Pref.tvFocus`**：`TvTextField.autofocus` 只在手柄模式下把焦点送到
外层导航态（手柄要的是"先停在框上"），而老行为是"一进页面键盘就弹好"。
两个 `autofocus` 各管一半，少写一个就会让**触摸用户在打开页面后还得再点一下**
输入框。本仓库已按这个写法改过：搜索 / 分区搜索 / 用户搜索 / 设置搜索 /
关于页 / 收藏夹重命名 / 屏蔽词与其它设置弹窗。

## 播放器：两套键位 + 三层焦点

播放器是唯一一个"方向键另有语义"的地方（准则 2 第 1 条），按键层 `PlayerFocus`
按设置分流成两套：**桌面键盘**（`tvFocus` 关着）逐字保留原逻辑；
**「手柄/遥控器模式」打开**时**视频页和直播页一起**走「手柄播放器模型」，
方向键和确定键完全归焦点系统。判定统一走 `isPlayerTvMode()`
（= `Pref.tvFocus`），别在调用点上再分直播/视频——两页的差别全在上下栏
各自装了什么控件（直播没有进度条、快进被 `isLive` 短路）。

### 三层结构

```
TvPlayerSurface      （只在手柄播放器模型下装：非全屏时画面 = 一个大焦点）
└── PlayerFocus      画面（焦点锚点 player-surface，autofocus，手柄模式下 skipTraversal）
    └── PlayerTvOsd  OSD 整层（区域 player-osd，edgeBehavior: stop）
        ├── AppBarAni    顶部信息栏（区域 player-osd-top，进栏锁 → 返回键）
        └── TvRegion     底栏（区域 player-osd-bar，进栏锁 → 播放/暂停）
            └── TvSeekBar / ComBtn / PlayOrPauseButton ...
```

- **画面是锚点不是区域**。`TvRegions.registerAnchor(playerSurface, node)`
  让别处能把它拉回来：`TvRegions.focusAnchor(...)`。**登记人由模式决定**：
  关掉手柄模式时是 `PlayerFocus` 那个页面级节点，手柄播放器模型下换成
  `TvPlayerSurface` 的画面节点。两边都在自己的 `build` 里同步登记
  （不是 `initState`，这样运行中开关设置也能换人），父层后于子层 build 时会
  用 `!enabled` 让位，`unregisterAnchor` 有 identity 检查，不会误删别人的节点。
- **画面在关掉手柄模式时** `skipTraversal: true`——它就是一块大矩形，
  参与遍历会把所有卡片的焦点抢走。`skipTraversal` **不影响 `autofocus`**
  （`_pendingAutofocuses`/`applyIfValid` 只看祖先链），所以进页面焦点仍在画面上。
  手柄播放器模型下更彻底：`PlayerFocus` 关掉自己的 `autofocus`，
  焦点从画面那一层开始。
- **上下栏各有自己的区域标签 + 进栏锁**（`TvEntryLock`）：焦点**从栏外进到栏里**
  时落点锁死——上栏锁 `player-back`（返回键）、下栏锁 `player-play-pause`
  （播放/暂停按钮）；**栏内**走动不锁，仍是几何寻焦（从播放/暂停能走到隔壁按钮）。
  锚点没登记时什么也不做，退回几何寻焦——直播页非全屏时上栏整层不可聚焦、
  返回键也不在树上（那一栏只在全屏 / 桌面画中画里出现），锚点跟着撤销登记。
  为什么不用 `focusFirst`（区域首项）：顶栏第一个可聚焦项不是返回键、底栏第一个
  也不是播放/暂停（树序里前面还有别的按钮），而"落点"也不该跟着栏的布局跑。
- OSD 内两个区域都是 `stop`：控制条亮着的时候方向键在 OSD 里循环
  （底栏 ↑ 到顶栏、顶栏 ↓ 回底栏），**按 B 才收起来回画面**，不越界跑到页面其他部分。
- OSD 收起时 `ExcludeFocus` 让整层直接离开焦点树，同时触发下面的"焦点拉回"。

### 焦点被"收走"时必须拉回画面（否则播放器变成砖）

控制条被收掉的路径很多：按 B、触摸点一下画面、自动隐藏超时、切全屏、锁屏。
除了按 B（我们自己 `requestFocus()`），其余路径框架的 `applyFocusChangesIfNeeded`
会把焦点退回**路由 scope**（`_ModalScopeState`）——这时音量、快进、确定键
在 `PlayerFocus.onKeyEvent` 里全都收不到，手柄看起来就是"播放器没反应了"。

所以 `PlayerTvOsd` 监听 `FocusManager`，一旦发现焦点离开 OSD 就
`TvRegions.focusAnchor(playerSurface)` 拉回画面。**注意用 `hasFocus` 语义**：
锚点节点的 `hasFocus` 在自己或任一后代有焦点时都为真，正好可以拿来问
"焦点现在在不在这块区域里"。

### 控制条自动隐藏：焦点在 OSD 里**也照收**

老写法反过来：`hideTaskControls` 每 2 秒问一次 `tvFocusInControls`，为真就重新
计时——"焦点在控制条里就不自动隐藏"。手柄把预选框停在控制条上时，那一层于是
**永远不收**：焦点待在一块不会消失的浮层里，用户看到的是"这块东西一直在，
按它也没反应"。已经拿掉了。

现在的规则两条：

- 到点就收，**焦点在 OSD 里不豁免**（收掉之后由上一节那条"拉回画面"接住）；
- 栏亮着时，人在控制条上按键就**重新计时**——`PlPlayerController.keepControlsAlive`，
  `PlayerFocus` 每收到一次按在 OSD 里的按键就调一次。所以"一直在操作"不会被
  打断，"停手"也一定收得掉；代价就是人在栏里时得**一直按**才留得住它。

计时器本身还是 `hideTaskControls`（超时时长不变：`Pref.enableLongShowControl`
才是 30s，否则 3s），`isSeeking` / `tripling` 期间照旧不收起。

### 鼠标光标跟着控制条收放（`PlPlayerController.playerCursor`）

| 状态 | 光标 |
| --- | --- |
| 控制条亮着 | `MouseCursor.defer`（照旧） |
| 控制条收着 | `SystemMouseCursors.none` |

看片时鼠标不动 → 超时收栏 → 光标跟着一起消失；再晃一下鼠标，`MouseRegion.onHover`
把栏亮起来，光标同时回来。**不需要单独的"鼠标静止计时器"**：会收栏的那一路本来
就是"指针停在视频上但没动"，复用同一个计时器就够。

**不要求全屏**（老写法是 `!showControls && isFullScreen` 才藏）：窗口里那块视频
同样得"看片时不挡着"。窗口模式里指针会离开视频区域去做别的事，那一下 `onExit`
把控制条收掉、光标也交回页面管（`defer`），不会出现"整个页面没有光标"。
视频页和直播页共用 `PLVideoPlayer` 这一层，所以两页一起生效。

换光标为什么立刻可见：`RenderMouseRegion.cursor` 的 setter 会 `markNeedsPaint`，
`MouseTracker` 因此重算一次，**不用等下一次指针移动**——不然就是"晃了却还看不见
光标"。

### 键位表（手柄模式关着时：桌面键盘）

**「手柄/遥控器模式」打开时这张表不适用**——视频页和直播页都走下一节
「手柄播放器模型」。表里的 B / 确定 两行原来写的是手柄模式下的行为
（B 两页都有、确定只有直播页有），那两条已经并进模型里了。

焦点在**画面**上：

| 键 | 行为 |
| --- | --- |
| ←/→ | 快退 / 快进（保持原语义） |
| ↑/↓ | 音量（保持原语义） |
| enter / space | "跳过片头 + 发弹幕"（直播页是发弹幕）/ 播放暂停 |
| L2 / R2 | 快退 / 快进（媒体键同） |
| L1 / R1 | 走全局层（上一栏/下一栏），播放器里没做特殊处理 |
| B / Esc | 播放器不拦，交给全局层（全屏里 = 退出全屏，桌面画中画里 = 退画中画，否则退页面） |

焦点在**控制条**里（下面这几条都是手柄模式打开时；关着时播放器不拦 B，
它是全局的"返回"）：

| 键 | 行为 |
| --- | --- |
| ←/→ | 控件间导航；停在进度条上时按 `TvSeekBar` 的规则微调（见下） |
| ↑/↓ | 顶栏 ↔ 底栏（`stop` 边界，不会跑出 OSD） |
| 确定 | 激活焦点控件（`ActivateIntent`，交还框架） |
| 空格 / Tab | 交还框架（空格 = 激活焦点控件，`NextFocusIntent` 照常） |
| B / Esc / 安卓返回键 | 收控制条 + 焦点回画面（走 `hideControlsOnBack`，见下） |

B 这一行**不是 `PlayerFocus` 自己判的**：焦点在 OSD 里时它只做一件事——把自动隐藏
重新计时（`keepControlsAlive`），其余按键一律放行；返回键那一下交给全局那条路。
原因是这三条路根本不在焦点树里汇合（见「返回键：一套语义」）：桌面端的 Esc 由
`main.dart` 的 early handler 直接送进 `appBack()`，安卓返回键走系统 `popRoute`，
只有手柄 B 会经过 `PlayerFocus`。规则放在三者**共同**的落点上才管得住全部。

实现上 `onKeyEvent` 开头只做一次判断：`TvRegions.hasFocus(playerOsd)` 为真就
**放行**方向键/确定键/空格/Tab，其余按桌面键位表走。放行（`ignored`）而不是
`handled` 很关键——`handled` 会让按键停在这一层，控件的"确定"就永远不会被激活。

### 返回键：全屏里亮着 OSD 就先收 OSD（`hideControlsOnBack`）

需求：全屏 / 窗口全屏（桌面全屏和 `windowFullScreen` 是同一个 `isFullScreen`）
**且 OSD 亮着**时，`Esc` / 手柄 `B` / 安卓返回键的语义是**隐藏 OSD**，而不是退出
全屏、更不是退页面。

| 状态 | 返回键 |
| --- | --- |
| 手柄模式 + 全屏 + OSD 亮着 | 收 OSD（焦点回画面），这一下到此为止 |
| 手柄模式 + 全屏 + OSD 收着 | 退全屏（交给 `onBackButton` 的下一步） |
| 手柄模式 + 非全屏 | 播放器不插手：退页面（桌面画中画里是退画中画） |
| 锁屏中 | 不插手（那一下是"解锁"） |
| 手柄模式关着 | 不插手（桌面键盘的 Esc 照旧是"退出全屏"） |

`PlPlayerController.onPopInvokedWithResult` 是最前面的落点（`noPop` 分支），
`hideControlsOnBack()` 返回 true 就只收 OSD。三条路怎么走到这里的：

- **手柄 B**：焦点树 → `TvShortcuts` → `appBack()` → 路由 `popDisposition`
  （全屏时 `PopScope(canPop: false)`）→ `onPopInvokedWithResult`；
- **桌面 Esc**：`main.dart` 的 early handler → 同一个 `appBack()` → 同一处；
- **安卓返回键**：系统直接 `popRoute`，**不经过 `appBack()`**——它自己就会落到
  路由的 `popDisposition` 上，所以补在 `onPopInvokedWithResult` 里是唯一
  三个都覆盖得到的写法（不需要给播放器压 `TvBack` handler）。

只认这两个状态是有意的：**非全屏的 OSD 是给鼠标/触摸的浮层**（手柄模型下整层
不进焦点树），在那儿按返回还是"退出页面"，别让触摸用户为了退出多点一次；
**桌面键盘模式**（「手柄/遥控器模式」关着）的 Esc 保持"退出全屏"的老语义，
桌面用户对这个键有预期。窗口全屏和桌面全屏走同一个 `isFullScreen`，规则一视同仁。

OSD 上那颗**返回按钮**（顶栏那颗）不走这条路：它直接调
`PlPlayerController.onBackButton`（锁屏 → 画中画 → 全屏 → 退页面）。
那颗按钮只在控制条亮着时才看得见，被"先收控制条"吃掉就成了"按了没反应"——
它要的就是退出。视频页和直播页共用这一颗按钮的行为。

**面板开着时返回键不会误伤控制条**：面板是路由（画质、弹幕设置……）或
`MiniScaffold` 底弹层，前者本身就是最上层路由、后者是路由内部的 local history
entry（`popDisposition` 那时返回 `pop`），都在 `onPopInvokedWithResult` 之前
把这一下吃掉了。

### 手柄播放器模型：整块画面 = 一个焦点（`TvPlayerSurface`）

只在**「手柄/遥控器模式」打开**时成立（`isPlayerTvMode`），**视频页和直播页
一模一样**。它解决的是上面那张表里最反直觉的一条：手柄 / 遥控器用户想要的
不是"↑/↓ 调音量"，而是"方向键在界面里移动预选框"；而**框架区分不出遥控器
方向键和键盘方向键**（都是 `arrowUp`），所以这一模式下键盘的方向键也一起
交出去了。

直播页跟着一起走，是因为这一套只谈"焦点停在哪、确定键干什么"：它没有进度条、
快进被 `isLive` 短路，那几个键本来就不参与模型，上下栏里剩下的控件（播放/暂停、
返回、刷新、弹幕、画质……）和视频页是同一批 `ComBtn`，焦点行为也就该是同一个。
代价是直播页**非全屏时方向键不再弹控制条**（它现在在页面里移动预选框）、
**遥控器确定不再是"进控制条"**（非全屏 = 进全屏，全屏 = 播放/暂停），对齐视频页。

播放器在这一模型下分两态（`isFullScreen`，**窗口全屏 `inAppFullScreen` 也算全屏**）：

**非全屏（内嵌播放器）**

- 整块画面 = **一个**焦点，预选框贴着视频内边缘（`FocusRing` 的描边是
  `Positioned.fill` 画在边界**内侧**的，不会被视口裁掉，也不用给布局留外间距；
  `scale` 固定 1.0，整块画面缩放会顶出视口）。
- **播放器里的控件一个都进不了焦点树**：`PlayerTvOsd` 在非全屏把整层
  `ExcludeFocus`。这是需求明确要求的——"非全屏时整个视频视为一个焦点，
  无论何时都无法将焦点移动到视频播放器内的元素上"，包括画面上一层那些
  上下拉控制按钮。
- 确定（手柄 A / 遥控器确定 / 回车）= **进全屏**；方向键放行，去页面里别的卡片。

**全屏 / 窗口全屏**

| 场景 | 键 | 行为 |
| --- | --- | --- |
| 上下栏收着 | 确定 | **播放 / 暂停**（对齐 BBLL） |
| 上下栏收着 | ←/→/↑/↓ | 唤起上下栏 + 焦点送到**播放/暂停按钮**（焦点不自己移动） |
| 上下栏亮着 | 方向键 | 正常控件间导航，**预选框是圆形** |
| 焦点进下栏 | — | 强制落在**播放/暂停按钮**（进栏锁） |
| 焦点进上栏 | — | 强制落在**返回按钮**（进栏锁） |
| **进全屏**时上下栏亮着 | — | 焦点固定到**播放/暂停按钮**（和"唤栏"同一个落点） |
| **进全屏**时上下栏收着 | — | 焦点留在画面（收栏的静息态，什么也不做） |
| 退出全屏 | — | 焦点交回画面（非全屏下它是唯一落点） |
| 任何时候 | 空格 / 字母键 | 播放暂停、发弹幕、全屏(`F`/`X`)、静音……照旧 |
| 控制条亮着 | B / Esc / 安卓返回键 | 只收控制条，焦点回画面（`hideControlsOnBack`） |
| 控制条收着 | B / Esc / 安卓返回键 | 退全屏；全屏之外才交给全局层（退页面） |

全屏下画面**不再是"整块一个大焦点"**：焦点能进上下栏了，它退化成"上下栏收起来
时焦点停的地方"，所以**不画预选框**（`FocusRing(hideRing: true)`）——上下栏收着
是它唯一会停留的状态，那种状态下画一圈大框只会让人以为"还能往别处走"。

几点实现说明：

- **确定键只在画面自己持有焦点时才接**（`node.hasPrimaryFocus`）。OSD 是画面的
  子节点，焦点落在里面某个按钮上时这一层会作为祖先收到同一颗确定键，
  不判断的话就会"按确定激活不了按钮，反而变成播放暂停"。
- **`enter` 在画面上就是确定键**（需求里的"回车 = 确定"），所以这一模型下
  键盘的"回车 = 跳过片头 / 发弹幕"让位；发弹幕仍有顶栏按钮和 `D` 之类的键。
  这是 `Pref.tvFocus` 打开时的既定取舍，要老键位就把「手柄/遥控器模式」关掉。
- **进全屏时看上下栏在不在**（`_enterFullScreen`）：亮着（触摸/鼠标刚把它点出来，
  或者就是从栏里那颗全屏按钮进的）就把焦点固定到**播放/暂停按钮**上——用户看到的
  是同一件事"栏就在那儿"，预选框该落在这一栏的起点上，和方向键唤栏的下标一致；
  收着则**什么都不做**，焦点留在画面（那是收栏状态的静息态，硬送进控制条等于
  把栏一起点亮了）。送焦点要**按帧重试**（最多 4 次）：`PlayerTvOsd` 的
  `ExcludeFocus` 跟着全屏状态走，按钮要等全屏生效后的下一帧才回到焦点树里
  （非全屏时它连"能聚焦"都不是），一帧之后再去问；每次重问一遍条件，
  用户自己收了栏、退了全屏，或者这一页已经被面板/菜单盖住，就立刻收手。
  窗口全屏（`Pref.windowFullScreen` / 桌面全屏）走的是同一个 `isFullScreen`，
  这条规则对两种全屏一视同仁。
- **方向键唤栏只认"第一次按下"**（`TvKeys.isFirstPress`）：长按的重复事件只吞掉，
  不然每帧都要重新送一遍焦点。
- **返回键那一步不在这一层**（`PlayerFocus` / `TvPlayerSurface`）：全屏里 OSD 亮着
  时它要先收 OSD，而 Esc 和安卓返回键都到不了焦点树，所以规则写在三条路的共同
  落点 `PlPlayerController.onPopInvokedWithResult` 里（见「返回键：全屏里亮着 OSD
  就先收 OSD」）。这一层只做"焦点在 OSD 里就把自动隐藏重新计时"。
- **焦点在进度指示器上时不画整条进度条的环**（`TvSeekBar(focusOnThumb: true)`
  把 `borderWidth` 收成 0），那一圈改由 `ProgressBar.thumbFocusRing` 画在
  thumb 外面——否则会同时出现两个框，让人以为有两个能停的地方。
- **圆形预选框**由 `FocusRing(circle: true)` 提供（`BoxShape.circle`，圆角矩形
  和它互斥），`TvButton` 统一打开。它只影响视觉，所以直播页的播放器控件也会
  跟着变圆——同一套组件，不为此再分叉。
- **画面晚一步建出来时接走"悬空"的焦点**：`videoState` 没就绪 / `autoPlay` 关着 /
  切布局 / 拉流重试时 `PLVideoPlayer` 会被换成 `SizedBox.shrink()`，这一层也跟着
  不在树上。等它建出来，焦点多半悬在路由 scope 上或者 `TvLabels.playerPage` 那个
  页面级节点上，`TvPlayerSurface` 在首帧之后 `_claimFocus()` 把它接过来
  （`autofocus` 只在同一批里没人抢焦点时才起作用，接不住这种情况）。反过来，
  焦点不在画面里时它**不抢**：画面被拆掉只把"本来就在画面里"的焦点交给
  页面那一层兜底，不会顺手把用户从别处拽回来。
- **`dispose` 里不能查祖先**：把焦点交回页面那一层走的是
  `TvRegions.focusAnchor(playerPage, checkRoute: false)`——`focusAnchor` 默认要问
  `ModalRoute.of`，而 `dispose()` 里查祖先框架会直接抛断言
  （"Looking up a deactivated widget's ancestor is unsafe"）。

### 进度条上按左右：微调而不是导航

`TvSeekBar` 把进度条做成一个可聚焦控件，左右键在**本控件内**改位置：

- 步长 `TvFocusSpec.seekStep`（5 秒，故意小于 `fastForBackwardDuration`）。
- **按住的过程只挪预览、不 seek**：`beginSeek` 一次，之后只改 `seekPosition`
  并 `previewIndex` 走缩略图；**抬起**（或焦点离开进度条）才 `commitSeek`
  真正 seek 一次。这样按住连点不会把播放器打成一串 seek 请求。
- 位置用 `clamp(0, duration)`：到头的表现是"停住"，不是跳回 0。
- **确定键 = 播放/暂停**（对齐 blbl），不是"跳到这个位置"。
- 拖拽/点击进度条的触摸路径完全不变。

`TvSeekBarHost` 是给 `PlPlayerController` 收窄用的接口（测试里可以直接
塞一个假 host，不用起播放器）。视频页的适配器是 `_ControllerSeekBarHost`。

### `TvButton`：让"只能点"的控件能被手柄停住

播放器控件几乎都是 `GestureDetector`（`ComBtn`、`PlayOrPauseButton`、
直播底栏），不是 `InkWell`，**天然不进焦点树**——手柄根本停不上去。
`TvButton` 给它们补三件事：`Focus` 节点、焦点环、`ActivateIntent → onTap`。

```dart
TvButton(
  debugLabel: '刷新',
  onTap: onTap,
  onSecondaryTap: onSecondaryTap, // 手柄 Y = 原来的右键/长按动作
  child: 原来的 GestureDetector(...),
)
```

- `onTap` 为空的占位按钮**不进焦点树**（`canRequestFocus: false`），
  否则方向键会停在一个按不动的图标上。
- 没给它 `onTap` 就等于没行为，所以 `TvButton` 必须包在**最外层**
  （`ComBtn` 是包整个 `SizedBox`，不是包 `GestureDetector`）。
- 视频页和直播页共用同一套（`ComBtn` / `PlayOrPauseButton` 是共享组件），
  所以直播底栏和顶栏"返回"按钮自动就有焦点环，不需要各写一遍。

### 直播页

直播复用同一套：同一个 `PLVideoPlayer`、同一个 `PlayerFocus`、同一份
`TvPlayerSurface` / `PlayerTvOsd` / 两个进栏锁，所以「手柄/遥控器模式」打开
时它和视频页走的是同一个模型（`isPlayerTvMode()` 里不分页面）。"键盘控制"
这个开关已经去掉了（键盘一直是常开的），所以装 `PlayerFocus` 不需要条件：

```dart
child = PlayerFocus(plPlayerController: ..., child: child);
```

直播页这边需要单独做的只有两件事（都在它自己的控件里）：

- **返回键要交出焦点节点**：`LiveHeaderControl` 的返回键是个 `ComBtn`
  （自己建节点），进栏锁在播放器那一层够不到它的 State，所以 `ComBtn` 多了个
  `focusNode` 透传，`_LiveHeaderControlState` 拿它登记 `player-back` 锚点。
  这个返回键只在**全屏 / 桌面画中画**里才建（也正是手柄模式下焦点能进上栏的
  时候），所以锚点跟着这个条件登记/撤销——不在树上时进栏锁退回几何寻焦。
- **下栏的播放/暂停按钮**（`PlayOrPauseButton`）自己就是 `player-play-pause`
  锚点，和视频页同一个组件、同一行代码，不用额外做什么。

直播间底栏（发送弹幕那一整条）在**竖屏/侧栏布局**下也是一个 `TvCard`：

| 键 | 行为 |
| --- | --- |
| 确定 | 打开发送弹幕面板（和触摸点在整条栏上一样） |
| 长按确定 / Y | 点赞一次（触摸那边是按住点赞按钮连点，手柄只给一次） |

栏里的「弹幕开关 / 点赞 / 表情」三个按钮在触摸上照旧可点，但手柄模式下
统一 `TvCardSubAction`（一个 cell 一个焦点）。弹幕开关在播放器控件里也有一个，
手柄走那边（见上表 `D` 键）。

直播页里**进不了焦点树**的东西（和触摸路径一致，不是遗漏）：画面上那层
`LiveDanmaku` 弹幕、`SuperChatCard`、弹幕互动提示——它们只有 `GestureDetector`，
手柄模式下不可达；上栏/下栏整层在**非全屏**时也不可聚焦（模型要求如此）。

### `[` `]` 的归属

`TvKeys.prevSection/nextSection` 里有 `[` `]`（切栏），`PlayerFocus` 的老键位表里
也有 `[` `]`（上一集/下一集）。播放器在焦点树上比全局的 `TvShortcuts` **更靠内**，
派发由内向外，所以**焦点在播放器里时 `[` `]` 是切集**，焦点在页面上时才是切栏。
这是有意的：正在看视频的人按 `[` `]` 想要的显然是上/下一集。

## 滑块：`TvSlider`（框架挖的坑）

`Slider` 在 `NavigationMode.traditional`（默认）下把**四个方向键全绑成"调节"**
（`slider.dart` 的 `_traditionalNavShortcutMap`：左右 ±1%、上下 ±10%），
于是手柄一旦停在滑块上，方向键就**再也走不出去**了——音量、倍速、字号这些
设置项都是滑块，一进去整个页面就卡住了。

`TvSlider` 只做一件事：把这一格单独包成 `NavigationMode.directional`
（框架在这个模式下只绑左右键，上下键留给"走出这一格"）：

```dart
TvSlider(child: Slider(...))
```

- 滑块没有可以直接接管的 `FocusNode`（`Slider.focusNode` 是它内部创建的），
  所以这里**不能**用 `FocusRing`——焦点视觉用滑块自带的（拇指高亮 + 光圈）。
- 已接：界面缩放、字体粗细/大小、颜色调节、双滑块弹窗、动态分栏比例、
  音频倍速。**新增滑块一律套一层**。
- 这也是唯一一处"局部用 `NavigationMode.directional`"的地方，理由见文末取舍。

## 长按确定：为什么能实现

`TvCard` 上的长按确定不是"监听长按"，而是**截住确定键的按下/抬起**：

```
手柄 A ──FocusManager 派发──> TvCard 的焦点节点.onKeyEvent
                              ├─ 有长按动作：吃掉，起 500ms 计时
                              └─ 没有长按动作：放行
                                   └─> Shortcuts(enter→ActivateIntent)
                                        └─> Actions.invoke(primaryFocus.context)
                                             └─> InkWell.activateOnIntent → onTap
```

- 吃掉按键就等价于"这次确定不激活"，抬起时自己判断是点击还是长按。
- 按住期间画 `HoldProgressRing`（1/4 圆环起画、随进度补满），满格即触发。
- **只在对卡片配了 `onMore`/`onLongPress` 时才拦截**，普通按钮保持框架默认行为
  （按下即触发、带水波纹），响应更即时。
- 长按的时长用 `TvFocusSpec.longPressDuration`（500ms，对齐
  `kLongPressTimeout` 与 Android `ViewConfiguration.getLongPressTimeout()`）。
- 手柄 Y / 遥控器菜单键（`TvKeys.more`）不需要长按，按下即开。
- **长按触发之后，这一次按下剩下的按键一起作废**（`TvKeys.markPressConsumed`）：
  长按是在按键**还按着**的时候触发的（环满即开），菜单这时才刚拿到焦点，
  而确定键在框架里同时还是 `ActivateIntent`（`WidgetsApp` 的默认键位把
  enter / space / gameButtonA / select 全映射成它，**连按键重复一起认**），
  于是按着不动的确定键接着送来的重复事件会被刚聚焦的菜单项当成"确定"——
  长按一条动态就直接执行了菜单第一项（图文 = 保存动态的截图面板、
  视频 = 稍后再看）。`TvShortcuts` 比框架自带的 `Shortcuts` 深，
  在它那里把**那个确定键松手前**的按键全部吃掉，就不会变成 `ActivateIntent`；
  只认确定键（别的键没有这层默认行为），松手即作废，不会吞掉后面的按下。
  "松手"这一下不靠按键派发去看：标记时顺手往 `HardwareKeyboard` 挂一个
  旁观的处理器（不吃键，抬起即摘掉）。没有 `TvShortcuts` 的页面（纯触摸、
  widget 测试）或焦点丢了、事件没送到焦点树时，抬起照样收得到，标记不会漏清。
  吃的是整段而不只是 `KeyRepeatEvent`：平台确实会为同一次按下送来不止一个
  `KeyDownEvent`（框架自己都为这种情况留了 `_logEventIfIrregular`，
  见 flutter/flutter#125975），多出来的那一下在 `Shortcuts` 那里一样会变成
  `ActivateIntent`。
- 开关「长按确定打开更多」关掉后，长按 = 短按（确定键完全交还框架）。

## 动态卡片（`dynamic_panel.dart`）

动态页各栏（`dynamics_tab`）、话题页、UP 主主页的动态栏（`member_dynamics`）、
收藏（`save_panel`）和动态详情（`dynamics_detail`）走的是同一个 `DynamicPanel`，
差别只有一个 `isDetail`，所以 TV 相关的东西也都写在这一处：

- **一条动态 = 一个 `TvCard`，背景（`Card`）要放进 `surface` 里**。
  `surface` 在 `FocusRing` **里面**、`InkWell` **外面**：放外面就只有内容在放大、
  卡片背景不动（焦点放大"一个白框、里面一块小的在动"）；放里面则水波纹画到
  卡片背后去了。列表卡片自己只留一个底部 `Padding`。
- **「更多」和视频卡同一套**（`showMenu`，见「弹菜单」）。原来那个
  `showModalBottomSheet` + `ListTile` 的面板在 TV 上要多一次"进面板再找第一项"，
  且和长按视频卡弹出来的菜单不是一个东西；长按 / 右键 / Y 键 / 遥控器菜单键
  四个入口不变。**折叠动态的「展开」行**也是卡内的一个 `InkWell`（`onUnfold`，
  不是卡片自己那块"点哪儿都行"的手势），它跟着卡内元素一起受开关影响。
- **动态页每一栏是各一块 `TvRegion`**（标签 `dynamics-<栏名>`，**一栏一个**）：
  进页面 / 切栏后焦点落到本栏第一条动态；列表还没加载出来时入口是空的，
  `TvRegions.entryNodeFor` 会退到 `TvTabBar` 的区域，由进栏锁落到**当前选中的
  那一栏**（见「进栏锁」）。标签必须一栏一个，是因为切走的栏被 `TabBarView`
  用 KeepAlive 留在树上、区域也还登记着，标签撞了 `TvRegions.focusFirst` 会找错栏；
  同理，切走那一栏的卡片不算入口（它们连布局都没了，见准则 3 的"看不见的也不算"），
  所以在第 2 栏上退出再进来，落点还是第 2 栏的第一条动态。
- 列表加 `TvFocusSpec.cacheExtent`（下一屏留在焦点树里，方向键才走得下去）。

### 「遥控器适配」开关（`Pref.remoteAdaptation`，设置 - 外观，默认关）

打开后**外部**的动态卡片退回"一条动态一个焦点"：

| 关（默认） | 开 |
| --- | --- |
| 卡内更多 / 转发 / 评论 / 点赞各自是一个焦点，各做各的事 | 这些按钮**不显示**，卡内元素全部 `ExcludeFocus` |
| 确定键落在哪颗按钮上就做哪件事 | 确定键整卡一个动作：`PageUtils.pushDynDetail(item)` |
| 折叠动态显示「展开x条相关动态」，点一下才看得到 | 折叠的同批动态**直接渲染**（默认展开），这一行不显示 |
| 卡片底部靠 `ActionPanel`（转发 / 评论 / 点赞那行）收边 | 图文 / 视频这类贴边内容补 12px 下内边距 |

"按确定跳到哪儿"不用额外写：`pushDynDetail` 按 `item.type` 分流（视频 / 直播 /
番剧 / 收藏夹 / 课程各自进对应页，其余进动态详情），它本来就是"点这张卡"的入口。

撤掉「更多」那一行之后还有两处收尾：

- **默认展开**：被折叠的那几条是接口给的同一批条目，只是标着
  `visible == false`（`onUnfold` 本来也就是把它们置为可见），所以开关打开时
  照常渲染它们，同时不再画 `moduleFold` 那一行——卡内元素都进不了焦点树，
  「展开」那行本来就点不到，留着只是装饰。
- **卡片底部收尾**（`DynamicPanel._tailBleeds`）：`ActionPanel` 没了之后，
  卡底由最后一块内容收尾。图文图片、视频封面+标题、直播封面+标题这类
  "贴边内容"直接贴到卡片下边缘，比转发原动态（灰底 `Container`，
  `vertical: 8`）、视频预约之类的 `additional` 面板（底色 + `vertical: 10`）
  看着挤，所以给前者补 `_remoteTailGap`（12）；后者自带底色和内边距，
  补了反而空。

**默认关**的理由：卡里直接点赞 / 评论本身就是手柄用户的常见工作流（方向键停在
爱心上按确定），只有遥控器那种"只想快点进去看"的场景才需要它。「更多」在，
长按确定 / Y 键 / 遥控器菜单键 / 右键四个入口都在。**详情页不受这个开关影响**
（`isDetail` 为真时一律走原来的样子），触摸操作也不受影响（按钮只是移出焦点树 /
不显示，触摸那条路照旧）。

## 弹层（对话框 / 底弹层）

先分两类，判据是"它有没有自己的 `FocusScope`"：

| 弹层 | 是不是路由 | 自己要做的 |
| --- | --- | --- |
| `showDialog` / `showModalBottomSheet` / `showGeneralDialog` | 是（各自的 `ModalRoute`） | 套 `TvFocusOnOpen` |
| `SmartDialog.show`、`MiniScaffold.showBottomSheet`、其它往 overlay / 当前路由里插的 | **不是** | 套 `TvPanelScope`（它顺带把 `TvFocusOnOpen` 包进去了） |

路由那一类，框架行为先记清楚，省得自己发明一套：

- push 的时候框架会把焦点交给**这条路由自己的 `FocusScope`**——面板里一个
  控件都没选中，按确定什么都不会发生，用户得先瞎按一下方向键才"活"过来。
  （这一条现在由 `TvRouteFocusObserver` 统一兜了，见「进页面的初始落点」：
  路由弹层的入口就是"面板里第一个可聚焦项"，和 `TvFocusOnOpen` 的落点一致。）
- 那条 scope 的遍历范围只包含面板内部，所以**方向键不会跑到底下的卡片上**。
- pop 的时候框架自动把焦点还回**打开面板的那个控件**，不需要自己记。

所以这一类的到手动作只有一件：**打开后把焦点送到面板里的第一项**。

```dart
showModalBottomSheet<void>(
  context: context,
  builder: (_) => TvFocusOnOpen(child: 面板内容),
)
```

`TvFocusOnOpen` 等第一帧（懒加载的列表项得先建出来）再取
`FocusScope.of(context)` 的 `traversalDescendants.first` —— 用
`FocusScope.of` 而不是 `Focus.of`：后者不允许拿到 scope 本身
（会抛 "No Focus widget ancestor could be found"）。第一帧只看不动，之后**每帧
试一次、最多 40 帧**（≈660ms）：弹层里常见的是网络列表（选集、收藏夹、评论），
第一帧完全是空的，只试一帧的话预选框要等到用户按下第一个方向键才出现。

它和路由级的入口机制（`TvRouteFocusObserver`）算出来的是同一个落点，重复套不
冲突：面板第一项在**顶栏**里时 observer 会让位（顶栏控件不算入口），
`TvFocusOnOpen` 照旧能把它接住；不走路由的弹层则只能靠它。

⚠️ 别在面板里再套一层"打开就抢焦点"的逻辑（例如给首项写 `autofocus`）：
如果有两个面板叠在一起，抢焦点的那层会把**上层**的选项抢走，用户看到的是
"菜单弹出来了但手柄完全选不了"。同理，播放器里所有"把焦点抢回来"的动作
都要先问一句 `TvRegions.isCurrentRoute(context)`。

仓库里用得最多的几个弹层已经包好了（改代码时别把它们拆掉）：
`showConfirmDialog`、`showPgcFollowDialog`、举报（`report.dart` /
`report_member.dart`）、评论卡片长按弹出的操作面板、发布页
（`pages/common/publish/publish_route.dart` 一处覆盖弹幕 / 回复 / 投币 / 保存 /
直播弹幕五处），以及画质 / 音质 / CDN / 解码那些 `SelectDialog`。
（动态卡片的「更多」原来也是这里的一员，现在换成了 `showMenu`，见「动态卡片」。）

### 不走路由的弹层：`TvPanelScope`（= `TvOverlayScope`）

`SmartDialog` 只是往 overlay 里插一层控件，`MiniScaffold.showBottomSheet` 更是
直接往**当前路由**里插一条 local history entry——两者都**和页面共用一个
`FocusScope`**，于是上面那两条规则都不成立：

- 焦点还停在打开它的卡片上，方向键就在底下的页面里转，弹层像张画；
- `TvFocusOnOpen` 送的"当前 scope 第一项"会送到**底下那页**的第一张卡片上。

所以这类弹层要套 `TvPanelScope`：先立一个自己的 `FocusScope`
（`autofocus` 会把焦点落到里面第一项），再让 `TvFocusOnOpen` 兜底，同时把这个
scope 登记进 `TvOverlayScopes`——`TvRouteFocusObserver` 的看护循环靠它区分
"焦点浮在**弹层**的 scope 上"（弹层自己管，别插手）和"焦点浮在**页面**的
scope 上"（该动手了）。

```dart
SmartDialog.show(
  builder: (context) => TvPanelScope(child: 面板内容),
)

// MiniScaffold.showBottomSheet 里已经包好了，13 个面板一起受益
(context) => TvPanelScope(child: builder(context)),
```

`MiniScaffold` 还多做了"归还"：打开面板前 `TvFocusReturn.remember(当前路由)`，
面板关掉（`onDismissed` / `onRemove`）时 `restore`——回到打开它的那张卡片上，
而不是页首。

已接：更新提示、权限提示、播放器里的 `showAttach`、`mine/controller.dart`、
`login_utils.dart`，以及 `MiniScaffold` 的全部底弹层（选集、评论输入、媒体列表、
笔记、AI 总结、简介详情、收藏夹…）。

### 弹菜单（`showMenu`）

卡片上的 ⋮ / 更多按钮弹出 `showMenu` 时有两个坑（封面那颗 ⋮ 现在也一并
去掉了，菜单入口只剩长按 / 右键 / Y 键，锚点因此只能靠卡片自己算；
动态卡片的「更多」同样走这条路，只是它的锚是作者栏那颗按钮所在的渲染盒）：

1. **手柄没有指针位置**，`showMenu` 需要一个 `RelativeRect`。做法是拿**这张
   卡片自己的 `RenderBox`** 中心当锚点——`context` 的渲染盒就是卡片本人：
   ```dart
   final box = context.findRenderObject();
   final offset = box is RenderBox && box.hasSize
       ? box.localToGlobal(box.size.center(Offset.zero))
       : Offset.zero;
   showMenu<void>(context: context, position: PageUtils.menuPosition(offset), ...);
   ```
2. **`requestFocus: Pref.tvFocus`**：不给的话菜单弹出来焦点还留在列表上，
   方向键和确定键全被列表吃掉（看得见、点不着）。
3. **`PopupMenuItem.onTap` 里不要再写 `Get.back()`**：框架的
   `handleTap` 是"先 `Navigator.pop` 关菜单、再调 `onTap`"，自己再 pop 一次
   关掉的就是**整个页面**。要在菜单项里弹对话框是安全的（那时菜单已经关了），
   对话框自己会拿到路由级落点。

⚠️ 别为了"手柄也能开菜单"给 `InkWell` 同时加 `onTapUp` 和 `onTap`：指针抬起时
`TapGestureRecognizer` **两个都会调**，菜单会弹两遍。只配了 `onTapUp` 的
InkWell 在手柄上属于"能聚焦但按确定没反应"（框架的 `ActivateIntent` 只认
`onTap`），正确做法是在焦点节点上接管确定键（`FocusRing.onKeyEvent` +
`TvKeys.isOk` + `isFirstPress`，见 `PopupListTile`）。

## 返回键：一套语义

`B` / `Esc` / 遥控器返回 / 鼠标侧键全部走 `appBack()`：

```
TvBack.dispatch()            // 1. 先给"当前场景"的拦截栈
 → SmartDialog.dismiss()     // 2. 有弹窗先关弹窗
 → GetPageRoute.popDisposition // 3. WillPopScope 语义
 → navigator.pop()           // 4. 最后才退页面
```

`TvBack.push(handler)` 是给"返回键要先关自己的控件、再退页面"的场景准备的
（栈顶先拿到这一下），handler 返回 `false` 表示不接手。**播放器没有用它**：
它那句"先收控制条"要同时盖住桌面 Esc（跑在焦点树之前，`Focus.onKeyEvent`
抢不到）、安卓返回键（系统直接 `popRoute`，**根本不经过 `appBack()`**）和手柄 B，
所以规则挂在三条路唯一的交集——路由的 `popDisposition`
（`onPopInvokedWithResult`）上，见「返回键：全屏里亮着 OSD 就先收 OSD」。

为什么需要这个栈：桌面端的 Esc 是在 `FocusManager.addEarlyKeyEventHandler`
里处理的（`main.dart`），它跑在**焦点树之前**，`Focus.onKeyEvent` 抢不到；
手柄 B 走的是正常的焦点树派发，两者必须在同一个地方汇合。

## 媒体键

播放器活着的时候把自己压进 `TvMediaKeys`：

```dart
TvMediaKeys.push(TvMediaKeyTarget(onPlayPause: ..., onSeekBackward: ...));
// dispose 时
TvMediaKeys.remove(target);
```

`TvShortcuts` 只把媒体键转给栈顶（最后压进来的那个），栈空时放行。

---

## 常用组件速查

| 需求 | 用 |
| --- | --- |
| 一个可聚焦的卡片/列表项 | `TvCard`（同时给出焦点环、长按确定、长按进度环） |
| 把卡内次要操作移出焦点树 | `TvCardSubAction` |
| 弹层打开后自动选中第一项 | `TvFocusOnOpen`（`showDialog` / 底弹层用） |
| 进页面时预选框落在哪儿 | 自动：`TvRouteFocusObserver` + `TvRegions.entryNodeFor`，页面只需用 `TvRegion` 划出内容区 |
| 退栈时把焦点还给"从哪儿进的那一项" | 自动：`TvFocusReturn`（`TvRouteFocusObserver` 里调用；`MiniScaffold` 的底弹层进出时也自己记一次） |
| `SmartDialog.show` / `MiniScaffold` 底弹层 | `TvPanelScope`（= `TvOverlayScope`）：它们不走路由、和页面共用一个 scope，必须自己立一个 |
| 鼠标点一下就让焦点跟过去（预选框隐藏） | 自动：`TvInputMode`（`main.dart` 里 `init()` 一次）+ `TvRegions.focusAt` |
| 判定"这一下是按键还是鼠标" | `TvInputMode.fromKeys`（切页交接、"鼠标别抢焦点"之类的地方用它） |
| 滑块（音量/倍速/字号…） | `TvSlider`（不套的话方向键会被滑块吃掉，出不来） |
| 给普通按钮/列表项/标签页加焦点环 | `FocusRing`（`builder` 拿 `focusNode` 交给内部控件） |
| 包不进去的控件（框架生成的返回键、裸 `IconButton`……） | 自动：`TvFocusOverlay`（挂在 `main.dart` 的 `_builder` 上，见「焦点必须可见」）|
| 给 `ListTile` 加环（压掉框架自带底纹） | `listTileFocusRing`（`ListTile.focusColor` 置透明、节点交给 `ListTile`） |
| 顶部标签栏（预选框 + 焦点即切换 + 进栏锁 + L1/R1） | `TvTabBar`（`regionLabel` 要唯一；"标签=滚到区块"的页面传 `onFocusTab`） |
| 平板抽屉里的导航项 | `TabletNavItem`（圆角矩形环 + 指示条；头像/消息/搜索那三颗圆按钮用 `FocusRing(circle: true)`） |
| 框架自己的导航项（M3 底栏 / 侧栏） | `TvNavDestination`（外壳只当环的挂点，落点仍是框架的 `InkWell`） |
| 页面/面板的焦点边界 | `TvRegion`（标签要唯一） |
| 把焦点送进某个区域（切栏、跳转） | `TvRegions.focusFirst(label, index: n)` |
| 焦点寄存与恢复 | `TvFocusMemory.park()` / `restore()` / `focusIndex(i)` |
| 输入框（按确定才输入、返回键脱出） | `TvTextField`（宿主自己持焦点时传 `editFocusNode` + `navFocusNode`） |
| 上一栏 / 下一栏 | 实现 `TvSectionSwitcher`，按键已由 `TvShortcuts` 全局接好 |
| 返回键先关自己的控件 | `TvBack.push` |
| 让播放器里"只能点"的控件能被手柄停住 | `TvButton`（`onTap` 为空则不占焦点；要把节点交出去当锚点就传 `focusNode`） |
| 可聚焦的进度条（左右微调、抬起才 seek） | `TvSeekBar` + 实现 `TvSeekBarHost` |
| 让焦点落在进度**指示器**上（手柄播放器模型） | `TvSeekBar(focusOnThumb: true)` + `ProgressBar(thumbFocusRing:)` |
| 播放器画面当成一个大焦点（预选框+确定键进全屏） | `TvPlayerSurface`（只在手柄播放器模型下装，见 `isPlayerTvMode`） |
| 焦点"进到某块区域"时把落点锁到指定控件 | `TvEntryLock`（播放器上下栏就是这么锁返回键 / 播放暂停的） |
| 播放器 OSD（控制条照超时收、焦点由它拉回画面） | `PlayerTvOsd`，按键层是 `PlayerFocus`（按键只负责重新计时：`keepControlsAlive`） |
| 播放器返回键（全屏里先收 OSD） | `PlPlayerController.hideControlsOnBack`（挂在 `onPopInvokedWithResult` 上，三条返回路径同一个落点） |
| 看片时藏鼠标光标 | `PlPlayerController.playerCursor`（控制条收着 → `SystemMouseCursors.none`） |
| 响应媒体键 | `TvMediaKeys.push` |
| 键位判定 | `TvKeys.isOk / isBack / isMore / isPrevSection / isNextSection / isDpad / isFirstPress` |
| 尺寸与时长常量 | `TvFocusSpec`（scale / duration / radius / borderWidth / longPressDuration / safeSpace / cacheExtent，播放器另有 playerRadius / surfaceRadius / seekStep） |

## 新增一个页面时的检查清单

1. 每块独立导航区域套 `TvRegion`，网格/列表加 `TvFocusSpec.cacheExtent`
   （`scrollCacheExtent:` 参数）。内容区用默认的 `kind` 就行；标签栏交给
   `TvTabBar`（它自己标成 `TvRegionKind.tabBar`，进页面时不会被当成入口）。
   套好区域，进页面时预选框就会落在第一个内容区的首项上，**不需要**再给
   列表首项写 `autofocus`；想指定别的入口才用 `autofocus`，或者把目标单独套
   一个 `TvRegion`（见「进页面的初始落点」）。
2. 所有卡片/列表项换成 `TvCard`，卡内按钮换 `TvCardSubAction`。
   顶栏/工具栏里的圆形按钮用 `iconButton()` / `ToolbarIconButton`（它们自带
   `FocusRing(circle: true)`）；其余裸 `IconButton` 不写也不用慌，兜底层
   （`TvFocusOverlay`）会补，但补出来的只有一根描边。
3. 需要「更多」的卡片传 `onMore`（长按确定与手柄 Y 自动接好）。
4. 刷新 / 删除 / 加载更多前后各加一行 `TvFocusMemory.park()` / `restore()`。
5. 需要左右切栏的页面套 `TvSectionSwitcher`，并在切栏后把焦点送进新栏
   （`TvRegions.focusFirst`），新栏没接适配就把焦点放到 TabBar 上。
   标签栏一律用 `TvTabBar`（它自带区域，焦点在标签栏里时 L1/R1 已经能切，
   从内容区按 ↑ 回来也一律落在当前那一栏）；
   只有"切完栏还要额外做事"（进新栏第一张卡 / 滚到对应区块）时才需要
   `TvSectionSwitcher`。
6. 每个输入框套 `TvTextField`（里面的 `TextField` 要"一进来就能打字"的话
   补 `autofocus: !Pref.tvFocus`）；宿主自己请求焦点的地方按 `Pref.tvFocus`
   决定落在导航态还是输入框上（见「输入框」一节）。
7. 每个滑块套 `TvSlider`（见「滑块」）；每个 `showMenu` 的锚点用自己卡片的
   中心并开 `requestFocus: Pref.tvFocus`（见「弹菜单」）；`SmartDialog.show`
   的弹层套 `TvPanelScope` / `TvOverlayScope`（见「弹层」）——**不走路由的弹层
   一律要套**，不套的话焦点还在底下那页上，方向键也跑不到弹层里。
8. **被主界面导航栏指着的那一页要给一个 `tvRegion` 标签**（首页 / 动态 / 我的
   那三页，见「按键切页之后把焦点接走」）：按键切页之后焦点要送进"这个导航项
   对应的当前内容区"，主界面的 `_tvRegionOf` 只能按标签反查。新加一个子栏 /
   分类时同步补上，返回 `null` 就是"焦点留在导航项上"。
9. 跑 `flutter test test/tv_focus_test.dart`，`flutter analyze` 零新增告警。
10. 动播放器（`PlayerFocus` / `PlayerTvOsd` / `TvSeekBar` / `TvPlayerSurface`）时记得
   **视频页和直播页共用**这套代码、共用同一个「手柄播放器模型」（`isPlayerTvMode()`
   不分页），改键位表两页一起变（差别只在直播没有进度条、`isLive` 会把快进短路）；
   控制条上的新控件一律用 `TvButton` 包（要当锚点就把 `focusNode` 透传出去）；
   新按钮要能"进栏即落点"就把 `TvRegions.registerAnchor` 登记上，
   别在按键层里写方向判断。**跟返回键有关的行为别写进 `PlayerFocus`**：
   桌面 Esc / 安卓返回键都到不了那里，规则要挂在 `PlPlayerController`
   上（见「返回键：全屏里亮着 OSD 就先收 OSD」）。

### 写测试时的几个坑（`test/tv_focus_test.dart` 顶部有现成脚手架）

- `testWidgets` 的函数体跑在 fake async 里，`await Hive` 这种**真实磁盘 I/O 会卡死**；
  于是它落盘的 Future 靠真实事件循环完成，扔着不管则会把**下一个测试**的 pump 一起拖住。
  Hive 写入一律走 `await tester.runAsync(() => ...)`。
- **先 `pump()` 再 `pump(时长)`**：`AnimationController` 的 ticker 从**首次** tick
  起算时间，一上来就 `pump(600ms)` 的话第一帧只算 0ms，长按判定不会触发。
- 测试卡片的 `TvCard` 必须给一个动作（通常 `onTap: () {}`），否则按上面的
  `isWidgetEnabled` 规则它不可聚焦，测试会以"焦点根本没动"的方式失败，
  很容易被误读成焦点系统的 bug。
- **切过栏就要把动画跑完**：`TabController.animateTo` 会在指示器上起一个 300ms 的
  ticker，测试结束时它还活着的话，框架拆树时报
  「An animation is still running even after the widget tree was disposed」，
  断言全过的用例也红——`TabBar` 那组用 `finishSwitch(tester)`（`pump()` +
  `pump(400ms)`）收尾。
- **标签栏要"移到某一栏"就用按键走**（`sendKeyEvent(arrowRight)`），别
  `TvRegions.focusFirst('<label>', index: n)`：后者是"从栏外进来"，会被进栏锁
  拉回当前栏——想测几何寻焦本身，得在栏外放一个可聚焦控件（那组的进栏锁用例
  就是这么写的）。
- **换页 / 弹层的用例要换一台脚手架**：上面那台 `pumpHost` 没有
  `NavigatorObserver`，换页之后没人管入口这一套；`pumpRouter` 装了
  `TvRouteFocusObserver` 和 `TvShortcuts`（按键要经过它才能测"第一下唤进页面"）。
  换页后的断言一律用 `FocusManager.instance.primaryFocus`，比找某个
  `FocusNode` 更贴近"用户看到的预选框在哪"。
- **`TvInputMode` 那一组必须放在文件末尾**：它的 `init()` 装的是**进程级**监听
  （`pointerRouter` + `HardwareKeyboard`），会把 `highlightStrategy` 翻成
  `alwaysTraditional` / `alwaysTouch`，后面任何用例都会跟着变——放在中间，
  那些用例的"预选框没画"断言就会莫名其妙地红。
- **"焦点被列表刷新掉了"这类用例要真删节点**：只 `setState` 重建是不够的，
  要像「退栈归还：离开时那张卡被删了」那样把节点从 `ValueNotifier` 的列表里
  拿掉。这条用例正好钉着 `TvRegions.isPainted` 那个坑（框架 `detach` 不清
  `FocusNode.context`，element 还会被按位置复用给别的节点），去掉
  `nearestScope == null` 那条检查它就会红。
- **别用 `find.byType(Focus)` 数"我们自己的焦点节点"**：框架控件内部遍地是
  `Focus`（`InkWell`、`NavigationDestination`…）。要挑自己那枚就用
  `find.byWidgetPredicate((w) => w is Focus && !w.canRequestFocus)`
  之类的特征，或者按祖先 `find.descendant` 找（`TvNavDestination` 那组就是
  这么写的）。
- **测兜底环（`TvFocusOverlay`）要另起一台脚手架**：它得挂在 `Navigator` 之上
  （放 `MaterialApp.builder` 里），挂在 `home` 里面压不住 push 上来的页面。
  「兜底焦点环」那组的 `pumpOverlay` 就是 `main.dart` 的 `_builder` 的缩影。
  两个坑：**焦点/位置变过之后要 `pump()` 两次**（第二帧才是兜底层帧末采样
  `setState` 出来的那一圈），以及**别拿 `find.byType(IconButton)` 的矩形当期望值**
  ——那是 48 的点击区，环贴的是 40 的可视区（`_InputPadding` 会多套一圈），
  写死尺寸的断言会差 8px。

## 已确认的取舍

- **兜底环（`TvFocusOverlay`）是"帧末采样"，移动中慢一帧**：它靠
  `addPostFrameCallback` 搭别人已经在出的帧（自己不请求帧——常驻 60fps 空转对
  电视盒子不划算），所以几何在**帧末**才采到，滚动/转场动画里环会比控件慢一帧。
  换精确同步就得每帧 `markNeedsPaint`，那等于让机器一直出帧；而环要画的东西
  （一根描边）本来也不参与布局，不值得。静止时两者完全一致。
- **兜底环不缩放，只画描边**：控件不是它的子树，1.04 倍缩不了。对图标按钮这类
  背景透明的控件本来也看不出来（`FocusRing` 那时缩的其实只有 24dp 的图标，
  4% = 1dp），但对有底色的控件差别是有的——所以"该自己套环"的地方仍然要套，
  这一层只管"包不进去"的那些（见「焦点必须可见」）。
- **兜底环的裁剪是"近似"的**：用的是框架的
  `describeApproximatePaintClip`，它明确说了是 approximate——`ClipOval` 这类
  返回的仍是整块 `Offset.zero & size`。所以这一层只保证不画到**确定**看不见的
  地方（`Offstage`、滚出视口），不保证裁得一丝不差。要对椭圆裁剪精确，得自己
  遍历 `RenderClipOval.clipper`，不值当。
- **不逐处给 `IconButton` 包 `FocusRing`，也不走 `iconButtonTheme` 描边**：
  前者包不全（`AppBar` 的返回键在框架内部新建，应用层没有扩展点），而且以后
  新写的裸按钮还会漏；后者（`ButtonStyle.side` 描边）虽然一处管所有，但没有
  1.04 倍放大，还会把 `IconButton.outlined` 的默认边框一起改掉，且和"输入源
  切换"接不上。挂在 `_builder` 上的兜底层一处管全部，包括框架内部和以后新写的
  控件，判定口子和 `FocusRing` 共用（`FocusRing.highlightEnabled`）。
- **不做 `NavigationMode.directional` 那一套来"顺便"解决可见性**：它的代价是
  全局的，见下一条。
- **不用 `NavigationMode.directional`**（Flutter 自带的 10-foot 模式）。
  它会把禁用的按钮、`TextField`、`ExcludeFocus` 之外的东西统统变成可聚焦，
  还会把 `Slider` 的方向键改成"左右调节"——好处我们已经有别的办法拿到，
  代价却是全局性质的，难以局部回退。需要在播放器里用的时候，
  用 `MediaQuery(navigationMode: ...)` 包住那一小块。
- **进页面的落点做成路由级（`TvRouteFocusObserver`）而不是逐页 `autofocus`**：
  逐页写要在几十个页面里各挑一个"首项"，而列表是懒加载的、首项未必第一帧就
  在，页面还得自己处理"数据来了重建之后谁说了算"。observer 一处管全局，
  页面只需要把区域套对。代价是页面还没有入口时，**第一下方向键会先被吃掉**
  （那时页面里没有任何控件有焦点，按一下只是把预选框唤到入口上）——
  这是电视上共通的"第一下亮出光标"手感，不是卡顿。同理，顶栏控件一律不当
  入口：宁可停在内容首项，也不要一进页面预选框就趴在返回键上；**看不见的项
  也不当入口**（预选框画在屏幕外，用户看到的就是"焦点又丢了"），实在一个都
  看不见时才退回树序第一项。
- **「遥控器适配」默认关**：它拿掉的是"方向键停在爱心上按确定"这条手感，
  而手柄用户里这么用的人不少；遥控器上"只想快点进去看"的需求才值这一刀，
  所以做成显式开关而不是默认行为。开关打开后卡里的转发 / 评论 / 点赞都不显示
  也不进焦点树，要用得进详情页——这正是这个开关本身的意思。
- **动态卡片的缩放要连背景一起放大，靠的是把 `Card` 放进 `TvCard.surface`**：
  `surface` 的语义就是"会被 `FocusRing` 一起缩放的背景"，位置在 `FocusRing`
  里面、`InkWell` 外面。放外面只有内容在放大，放里面水波纹会画到卡片背后。
  列表卡片因此不再自己包 `Card`/`Padding`，只留底部间距。
- **动态页的进页面落点用"一栏一个 `TvRegion`"，不写 `autofocus`**：
  区域里第一个可聚焦项就是本栏第一条动态，列表没加载出来时自动退到当前
  选中的那一栏；写 `autofocus` 反而会和"数据来了重建列表"打架（首项未必第一帧
  就在）。标签一栏一个不是洁癖——切走的栏被 KeepAlive 留在树上，标签撞了
  `TvRegions.focusFirst` 会找到别栏去。
- **不移植 blbl 的 `DpadGridController`**：Flutter 的几何 traversal 已经覆盖
  它的绝大多数功能，剩下的缺口只有本文这六个准则。
- **焦点框缩放不处理 z 序**：1.04 倍 + 12dp 间距下不会压到邻卡，
  所以不做 `clipChildren`/层级提升（Flutter 里对应 `Overlay` 提升）。
- **弹层里的拖拽把手也移出焦点树**（`TvCardSubAction` 包一层）：它是个
  `InkWell`，留着就是"面板第一项是把手"这种荒唐的默认落点。
- **收藏页（视频 / 番剧 / 笔记 / 专栏）的列表项统一成 `TvCard`**：卡内那个
  右下角的「更多 / 取消收藏 / ⋮」在触摸上照旧可点，但手柄模式下移出焦点树
  （`TvCardSubAction`），改由**长按确定 / Y 键**触发——正好对上用户那句
  "长按确定绑定到封面上的更多按钮"。触摸的长按语义（番剧/笔记是进多选）
  不变：`onLongPress` 只留给触摸，`onMore` 才是手柄那条路。
- **视频卡 / 直播卡封面上的 ⋮ 已经整个拿掉**：这颗图标占着封面右下角，
  又只在指针设备上顺手，改由卡片自己接三种入口——触摸长按、桌面右键
  （`onSecondaryTap`，移动端传 `null`）、手柄 Y / 遥控器菜单键，三者都走
  `VideoPopupMenu.show`（`showMenu`，锚在卡片自身中心，见上一节）。
  同一批删掉的还有它的老搭档「长按弹封面预览」面板（`imageSaveDialog`）：
  封面上的分享 / 保存封面图随之消失，稍后再看等仍在菜单里，视频详情页
  也照旧能存封面。`VideoPopupMenu` 因此不再是个 widget，只留静态 `show`。
- **`ListTile(enabled: true, onTap: null)` 是排版技巧，不是疏忽**：
  `enabled` 只管配色，没有手势回调就不会多一个焦点节点（面板项外面套
  `FocusRing` 才是唯一的焦点）。反过来，`enabled: false` 会把文字画成灰色。
- **手柄播放器模型拿掉的正是"↑/↓ = 音量"**：遥控器根本没有音量键，
  而**框架区分不出"遥控器方向键"和"键盘方向键"**（都是 `arrowUp`），
  所以视频页和直播页的键盘 ↑/↓ 都一起变成焦点导航——设置项的说明文字里写明了。
  想要音量就走 `M` 静音/音量面板，或者把「手柄/遥控器模式」整个关掉。
- **非全屏按确定 = 进全屏，不照搬 blbl 的"确定 = 播放/暂停"**：这是需求明确
  指定的（"在视频上点击 A、确定、回车等视为全屏播放视频"）。代价是非全屏时
  方向键够不到 OSD 上的控件（那一层在非全屏压根不进焦点树），要操作控件得先进全屏；
  对照的 BBLL 也是这个分工。全屏之后确定才是播放/暂停（这时它就是 BBLL 的手感）。
  直播页跟着一起变：它原来是"确定 = 进控制条 / 播放暂停"（只在那一条分支里），
  现在两页同一个模型。
- **焦点停在控制条里不豁免自动隐藏**（老写法是"焦点在栏里就一直不收"）：
  豁免的后果是手柄把预选框停在一块**永不消失**的浮层上——用户按不动它、
  也等不到它自己走，只有画面那块"一直亮着框"。改成"到点照收"之后，
  代价挪到了另一头：人一直在栏里操作就得**一直按**（每次按键重新计时），
  停手的那一下栏会收掉、焦点被拉回画面。两害相权，后者是电视上通行的做法
  （遥控器"没动作就淡出"），前者则是个死状态。
- **非全屏 / 桌面键盘模式下返回键不吃"先收 OSD"**：非全屏的 OSD 是鼠标/触摸的
  浮层（手柄模型下整层不进焦点树），按返回就是"退页面"，吃成两下会让触摸用户
  为了退出多点一次；桌面键盘模式（「手柄/遥控器模式」关着）的 Esc 保持
  "退出全屏"的老语义，桌面用户对这个键有预期。所以 `hideControlsOnBack` 只认
  "手柄模式 + 全屏/窗口全屏 + OSD 亮着"这一个组合。
- **看片时的鼠标光标跟控制条走，不再要求全屏**（老写法是
  `!showControls && isFullScreen`）：窗口里那块视频同样得"看片时不挡着"。
  指针离开视频区域（`onExit` 收栏、光标交回页面）之后没有副作用——藏光标的
  `MouseRegion` 只覆盖播放器自己那一块。再晃一下鼠标光标立刻回来，
  靠的是 `RenderMouseRegion.cursor` 的 setter 会 `markNeedsPaint`。
- **OSD 顶栏那颗「返回」按钮刻意跳过 `hideControlsOnBack`**（直接调
  `onBackButton`）：它只在控制条亮着时才看得见，被"先收控制条"吃掉就是
  "按了没反应"——它要的正是退出（全屏 → 退页面）。视频页和直播页共用这一颗。
- **桌面画中画（`isDesktopPip`）里 OSD 上的按钮手柄够不到**：画中画只能从非全屏
  进（`enterDesktopPip` 在 `isFullScreen` 为真时直接返回），而非全屏下整层 OSD
  是 `ExcludeFocus` 的，所以画中画窗口上那排按钮只有触摸能点——直播页偏偏还会在
  这个模式下多出一个「返回」（`showBack = isFullScreen || isDesktopPip`），
  它跟着一起不可聚焦。两页一样。要修得先让 `isDesktopPip` 变成可监听的状态
  （控制器上现在是普通 `bool`，改了不触发重建），不值得为这一条改控制器接口。
  Android 的画中画是另一回事：activity 级、不切 `isFullScreen`、窗口本身也拿不到
  按键输入，不在这套语义的讨论范围里。
- **全屏收栏时"方向键唤栏"而不是"方向键自己进栏"**：BBLL 是"上下栏一露出来焦点
  就落在播放/暂停上"，我们把它拆成两步——先亮栏（焦点送到播放/暂停按钮，
  按钮被按顺序走过，不判方向），再让用户从那里按方向键走进栏里。
  **进全屏那一刻栏本来就亮着的话，等于第一步已经发生过了**，于是直接落在同一个
  点上（`_enterFullScreen`），两种情况用户看到的都是"栏亮着、预选框在播放/暂停"。
  好处是方向键的语义只有一条（唤栏），不用在画面这一层判"↑ 进下栏还是上栏"；
  代价是亮栏那一帧焦点其实已经不在画面上了，所以画面在那一帧同步 `hideRing`。
- **B 键分两处判，看焦点在不在控制条里**（`PlayerFocus`）：焦点在画面/页面里时
  这一层直接吃掉它（控制条亮着就只收控制条 + 焦点回画面，收着就放给全局层当
  "退出"）；焦点在控制条里时它**不吃**，只把自动隐藏重新计时，然后让这一下走到
  全局那条路上去——桌面 Esc 和安卓返回键都到不了焦点树，规则必须写在三条路的
  共同落点（`hideControlsOnBack`）上，写在 `PlayerFocus` 里反而会漏掉那两个。
- **上下栏的落点用进栏锁，不在按键层判方向**：从画面按 ↑ 进底栏，几何上会落到
  "正上方那根进度条"，而手柄用户要的是播放/暂停按钮。进栏锁（`TvEntryLock`）
  只认"焦点从栏外进到栏里"，栏内移动照旧几何寻焦——这样以后往栏里加控件、
  挪布局都不用改按键逻辑。锚点没登记时它什么也不做，所以"那颗按钮不在树上"
  的情况（直播页非全屏时的返回键）行为自然退回几何寻焦。
- **进度指示器的预选框画在 `RenderProgressBar` 里**（`thumbFocusRing`），
  没有改 `_heightWhenNoLabels()`：和 `thumbGlowRadius` 一样"允许画到控件边界外"，
  这样焦点态不会让进度条的布局跳一下。
- **`TvRegions.registerAnchor` 允许在 `build` 里反复调用**（同一个节点直接跳过）。
  播放器画面的锚点要在运行中换人（开关「手柄/遥控器模式」），只有 build 才知道
  当前该是谁登记的，`initState`/`didUpdateWidget` 配不出这个顺序。
- **`focusAnchor` 有一个 `checkRoute: false` 的用法**（只在 `dispose` 里用）：
  它的默认检查要问 `ModalRoute.of`，而 `dispose()` 里查祖先框架会直接抛断言。
  拆树时"这一页还在不在最上层"本来也无从判断——锚点自己那几句有效性检查
  （还挂得住、还活着）就够了。
- **「焦点即切换」默认开着，代价是扫一遍标签栏就会发一串请求**（PGC 时间表、
  历史、直播分区这类页面每切一栏就加载一次）。这是对齐 blbl 的默认值
  （`tabSwitchFollowsFocus`）——手柄用户要的就是"移过去就到了"；不想这样就关掉
  「标签跟随焦点切换」，关掉后焦点照样有预选框，只是要按确定才切。
- **进栏锁让"把焦点送到某个标签上"只在它正好是当前栏时才有效**
  （`TvRegions.focusFirst('<label>', index: n)` 的 `n`）。目前两处传 `index:`
  的调用（首页 / 视频页 `_switchTab`）都是"先 `animateTo(target)` 再送焦点"，
  落点就是当前栏，所以没有影响；真要"焦点在这一栏、页面在那一栏"就只能
  先切栏。换来的好处是：从内容区按 ↑ 回来永远落在看得见的那一栏上，
  而不是正上方那个标签（更不会顺手把页面切走）。
- **没写 `TvSectionSwitcher` 的页面，L1/R1 落在标签栏上而不是新栏的内容里**：
  焦点在标签上看得见，按一下 ↓ 就进新栏列表，但少一次"直接进第一张卡"的便利。
  想省这一步就在页面上声明 `TvSectionSwitcher`（见准则 2）。
- **标签栏自带的 `TvRegion` 让 28 处原本没有区域的标签栏多了一个 FocusScope**：
  ←/→ 走到两端时会交给相邻区域（`TraversalEdgeBehavior.parentScope`）而不是
  原地停住。这和页面里其它 `TvRegion` 的既定语义一致，方向键更不容易"卡住"。
- **1.04 倍缩放在滚动标签栏的最边上有不到 1px 会被裁**（`SingleChildScrollView`
  的裁剪）：blbl 靠 `clipChildren=false` 解决，Flutter 这边视觉上看不出来，
  不值得为它改滚动结构。要根治得把栏高从 42 加到 50 以上（标签格子的固有高度
  是 48，被 42 夹着），比这 1px 贵得多——「可见（焦点预选框）」里那条"贴着裁剪边
  要么留余量、要么 `scale: 1.0`"的规则，这里选的是"接受"。
- **不移植 blbl 的"内容网格左右边沿切栏"**（`switchToNextTabFromContentEdge`）：
  Flutter 的几何 traversal 表达不了"网格左边沿"这个条件，而 L1/R1 加上"焦点在
  标签栏上按 ←/→"已经覆盖了同一个需求。
- **`dynamics_topic` 的排序 `ToggleButtons`（排序选择器，不是 tab）不在本次范围**。
- **鼠标点击即焦点靠翻全局的 `highlightStrategy`，代价是 Material 自带的
  `focusColor` 也会一起收起来**——这正是"鼠标点了不显示预选框"想要的，而且
  一处开关就让 `FocusRing` 和框架控件同步（两边读的都是 `highlightMode`）；
  `Pref.tvFocus` 关掉时还原 `automatic`，触摸用户完全无感。反过来，翻过策略之后
  框架那半边的"触摸按下切 `touch`"也失效了，所以触摸那一路得我们替它做
  （见「焦点框只在按键之后出现」）。
- **`TvRegions.focusAt` 用"矩形包含 + 取面积最小"而不是真正的 hit-test**：
  好处是不碰 release 下不可用的调试 API、并天然跳过 `ExcludeFocus` 的卡内子动作；
  代价是"点在被遮挡的控件上"这类极端布局会命中几何上的最内层。一次点击扫一遍
  节点树，可忽略。
- **退栈归还的优先级是"记住的节点 → 同一区域的同一个序号 → 页面入口"**：
  卡片被刷新掉时落到"大概同一个位置"而不是页首，比框架自带的"最近一次聚焦的
  节点"（节点没了就什么都不给）稳。它**只在焦点浮着时**动手——页面里有控件
  拿着焦点（`autofocus`、`TvFocusMemory` 的选择）就一个指头都不许伸。
- **不走路由的弹层必须自己立 scope（`TvPanelScope`）**，而不是靠 observer 兜：
  它们和页面共用一个 `FocusScope`，observer 看到的"当前 scope"就是底下那页，
  `TvFocusOnOpen` 送的第一项会送到底下页面上。`MiniScaffold` 的底弹层因此还要
  自己 `TvFocusReturn.remember` / `restore` 一次（进出面板都**不是**路由事件，
  observer 收不到）。
- **长按确定触发后，这一次按下剩下的按键一起作废**（`TvKeys.markPressConsumed`）：
  长按是在按键**还按着**的时候完成的（环满即开），而确定键在框架里同时还是
  `ActivateIntent`（`WidgetsApp` 的默认键位连按键重复一起认），不挡的话长按
  刚打开的菜单会立刻执行第一项——图文动态弹出"保存动态"的截图面板、视频动态
  直接进稍后再看。另一条路是改全局键位（`SingleActivator(includeRepeats: false)`），
  但那会一并改掉"按住确定连点"这类行为（比如播放器上按住快进）；
  这里选的是只作废"已经被长按用掉的那一次按下"，松手即恢复。
