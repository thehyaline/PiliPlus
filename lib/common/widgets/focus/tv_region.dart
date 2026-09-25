import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 区域的种类。[TvRegions.entryNodeFor] 挑入口时要区分。
///
/// 一页里通常排着一条标签栏和一块内容区，两者都是 [TvRegion]，但"进页面时
/// 预选框落在哪儿"**不该**是标签栏——那等于把预选框停在顶栏上，用户还得再按
/// 一次才进得了内容。所以标签栏会把自己标出来（[TvTabBar] 就是这么干的），
/// 内容区用默认值即可。
enum TvRegionKind {
  /// 内容区：进页面时的首选落点。
  content,

  /// 标签栏：内容区还没建出来时的退路。
  tabBar,
}

/// 页面里的一块独立导航区域（网格、列表、侧栏……）。
///
/// 只做一件事：给方向键一个**边界**。
///
/// 方向键走的是"几何寻焦"——在最近的 FocusScope 里找那个方向上的下一个控件。
/// 走到这块区域的边（例如最后一排再按 ↓）时，要不要继续往外走由
/// [FocusScopeNode.directionalTraversalEdgeBehavior] 决定，
/// 而框架默认值是 [TraversalEdgeBehavior.stop]：**什么都不发生**。
/// 手柄上这就像"卡住了"，只能再按 B 退出去。
///
/// 这里默认改成 [TraversalEdgeBehavior.parentScope]：
/// 区域内没得走了就去上一层区域找，也就是"网格最后一排按 ↓ 会去底栏"，
/// "顶栏按 ↑ 从网格上面绕回来"这类自然的跨区域移动。
///
/// 另外它也是 [TvFocusMemory] 定位"焦点现在在哪一块"的锚点，
/// 所以网格/列表外面套一层就好，别套太碎。
class TvRegion extends StatefulWidget {
  const TvRegion({
    super.key,
    required this.child,
    this.debugLabel = 'TvRegion',
    this.kind = TvRegionKind.content,
    this.edgeBehavior = TraversalEdgeBehavior.parentScope,
  });

  final Widget child;
  final String debugLabel;

  /// 这块区域算内容还是标签栏，见 [TvRegionKind]。
  final TvRegionKind kind;

  /// 走到边界之后怎么办，见类的说明。
  final TraversalEdgeBehavior edgeBehavior;

  @override
  State<TvRegion> createState() => _TvRegionState();
}

class _TvRegionState extends State<TvRegion> {
  late final FocusScopeNode _node = FocusScopeNode(
    debugLabel: widget.debugLabel,
    traversalEdgeBehavior: widget.edgeBehavior,
    directionalTraversalEdgeBehavior: widget.edgeBehavior,
  );

  @override
  void initState() {
    super.initState();
    TvRegions.register(widget.debugLabel, _node, kind: widget.kind);
  }

  @override
  void dispose() {
    TvRegions.unregister(widget.debugLabel, _node);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return widget.child;
    return FocusScope(
      node: _node,
      // 区域本身不该成为遍历目标：`FocusScopeNode` 也是外层 scope 的
      // `traversalDescendants` 里的一员，跨区域找焦点时会和区域里的卡片抢
      // （几何上区域矩形正好覆盖"下一张卡"的位置）。标了 skipTraversal
      // 就只比卡片，区域内的遍历不受影响。
      skipTraversal: true,
      child: widget.child,
    );
  }
}

/// 区域注册表：给"切栏之后把焦点送进新栏"这类跨区域动作一个查找入口。
///
/// [TvRegion] 挂载时按 [TvRegion.debugLabel] 登记自己，所以**标签要唯一**
/// （同一个标签同时存在两个活得区域时，后登记的会把先登记的顶掉）。
abstract final class TvRegions {
  static final Map<String, _RegionEntry> _scopes = {};
  static final Map<String, FocusNode> _anchors = {};

  static void register(
    String label,
    FocusScopeNode node, {
    TvRegionKind kind = TvRegionKind.content,
  }) => _scopes[label] = _RegionEntry(node, kind);

  static void unregister(String label, FocusScopeNode node) {
    if (identical(_scopes[label]?.node, node)) _scopes.remove(label);
  }

  /// 登记一个"锚点"节点：不是区域，但需要在别处把焦点**送回去**。
  ///
  /// 播放器画面、播放/暂停按钮、返回按钮都用它（见 [TvLabels]）。
  /// 调用方可能在 build 里反复调用，所以同一个节点重复登记直接跳过。
  static void registerAnchor(String label, FocusNode node) {
    if (identical(_anchors[label], node)) return;
    _anchors[label] = node;
  }

  static void unregisterAnchor(String label, FocusNode node) {
    if (identical(_anchors[label], node)) _anchors.remove(label);
  }

  /// 登记过的锚点节点；没登记过返回 null。
  ///
  /// 给"是不是已经停在落点上了"这类比较用（[TvEntryLock]），
  /// 想**送焦点过去**用 [focusAnchor]——那里有一堆有效性检查。
  static FocusNode? anchor(String label) => _anchors[label];

  /// 把焦点送回登记过的锚点；返回 false 表示没登记过（或已经销毁、
  /// 或者它属于被盖住的路由）。
  ///
  /// [checkRoute] 只在**拆树**的时候关掉：那个检查要问 `ModalRoute.of`，
  /// 而 `dispose()` 里查祖先会被框架拦下来（"Looking up a deactivated
  /// widget's ancestor is unsafe"）。拆树时"这一页还在不在最上层"本来也无从
  /// 判断——锚点自己那几句有效性检查（还挂得住、还活着）就够了。
  static bool focusAnchor(String label, {bool checkRoute = true}) {
    final node = _anchors[label];
    if (node == null || !node.canRequestFocus) return false;
    // `FocusNode.context` 只在 attach 时写过一次，节点销毁之后**不会**被清空，
    // 所以不能只看它是不是 null：锚点登记过、这一帧刚被销毁的情况得看
    // 它挂着的 element 还在不在（deactivate 起 `mounted` 就是 false）。
    final context = node.context;
    if (context == null || !context.mounted) return false;
    if (checkRoute && !isCurrentRoute(context)) return false;
    node.requestFocus();
    return true;
  }

  /// 这块区域（或锚点）现在是否持有焦点——含里面的控件。
  ///
  /// 给"焦点在不在这一块里"这类分支用，例如播放器：
  /// 焦点落在控制条里时方向键要让给控件间导航。
  static bool hasFocus(String label) =>
      (_scopes[label]?.node ?? _anchors[label])?.hasFocus ?? false;

  /// 这个上下文所在的路由现在是不是最上面那一层。
  ///
  /// 所有"把焦点抢回来 / 送进去"的动作都得先问这一句：从播放器控制条上打开
  /// 画质、弹幕设置这些面板时，播放器所在的路由已经被盖住了，这时抢焦点会把
  /// 面板的选项抢走，用户看到的是"菜单弹出来了但手柄完全选不了"。
  /// 拿不到路由（还没挂到树上、或测试里的脚手架没有路由）时按"就在最上层"处理。
  static bool isCurrentRoute(BuildContext? context) {
    if (context == null) return true;
    return ModalRoute.of(context)?.isCurrent ?? true;
  }

  /// 把焦点送进这个区域里的第 [index] 个可聚焦项（默认首项，一般是列表第一张卡）。
  ///
  /// 返回 false 表示区域不存在、里面没有可聚焦项（懒加载还没构建出来），
  /// 或者它属于**被盖住的路由**——那种情况下不该抢焦点。
  static bool focusFirst(String label, {int index = 0}) {
    final node = _scopes[label]?.node;
    if (node == null || !isCurrentRoute(node.context)) return false;
    // descendants 是按树序展开的，所以序号就是视觉顺序
    final nodes = node.traversalDescendants;
    if (index >= nodes.length) return false;
    nodes.elementAt(index).requestFocus();
    return true;
  }

  /// 这个节点是不是某个已登记区域的 scope。
  ///
  /// 看护循环用它分类"焦点现在浮在哪儿"（浮在区域上 / 路由自己在的 scope 上 /
  /// 面板上），三者的处理完全不同。
  static bool isRegion(FocusNode node) {
    for (final entry in _scopes.values) {
      if (identical(entry.node, node)) return true;
    }
    return false;
  }

  /// 把焦点送进**这个**区域里的第一个可见项（刚才聚焦的项被销毁、焦点浮到区域
  /// 自己身上时用）。区域空着返回 false。
  static bool focusFirstInScope(FocusScopeNode node) {
    if (!isCurrentRoute(node.context)) return false;
    final first = _firstVisibleOf(node);
    if (first == null) return false;
    first.requestFocus();
    return true;
  }

  /// 把焦点送到"屏幕上这个点底下的那个控件"（鼠标/触摸板点击用）。
  ///
  /// 不做真正的 hit-test，按几何来：遍历整棵焦点树，取**面积最小**的那个包含
  /// 这一点的节点。最小面积 = 最内层，所以卡片里的子按钮、滑块、开关都会被
  /// 正确命中；`ExcludeFocus` 包起来的卡内子动作（点赞、更多…）因为
  /// `canRequestFocus == false` 自动落选，和"一个卡片一个焦点"的约定一致。
  ///
  /// 不要求 `!skipTraversal`：播放器画面、输入框这些"不参与方向键遍历"的叶子
  /// 也得能接住点击——点一下视频再按方向键，起点就是画面。
  ///
  /// 返回是否真的移动了焦点（点在空白处就不动，免得把焦点从别处抢走）。
  static bool focusAt(Offset position) {
    FocusNode? best;
    var bestArea = double.infinity;
    for (final node in FocusManager.instance.rootScope.descendants) {
      if (node is FocusScopeNode || !node.canRequestFocus) continue;
      // 被盖住的路由、offstage 的旧页、保持存活但已经收走的项都不算
      if (!isCurrentRoute(node.context) || !isPainted(node)) continue;
      final rect = node.rect;
      if (!rect.contains(position)) continue;
      final area = rect.width * rect.height;
      if (area < bestArea) {
        bestArea = area;
        best = node;
      }
    }
    best?.requestFocus();
    return best != null;
  }

  /// 这个节点现在会不会被画出来。
  ///
  /// 先看它还挂不挂在焦点树上；再看尺寸是不是有限值（没布局过的连一帧都没画过，
  /// 见 [_firstVisible]）；最后排掉 `Offstage`（`TabBarView` 切走的那些栏、
  /// `Visibility` 保留状态的那种）——它们还挂在树上、矩形也是旧的，点它们等于
  /// 把焦点送进看不见的地方。
  ///
  /// 给"按坐标找落点"（[focusAt]）和"归还焦点"（`TvFocusReturn`）用。
  /// 只接普通节点，scope 节点不算。
  static bool isPainted(FocusNode node) {
    // 还在焦点树上吗——`context` **当不了依据**：框架只在 `attach` 时写它、
    // `detach` 时不清，而那个 element 常常已经被列表复用给同位置的**另一个**
    // 节点了（没给 Key 的 `Column` / `ListView` 是按位置匹配的），于是
    // "有 context、矩形有限、还在屏幕里"全是假象；真把焦点送过去，它打在
    // 一个不接线的节点上什么也不会发生，`TvFocusReturn` 还会当成"归还成功"
    // 而收手（预选框就永远浮着了）。挂在树上的非 scope 节点必有一个 scope 祖先，
    // 摘下来的没有（框架 `detach` 里会把 `_parent` 置空）。
    if (node.nearestScope == null) return false;
    final context = node.context;
    if (context == null || !context.mounted) return false;
    final rect = node.rect;
    if (!rect.width.isFinite || !rect.height.isFinite) return false;
    if (rect.width <= 0 || rect.height <= 0) return false;
    var painted = true;
    context.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) {
        painted = false;
        return false;
      }
      return true;
    });
    return painted;
  }

  /// 进入 [route] 时预选框该落在哪儿；给不出像样的落点时返回 null。
  ///
  /// 换页时框架只把焦点交给路由自己的 scope，页面里一个控件都没选中，
  /// 于是第一下方向键会落到"树序第一项"上——通常是 AppBar 的返回键。
  /// 这里按下面的顺序挑一个真正的入口（[TvRouteFocusObserver] 用它）：
  ///
  /// 1. 这一页登记的**锚点**（播放器页面：画面那一层）；
  /// 2. 第一个**内容区**（[TvRegionKind.content]）的首项，空着就往下找；
  /// 3. 标签栏区域（[TvRegionKind.tabBar]）的首项——页面还在加载时的退路；
  /// 4. 这一页里**不在顶栏**的第一个可聚焦项（没套区域的页面靠这条）。
  ///
  /// 两条筛选：顶栏（[AppBar] / [SliverAppBar]）里的控件一律不算入口——AppBar
  /// 在树序上排在内容前面，不排除掉的话任何带返回键 / 搜索键的页面都会把预选框
  /// 停在顶栏上；**看不见的**也不算（见 [_firstVisible]），否则列表滚过之后预选框
  /// 会画在屏幕外面，看着还是"焦点丢了"。想指定别的入口（例如顶栏里的搜索框）
  /// 就给内容 `autofocus`，或者把目标套进一个 [TvRegion]。
  static FocusNode? entryNodeFor(Route<dynamic>? route) {
    // 1. 锚点
    for (final node in _anchors.values) {
      if (node.canRequestFocus && _isInRoute(node, route)) return node;
    }
    // 2. 内容区 / 3. 标签栏
    FocusScopeNode? tabBar;
    for (final entry in _scopes.values) {
      if (!_isInRoute(entry.node, route)) continue;
      if (entry.kind == TvRegionKind.tabBar) {
        tabBar ??= entry.node;
        continue;
      }
      final first = _firstVisibleOf(entry.node);
      if (first != null) return first;
    }
    final tabBarFirst = tabBar == null ? null : _firstVisibleOf(tabBar);
    if (tabBarFirst != null) return tabBarFirst;
    // 4. 没套区域的页面：这一页里第一个不在顶栏里的可聚焦项
    final scope = _currentRouteScope(route);
    if (scope == null) return null;
    return _firstNotInTopBar(scope.traversalDescendants, scope.rect);
  }

  /// 焦点悬在**页面自己那一层**（路由的 scope，不是任何控件）时，把预选框
  /// 唤到入口上。返回 true 表示已经送进去了。
  ///
  /// 给按键层用（`TvShortcuts`）：页面刚进来、或者列表刷新完焦点掉回页面这一层
  /// 时，第一次按方向键/确定键由这里接管，比框架"从整屏 scope 开始寻焦、
  /// 最后兜底沉到树序第一项（顶栏返回键）"靠谱。返回 false 表示没有像样的
  /// 入口（页面还在加载），调用方放行按键，框架的默认行为照旧。
  static bool focusRouteEntry() {
    final context = _currentRouteScope(null)?.context;
    if (context == null) return false;
    final route = ModalRoute.of(context);
    if (route == null) return false;
    final target = entryNodeFor(route);
    if (target == null) return false;
    target.requestFocus();
    return true;
  }

  /// [node] 是不是挂在 [route] 这一层上；[route] 为 null 时不做路由过滤。
  static bool _isInRoute(FocusNode node, Route<dynamic>? route) {
    if (route == null) return true;
    // 节点销毁后 `context` 不会被清空（见 [focusAnchor]），看 element 还在不在
    final context = node.context;
    if (context == null || !context.mounted) return false;
    return identical(ModalRoute.of(context), route);
  }

  /// 焦点现在"悬在 [route] 自己那一层的 scope 上"吗？是的话把这个 scope 返回。
  ///
  /// 换页之后就是这样：`FocusScopeNode.setFirstFocus` 只把焦点交给路由的
  /// scope，里面一个控件都没选中，`FocusManager.primaryFocus` 正好就是它——
  /// 于是不用去翻 `_ModalScope` 私有的 `focusScopeNode`。
  ///
  /// [TvRegion] 自己的 scope 不算：它里面有没有项是另一回事（区域里有项的话，
  /// 上面的 1~3 步已经找到了；没有的话也不该拿区域当页面入口）。
  /// 根 scope 也不算：它的 `context` 是 null，问不出属于哪个路由。
  static FocusScopeNode? _currentRouteScope(Route<dynamic>? route) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus is! FocusScopeNode) return null;
    for (final entry in _scopes.values) {
      if (identical(entry.node, focus)) return null;
    }
    final context = focus.context;
    if (context == null || !context.mounted) return null;
    if (route != null && !identical(ModalRoute.of(context), route)) return null;
    return focus;
  }

  /// 区域里第一个**看得见**的可聚焦项；区域是空的（懒加载还没建出来）返回 null。
  static FocusNode? _firstVisibleOf(FocusScopeNode node) =>
      _firstVisible(node.traversalDescendants, node.rect);

  /// 序列里第一个"落在 [area] 里"的节点；一个都看不见时退而取第一个。
  ///
  /// 不挑看得见的会踩两类坑：列表滚过之后树序第一项在视口**上面**（预选框画在
  /// 屏幕外，看着还是"焦点丢了"）；被 `Offstage` / `KeepAlive` 留住的旧页
  /// （`TabBarView` 里切走的那些）区域还登记着，但项都已经不在屏幕上。
  ///
  /// 兜底只兜"画在屏幕外、但还有布局"的项：`rect` 不是有限值的连一帧都不会画
  /// 出来（`KeepAlive` 把切走的栏收走之后就是这样，连尺寸都是 NaN），选中它就是
  /// 真的把焦点弄丢了——这时宁可返回 null，让调用方接着去下一块区域找。
  static FocusNode? _firstVisible(Iterable<FocusNode> nodes, Rect area) {
    FocusNode? first;
    for (final node in nodes) {
      final rect = node.rect;
      if (!rect.width.isFinite || !rect.height.isFinite) continue;
      first ??= node;
      if (_visibleIn(node, area)) return node;
    }
    return first;
  }

  /// 序列里第一个**不在顶栏里**、且看得见的节点；实在没有就退到第一个
  /// 不在顶栏里的；全是顶栏控件时返回 null。
  static FocusNode? _firstNotInTopBar(Iterable<FocusNode> nodes, Rect screen) {
    FocusNode? notInTopBar;
    for (final node in nodes) {
      if (_inTopBar(node)) continue;
      final rect = node.rect;
      if (!rect.width.isFinite || !rect.height.isFinite) continue;
      notInTopBar ??= node;
      if (_visibleIn(node, screen)) return node;
    }
    return notInTopBar;
  }

  /// 这个节点现在画在 [area] 里吗（有大小、且和区域相交）。
  static bool _visibleIn(FocusNode node, Rect area) {
    final rect = node.rect;
    return rect.width > 0 && rect.height > 0 && rect.overlaps(area);
  }

  /// 这个节点是不是顶栏（[AppBar] / [SliverAppBar]）里的控件。
  static bool _inTopBar(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return false;
    var inTopBar = false;
    context.visitAncestorElements((element) {
      if (element.widget is AppBar || element.widget is SliverAppBar) {
        inTopBar = true;
        return false;
      }
      return true;
    });
    return inTopBar;
  }
}

/// 进区域锁：焦点**从区域外进到区域内**时，落点锁到指定的锚点上。
///
/// 方向键是几何寻焦，它只认位置：从下栏按 ↑ 进上栏，会落到"正上方那颗按钮"；
/// 从画面按 ↑ 进下栏，会落到"正中间那根进度条"。手柄用户想的是"进上栏 / 进下栏"，
/// 落点该是上栏的返回键、下栏的播放/暂停按钮。所以进区一律锁过去。
///
/// **区域内**的移动不锁：那时候本来就该按位置在控件之间走，锁住就动不了了。
/// 区分办法和 [TvTabEntryLock] 一样——看"这一批焦点变化**之前**，区域里有没有
/// 焦点"。不能直接问"现在还有没有"：`requestFocus` 是延迟到 microtask 才生效的，
/// 监听器被调到的时候这一批已经全部应用完，区域内的旧节点早就失焦了。
class TvEntryLock extends StatefulWidget {
  const TvEntryLock({
    super.key,
    required this.region,
    required this.entry,
    required this.child,
    this.enabled = true,
  });

  /// 区域标签，见 [TvRegion.debugLabel]。
  final String region;

  /// 进区域时的落点（[TvRegions.registerAnchor] 登记过的标签）。
  ///
  /// 锚点不在这一页上时什么也不做——比如直播页非全屏时的返回键（那一栏整层
  /// 不可聚焦），进栏就还是几何寻焦的落点。
  final String entry;

  /// 关掉时只是个透传的壳。
  final bool enabled;

  final Widget child;

  @override
  State<TvEntryLock> createState() => _TvEntryLockState();
}

class _TvEntryLockState extends State<TvEntryLock> {
  /// 这一批焦点变化**之前**，区域里是不是已经有焦点。
  bool _inside = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final inside = TvRegions.hasFocus(widget.region);
    final wasInside = _inside;
    _inside = inside;
    if (!inside || wasInside || !widget.enabled) return;
    // 从区域外进来：落点锁到入口。已经停在入口上就不用再 `requestFocus`
    if (identical(
      FocusManager.instance.primaryFocus,
      TvRegions.anchor(widget.entry),
    )) {
      return;
    }
    TvRegions.focusAnchor(widget.entry);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 登记表里的一条：区域节点 + 它的种类。
class _RegionEntry {
  const _RegionEntry(this.node, this.kind);

  final FocusScopeNode node;
  final TvRegionKind kind;
}
