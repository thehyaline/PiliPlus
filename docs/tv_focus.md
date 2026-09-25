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
描边画在控件**自己的边界内**（`Positioned.fill` + `Border.all`），
所以不会被视口裁切，也不存在和邻卡的 z 序问题。

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

路由 push/pop 的焦点恢复 Flutter 自己会做，**不需要** blbl 的 `FocusReturn`。
只有"同一个路由内焦点被重建"才需要 `TvFocusMemory`。

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

⚠️ 动帧序的时候要小心 `autofocus`：它是**帧末的 microtask** 才应用的，
所以 observer 在换页那一帧之后**跳过一帧**再动手。抢在它前面会把页面自己的
`autofocus` 顶掉——`_Autofocus.applyIfValid` 只看"这个 scope 里有没有
`focusedChild`"，被顶掉之后不会再补。跳过的那一帧同时也让退栈的焦点恢复先落地。

## 4. 焦点框只在按键之后出现

直接用 `FocusManager.instance.highlightMode`（`FocusRing` 已经读了它），
不要自己监听输入类型。触摸用户永远看不到焦点框，触屏设备上甚至不需要
考虑这个开关。

## 5. UI 为手柄让路

- 网格左右各留 8dp 安全内边距，避免 1.04 倍缩放被视口裁切
  （blbl：`focus_safe_padding_h = 8dp` + RecyclerView `clipChildren="false"`）。
  Flutter 里用 `TvFocusSpec.safeSpace`。
- 卡片间距 ≥ 12dp 时，1.04 倍缩放的溢出不会压到邻卡，**不需要**处理 z 序。
  如果将来把间距改小，必须同时把缩放降到 `间距 / 2 / 卡片尺寸` 以下。
- 必要时可以缩小或隐藏卡内次要按钮——TV 上没人去点 29×29 的三点按钮。
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

播放器没有单独的子开关：**视频页的「手柄播放器模型」也挂在 `Pref.tvFocus` 下**
（判定 `isPlayerTvMode(isLive:)`），里面同时包含"非全屏整块画面是一个焦点"
和"全屏下方向键唤栏 / 确定键播放暂停"这两条。遥控器用户觉得键盘被一起改了
（框架区分不出遥控器方向键和键盘方向键），要老键位就整个关掉「手柄/遥控器模式」。

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

## 主界面导航栏（平板抽屉）

设置项「优化平板导航栏」（`Pref.optTabletNav`，只在平板上、且导航项多于一个时
生效）下，主界面的左侧是一条 96 宽的 `NavigationDrawer`：上面是头像 / 消息 /
搜索，下面是首页 / 动态 / 我的。**形状按"这一格是什么"分两种**：

| 元素 | 形状 | 出处 |
| --- | --- | --- |
| 头像 / 消息 / 搜索 | 圆（`FocusRing(circle: true)`） | blbl 用 `ShapeableImageView` + `shapeAppearanceOverlay=Circular`，焦点描边贴着圆边 |
| 首页 / 动态 / 我的 | 圆角矩形 16dp + 12% 主题色底纹 | blbl 的 `item_sidebar_nav.xml`（10dp 圆角、描边只在聚焦时出现）+ `blbl_focus_bg_round.xml` |

导航项的 16dp 不是随手定的：抽屉的选中指示条（`indicatorShape`）就是这个形状，
两者共用 `tabletNavTileRadius`（`pages/main/widgets/tablet_nav_item.dart`）——
`_sideBar()` 把它传给 `NavigationDrawerTheme.indicatorShape`，`TabletNavItem`
拿它画焦点环。

> 不过屏幕上看到的两者并不完全一样：指示条的默认宽度是 336（框架那份 defaults
> 假设抽屉有 360 宽），而这条抽屉只有 96，所以实际渲染的是被 `Stack` 裁掉两头的
> 72×56 长条，圆角在裁剪线外面、看不见；焦点环的圆角是手工画的，看得见。
> 想让两者真的一致，得按可用宽度夹一下 `NavigationIndicator.width`——
> `TabletNavItem` 没这么做（先保持改动前的观感），要改就改在一处。

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
  原来那个 `onDestinationSelected`（`setIndex(index)`）。

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
- **平板侧栏（`NavigationRail`）和手机底栏的导航项还没适配**：它们走的是框架的
  `NavigationRailDestination` / `NavigationBar`，和 destination 同一个问题
  （节点自建、没有扩展点）。本文这一节只覆盖抽屉那一支；那两支各自的适配写的时候
  照 `TabletNavItem` 这份抄。

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

## 播放器：三套键位 + 三层焦点

播放器是唯一一个"方向键另有语义"的地方（准则 2 第 1 条），按键层 `PlayerFocus`
按页面和设置分流成三套：**桌面键盘**（`tvFocus` 关着）逐字保留原逻辑；
**直播页**保留原逻辑（键位表见下）；**视频页 + 手柄模式**走「手柄播放器模型」，
方向键完全归焦点系统。分流统一走 `isPlayerTvMode(isLive:)`
（= `!isLive && Pref.tvFocus`），别自己拼两个 Pref。

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
  直播页 / 关掉手柄模式时是 `PlayerFocus` 那个页面级节点，手柄播放器模型下换成
  `TvPlayerSurface` 的画面节点。两边都在自己的 `build` 里同步登记
  （不是 `initState`，这样运行中开关设置也能换人），父层后于子层 build 时会
  用 `!enabled` 让位，`unregisterAnchor` 有 identity 检查，不会误删别人的节点。
- **画面在直播页 / 关掉手柄模式时** `skipTraversal: true`——它就是一块大矩形，
  参与遍历会把所有卡片的焦点抢走。`skipTraversal` **不影响 `autofocus`**
  （`_pendingAutofocuses`/`applyIfValid` 只看祖先链），所以进页面焦点仍在画面上。
  手柄播放器模型下更彻底：`PlayerFocus` 关掉自己的 `canRequestFocus` 与 `autofocus`，
  焦点从画面那一层开始。
- **上下栏各有自己的区域标签 + 进栏锁**（`TvEntryLock`）：焦点**从栏外进到栏里**
  时落点锁死——上栏锁 `player-back`（返回键）、下栏锁 `player-play-pause`
  （播放/暂停按钮）；**栏内**走动不锁，仍是几何寻焦（从播放/暂停能走到隔壁按钮）。
  锚点没登记（直播页的返回键）时什么也不做，直播页因此一个字都没变。
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

同理，**焦点还在控制条里时不自动隐藏**——`hideTaskControls` 每 2 秒问一次
`tvFocusInControls`，为真就重新计时。用一个裸 `bool`（而不是 `Rx`）是因为
它只被计时器这一个消费者读，改它不需要触发重建。

### 键位表（桌面键盘 / 直播页）

**视频页 + 手柄模式不适用下面的表**，它走「手柄播放器模型」那一节。

焦点在**画面**上：

| 键 | 行为 |
| --- | --- |
| ←/→ | 快退 / 快进（保持原语义），同时**先把控制条亮起来** |
| ↑/↓ | 音量（保持原语义），同样先亮控制条 |
| 确定（`select` / `gameButtonA`） | 控制条亮着 → 焦点进底栏第一个控件；没亮 → 播放暂停 + 亮控制条 |
| B / Esc | 控制条亮着 → 只收控制条，焦点回画面；没亮 → 正常返回（退页面） |
| enter / space | **不动**：仍是"跳过片头+发弹幕" / 播放暂停（桌面键盘语义） |
| L2 / R2 | 快退 / 快进（媒体键同） |
| L1 / R1 | 走全局层（上一栏/下一栏），播放器里没做特殊处理 |

焦点在**控制条**里：

| 键 | 行为 |
| --- | --- |
| ←/→ | 控件间导航；停在进度条上时按 `TvSeekBar` 的规则微调（见下） |
| ↑/↓ | 顶栏 ↔ 底栏（`stop` 边界，不会跑出 OSD） |
| 确定 | 激活焦点控件（`ActivateIntent`，交还框架） |
| B / Esc | 收控制条 + 焦点回画面 |

实现上这件事只在 `onKeyEvent` 开头做一次判断：`TvRegions.hasFocus(playerOsd)`
为真就**放行**方向键/确定键/Tab，其余走桌面键位表。放行（`ignored`）而不是
`handled` 很关键——`handled` 会让按键停在这一层，控件的"确定"就永远不会被激活。

### 手柄播放器模型：整块画面 = 一个焦点（`TvPlayerSurface`）

只在**视频页 + 「手柄/遥控器模式」**下成立（`isPlayerTvMode`），直播页不变。
它解决的是上面那张表里最反直觉的两条：手柄 / 遥控器用户想要的不是"↑/↓ 调音量"，
而是"方向键在界面里移动预选框"；而**框架区分不出遥控器方向键和键盘方向键**
（都是 `arrowUp`），所以这一模式下视频页的键盘方向键也一起交出去了。

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
| 退出全屏 | — | 焦点交回画面（非全屏下它是唯一落点） |
| 任何时候 | 空格 / 字母键 | 播放暂停、发弹幕、全屏(`F`/`X`)、静音……照旧 |
| 控制条亮着 | B / Esc | 只收控制条，焦点回画面（和桌面键盘一致） |

全屏下画面**不再是"整块一个大焦点"**：焦点能进上下栏了，它退化成"上下栏收起来
时焦点停的地方"，所以**不画预选框**（`FocusRing(hideRing: true)`）——上下栏收着
是它唯一会停留的状态，那种状态下画一圈大框只会让人以为"还能往别处走"。

几点实现说明：

- **确定键只在画面自己持有焦点时才接**（`node.hasPrimaryFocus`）。OSD 是画面的
  子节点，焦点落在里面某个按钮上时这一层会作为祖先收到同一颗确定键，
  不判断的话就会"按确定激活不了按钮，反而变成播放暂停"。
- **`enter` 在画面上就是确定键**（需求里的"回车 = 确定"），所以这一模型下视频页
  键盘的"回车 = 跳过片头"让位；发弹幕仍有顶栏按钮和 `D` 之类的键。
  这是 `Pref.tvFocus` 打开时的既定取舍，要老键位就把「手柄/遥控器模式」关掉。
- **进全屏后不去抓控制条里的按钮**：切全屏之后布局要重排（视频页那边还有
  150ms 防抖），这时抓按钮会抓到一个马上被拆掉的节点上，焦点反而丢了。
  焦点留在画面上，按下方向键就进播放/暂停。
- **方向键唤栏只认"第一次按下"**（`TvKeys.isFirstPress`）：长按的重复事件只吞掉，
  不然每帧都要重新送一遍焦点。
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

直播复用同一套，差别只在底栏第一个可聚焦控件是**播放/暂停按钮**（没有进度条），
所以"确定键进控制条"落在那儿，而方向键在画面上就只有音量（快进的判断里有
`isLive` 短路）。"键盘控制"这个开关已经去掉了（键盘一直是常开的），
所以装 `PlayerFocus` 不需要条件，直接装上：

```dart
child = PlayerFocus(plPlayerController: ..., child: child);
```

它内部按 `isPlayerTvMode(isLive:)` 自己分流。
**手柄播放器模型在直播页永远是关的**（`isLive` 为真）：直播没有进度条、
快进被 `isLive` 短路，把方向键交出去只会得到一个"既不能导航、又不能调速"的
播放器。所以直播页的键位表、进栏锁落点（返回键那个锚点根本不会登记）
都和改动前一样。

直播间底栏（发送弹幕那一整条）在**竖屏/侧栏布局**下也是一个 `TvCard`：

| 键 | 行为 |
| --- | --- |
| 确定 | 打开发送弹幕面板（和触摸点在整条栏上一样） |
| 长按确定 / Y | 点赞一次（触摸那边是按住点赞按钮连点，手柄只给一次） |

栏里的「弹幕开关 / 点赞 / 表情」三个按钮在触摸上照旧可点，但手柄模式下
统一 `TvCardSubAction`（一个 cell 一个焦点）。弹幕开关在播放器控件里也有一个，
手柄走那边（见上表 `D` 键）。

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
- 开关「长按确定打开更多」关掉后，长按 = 短按（确定键完全交还框架）。

## 弹层（对话框 / 底弹层）

框架行为先记清楚，省得自己发明一套：

- `showDialog` / `showModalBottomSheet` 弹出来的是一条 **`ModalRoute`**。
  push 的时候框架会把焦点交给**这条路由自己的 `FocusScope`**——面板里一个
  控件都没选中，按确定什么都不会发生，用户得先瞎按一下方向键才"活"过来。
  （这一条现在由 `TvRouteFocusObserver` 统一兜了，见「进页面的初始落点」：
  路由弹层的入口就是"面板里第一个可聚焦项"，和 `TvFocusOnOpen` 的落点一致。）
- 那条 scope 的遍历范围只包含面板内部，所以**方向键不会跑到底下的卡片上**。
- pop 的时候框架自动把焦点还回**打开面板的那个控件**，不需要自己记。

所以弹层只有一件事要做：**打开后把焦点送到面板里的第一项**。

```dart
showModalBottomSheet<void>(
  context: context,
  builder: (_) => TvFocusOnOpen(child: 面板内容),
)
```

`TvFocusOnOpen` 等第一帧（懒加载的列表项得先建出来）再取
`FocusScope.of(context)` 的 `traversalDescendants.first` —— 用
`FocusScope.of` 而不是 `Focus.of`：后者不允许拿到 scope 本身
（会抛 "No Focus widget ancestor could be found"）。

它和路由级的入口机制（`TvRouteFocusObserver`）算出来的是同一个落点，重复套不
冲突：面板第一项在**顶栏**里时 observer 会让位（顶栏控件不算入口），
`TvFocusOnOpen` 照旧能把它接住；`SmartDialog` 那类不走路由的弹层则只能靠它。

⚠️ 别在面板里再套一层"打开就抢焦点"的逻辑（例如给首项写 `autofocus`）：
如果有两个面板叠在一起，抢焦点的那层会把**上层**的选项抢走，用户看到的是
"菜单弹出来了但手柄完全选不了"。同理，播放器里所有"把焦点抢回来"的动作
都要先问一句 `TvRegions.isCurrentRoute(context)`。

仓库里用得最多的几个弹层已经包好了（改代码时别把它们拆掉）：
`showConfirmDialog`、`showPgcFollowDialog`、举报（`report.dart` /
`report_member.dart`）、评论与动态卡片长按弹出的操作面板。

### `SmartDialog.show`：插 overlay 的弹层要自己立 scope

`SmartDialog` 不是路由，它只是往 overlay 里插一层控件，**和页面共用一个
`FocusScope`**，于是上面那两条规则都不成立：

- 焦点还停在打开它的卡片上，方向键就在底下的页面里转，弹层像张画；
- `TvFocusOnOpen` 送的"当前 scope 第一项"会送到**底下那页**的第一张卡片上。

所以这类弹层要套 `TvOverlayScope`：先立一个自己的 `FocusScope`
（`autofocus` 会把焦点落到里面第一项），再让 `TvFocusOnOpen` 兜底。

```dart
SmartDialog.show(
  builder: (context) => TvOverlayScope(child: 面板内容),
)
```

判断用哪个：**`showDialog` / `showModalBottomSheet` → `TvFocusOnOpen`；
`SmartDialog.show` → `TvOverlayScope`**。已接：更新提示、权限提示
（它们本来也是"弹出来按确定没反应"）。

### 弹菜单（`showMenu`）

卡片上的 ⋮ / 更多按钮弹出 `showMenu` 时有两个坑（封面那颗 ⋮ 现在也一并
去掉了，菜单入口只剩长按 / 右键 / Y 键，锚点因此只能靠卡片自己算）：

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

`TvBack.push(handler)` 是给"返回键要先关控件、再退页面"的场景准备的
（播放器控件层、全屏、图片预览……）。handler 返回 `false` 表示不接手。

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
| `SmartDialog.show` 的弹层 | `TvOverlayScope`（它没有自己的 scope，必须立一个） |
| 滑块（音量/倍速/字号…） | `TvSlider`（不套的话方向键会被滑块吃掉，出不来） |
| 给普通按钮/列表项/标签页加焦点环 | `FocusRing`（`builder` 拿 `focusNode` 交给内部控件） |
| 顶部标签栏（预选框 + 焦点即切换 + 进栏锁 + L1/R1） | `TvTabBar`（`regionLabel` 要唯一；"标签=滚到区块"的页面传 `onFocusTab`） |
| 平板抽屉里的导航项 | `TabletNavItem`（圆角矩形环 + 指示条；头像/消息/搜索那三颗圆按钮用 `FocusRing(circle: true)`） |
| 页面/面板的焦点边界 | `TvRegion`（标签要唯一） |
| 把焦点送进某个区域（切栏、跳转） | `TvRegions.focusFirst(label, index: n)` |
| 焦点寄存与恢复 | `TvFocusMemory.park()` / `restore()` / `focusIndex(i)` |
| 输入框（按确定才输入、返回键脱出） | `TvTextField`（宿主自己持焦点时传 `editFocusNode` + `navFocusNode`） |
| 上一栏 / 下一栏 | 实现 `TvSectionSwitcher`，按键已由 `TvShortcuts` 全局接好 |
| 返回键先关自己的控件 | `TvBack.push` |
| 让播放器里"只能点"的控件能被手柄停住 | `TvButton`（`onTap` 为空则不占焦点） |
| 可聚焦的进度条（左右微调、抬起才 seek） | `TvSeekBar` + 实现 `TvSeekBarHost` |
| 让焦点落在进度**指示器**上（手柄播放器模型） | `TvSeekBar(focusOnThumb: true)` + `ProgressBar(thumbFocusRing:)` |
| 播放器画面当成一个大焦点（预选框+确定键进全屏） | `TvPlayerSurface`（只在手柄播放器模型下装，见 `isPlayerTvMode`） |
| 焦点"进到某块区域"时把落点锁到指定控件 | `TvEntryLock`（播放器上下栏就是这么锁返回键 / 播放暂停的） |
| 播放器 OSD（自动隐藏与焦点联动） | `PlayerTvOsd`，按键层是 `PlayerFocus` |
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
   的弹层套 `TvOverlayScope`（见「弹层」）。
8. 跑 `flutter test test/tv_focus_test.dart`，`flutter analyze` 零新增告警。
9. 动播放器（`PlayerFocus` / `PlayerTvOsd` / `TvSeekBar` / `TvPlayerSurface`）时记得
   **视频页和直播页共用**这套代码，改键位表要两边都想一遍（直播没有进度条、
   `isLive` 会把快进短路掉，手柄播放器模型在直播上恒为关）；控制条上的新控件
   一律用 `TvButton` 包；新按钮要能"进栏即落点"就把 `TvRegions.registerAnchor`
   登记上，别在按键层里写方向判断。

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

## 已确认的取舍

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
  所以视频页的键盘 ↑/↓ 也一起变成焦点导航——设置项的说明文字里写明了。
  想要音量就走 `M` 静音/音量面板，或者把「手柄/遥控器模式」整个关掉。
- **非全屏按确定 = 进全屏，不照搬 blbl 的"确定 = 播放/暂停"**：这是需求明确
  指定的（"在视频上点击 A、确定、回车等视为全屏播放视频"）。代价是非全屏时
  方向键够不到 OSD 上的控件（那一层在非全屏压根不进焦点树），要操作控件得先进全屏；
  对照的 BBLL 也是这个分工。全屏之后确定才是播放/暂停（这时它就是 BBLL 的手感）。
- **全屏收栏时"方向键唤栏"而不是"方向键自己进栏"**：BBLL 是"上下栏一露出来焦点
  就落在播放/暂停上"，我们把它拆成两步——先亮栏（焦点送到播放/暂停按钮，
  按钮被按顺序走过，不判方向），再让用户从那里按方向键走进栏里。
  好处是方向键的语义只有一条（唤栏），不用在画面这一层判"↑ 进下栏还是上栏"；
  代价是亮栏那一帧焦点其实已经不在画面上了，所以画面在那一帧同步 `hideRing`。
- **`PlayerFocus` 的 B 键在最前面判**：B 在任何情况下的意思都是"先收掉播放器自己
  的东西"（控制条亮着收控制条、焦点在画面里就退页面），这条在两个模型下完全一致，
  所以它写在 `_tvPlayerMode` 分支之前，手柄播放器模型不会把它一起让出去。
- **上下栏的落点用进栏锁，不在按键层判方向**：从画面按 ↑ 进底栏，几何上会落到
  "正上方那根进度条"，而手柄用户要的是播放/暂停按钮。进栏锁（`TvEntryLock`）
  只认"焦点从栏外进到栏里"，栏内移动照旧几何寻焦——这样以后往栏里加控件、
  挪布局都不用改按键逻辑。锚点没登记时它什么也不做，所以没适配的页面
  （直播页的返回键）行为不变。
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
  不值得为它改滚动结构。
- **不移植 blbl 的"内容网格左右边沿切栏"**（`switchToNextTabFromContentEdge`）：
  Flutter 的几何 traversal 表达不了"网格左边沿"这个条件，而 L1/R1 加上"焦点在
  标签栏上按 ←/→"已经覆盖了同一个需求。
- **`dynamics_topic` 的排序 `ToggleButtons`（排序选择器，不是 tab）和 `main` 页的
  底部导航不在本次范围**：后者是底部 tab，不属于"顶部标签栏"。
