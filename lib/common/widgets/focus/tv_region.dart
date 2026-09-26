import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
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
///
/// 除了登记，它还替每块区域记着"上次焦点待在这块区域里的哪个控件"——切栏、切页
/// 之后回来时，落点是那个控件，而不是"树序第一项"那条粗糙规则（见 [focusEntry]）。
abstract final class TvRegions {
  static final Map<String, _RegionEntry> _scopes = {};
  static final Map<String, FocusNode> _anchors = {};

  /// [_anchors] 里那些"落脚点"（`registerAnchor(..., lastResort: true)`）。
  /// 挑页面入口时跳过它们，见 [entryNodeFor]。
  static final Set<String> _lastResortAnchors = {};

  /// 每块区域"上次待着的地方"。
  ///
  /// 键是**区域节点**不是标签：标签会重（`video-intro-panel` 就有三处），
  /// 用节点当键才分得清哪一块是哪一块。
  static final Map<FocusScopeNode, _Landing> _landings = {};

  /// 焦点记录器挂在哪个 `FocusManager` 上（换个实例要重挂）。
  static FocusManager? _watcher;

  static void register(
    String label,
    FocusScopeNode node, {
    TvRegionKind kind = TvRegionKind.content,
  }) {
    _scopes[label] = _RegionEntry(node, kind);
    _watch();
  }

  static void unregister(String label, FocusScopeNode node) {
    if (identical(_scopes[label]?.node, node)) _scopes.remove(label);
    _landings.remove(node);
  }

  /// 保证"焦点一动就记落点"那个监听器挂着。
  ///
  /// 跟着第一个区域挂上、之后一直不摘：区域会跟着页面反复建了又拆，按"现在还有
  /// 没有区域"来决定挂摘容易漏（监听器是静态的，漏一次就再也不记了）。
  static void _watch() {
    final manager = FocusManager.instance;
    if (identical(_watcher, manager)) return;
    _watcher?.removeListener(_rememberLanding);
    _watcher = manager;
    manager.addListener(_rememberLanding);
  }

  /// 焦点变了：如果它停在某块登记过的区域里，记下是哪个控件、第几项。
  ///
  /// 只记不改（这里一个指头都不碰焦点），所以挂在 `FocusManager` 上不会和谁打架；
  /// 手柄模式之外也没人读这份记忆（[focusEntry] 的调用方都先问 `Pref.tvFocus`）。
  static void _rememberLanding() {
    final focus = FocusManager.instance.primaryFocus;
    // 焦点浮在 scope（路由 / 区域自己 / 弹层）上时不属于任何控件
    if (focus == null || focus is FocusScopeNode) return;
    final scope = focus.nearestScope;
    if (scope == null) return;
    // 只记"直接待在这块区域里"的控件：区域里再嵌一层（面板、更里层的小区域）时，
    // 那层的落点是它自己的事，别顶掉外面这层的
    var mine = false;
    for (final entry in _scopes.values) {
      if (identical(entry.node, scope)) {
        mine = true;
        break;
      }
    }
    if (!mine) return;
    final nodes = scope.traversalDescendants.toList();
    final index = nodes.indexOf(focus);
    if (index < 0) return;
    _landings[scope] = _Landing(focus, index);
  }

  /// 登记一个"锚点"节点：不是区域，但需要在别处把焦点**送回去**。
  ///
  /// 播放器画面、播放/暂停按钮、返回按钮都用它（见 [TvLabels]）。
  /// 调用方可能在 build 里反复调用，所以同一个节点重复登记直接跳过。
  ///
  /// [lastResort] 给"**落脚点**"用（整页那一层、画面被移出树时接管的那一层）：
  /// 它接得住焦点、也确实该接（画面没了总不能把焦点丢了），但它不是控件——
  /// [entryNodeFor] 挑页面入口时会**跳过**它，留给画面/标签栏/真控件；
  /// 确实没有别的入口时才用它。挑成落脚点的话，进页面那一下焦点停在整页大小
  /// 的节点上，用户看到的就是"窗口大小的预选框"，方向键也会卡住
  /// （框架的几何寻焦以它为基准挑候选，页内一个都够不着）。
  static void registerAnchor(
    String label,
    FocusNode node, {
    bool lastResort = false,
  }) {
    if (lastResort) {
      _lastResortAnchors.add(label);
    } else {
      _lastResortAnchors.remove(label);
    }
    if (identical(_anchors[label], node)) return;
    _anchors[label] = node;
  }

  static void unregisterAnchor(String label, FocusNode node) {
    if (identical(_anchors[label], node)) {
      _anchors.remove(label);
      _lastResortAnchors.remove(label);
    }
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
  /// **明确按序号落项**的口子：标签栏"切到第 N 栏就把焦点放到第 N 个标签上"、
  /// 列表里删了一张卡按位置补位。日常的"切栏 / 切页之后进新区域"别用它，用
  /// [focusEntry]——那个记着上次待着的地方，而且保证落点看得见。
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

  /// 把焦点送进这个区域，落在"上次待着的地方"。
  ///
  /// 这是**进区域**的正路（切栏、切页交接、看护循环唤醒都走它），里面按三级
  /// 往下退：
  ///
  /// 1. 上次待着的那个控件，还看得见的话（见 [canLandOn]）；
  /// 2. 它没了（列表刷新过、卡片换过 Key）→ 同一块区域里的**同一序号**，
  ///    位置大差不差；
  /// 3. 都没有 → 区域里第一个看得见的项。
  ///
  /// 一条硬约束贯穿三级：**落点得是预选框画得出来的地方**。列表滚过之后树序
  /// 第一项在视口**上面**（缓存范围里的卡还在焦点树上），"取第一项"那条粗糙
  /// 规则选中它，预选框就画到屏幕外面去了——用户看到的就是"焦点丢了"。
  ///
  /// 返回 false 表示这块区域现在给不出落点：不存在、属于被盖住的路由、自己还在
  /// 屏幕外（页面正切栏滑动、切走的栏还挂在树上），或者里面一项都画不出来。
  /// 调用方（按帧重试的交接、看护循环）该等下一帧再来，而不是硬塞一个看不见的
  /// 落点进去。
  static bool focusEntry(String label) {
    final node = _scopes[label]?.node;
    if (node == null) return false;
    return focusEntryInScope(node);
  }

  /// [focusEntry] 的 scope 版：焦点浮在**区域自己**身上（区域里的项被销毁）时，
  /// 看护循环手里只有这个 scope，没有标签。
  static bool focusEntryInScope(FocusScopeNode node) {
    if (!isCurrentRoute(node.context)) return false;
    final target = _landingOf(node);
    if (target == null) return false;
    target.requestFocus();
    return true;
  }

  /// 这块区域现在的落点，见 [focusEntry]；给不出返回 null。
  static FocusNode? _landingOf(FocusScopeNode scope) {
    // 区域自己还在屏幕外（切走的栏、被滚出屏幕的板块）：往里送等于把预选框画到
    // 看不见的地方，返回 null 让调用方等下一帧
    if (!_onScreen(scope)) return null;
    final landing = _landings[scope];
    if (landing != null) {
      if (canLandOn(landing.node)) return landing.node;
      // 记的那个没了：同一序号顶上（列表重建、卡片换过 Key）
      final nodes = scope.traversalDescendants.toList();
      if (nodes.isNotEmpty) {
        final node = nodes[landing.index.clamp(0, nodes.length - 1)];
        if (!identical(node, landing.node) && canLandOn(node)) return node;
      }
    }
    return _firstLandingOf(scope);
  }

  /// 区域里第一个"画得出预选框"的项；一项都没有返回 null。
  ///
  /// 先用"在不在区域的可见窗口里"（[_visibleIn]）筛一道：滚上去的卡在这一步就
  /// 出局，省下逐项去求可见矩形的开销；再用 [canLandOn] 确认它真的画得出来
  /// （区域被别的层盖住、页面正滑动时，光"在窗口里"还不够）。
  static FocusNode? _firstLandingOf(FocusScopeNode scope) {
    final area = scope.rect;
    for (final node in scope.traversalDescendants) {
      final rect = node.rect;
      if (!rect.width.isFinite || !rect.height.isFinite) continue;
      if (!_visibleIn(node, area)) continue;
      if (canLandOn(node)) return node;
    }
    return null;
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

  /// 兜底的方向键寻焦：框架那套挑不出候选时，退到这里按方向挑**最近的真控件**。
  ///
  /// 框架的 `inDirection` 有一条硬规则：候选必须**完全落在起点的边之外**。
  /// 起点自己"跨满了一整维"时（整块视频画面、整页宽的横幅、整页大小的落脚点），
  /// 四周剩下的控件全都和它重叠，于是方向键按下去什么也不发生——用户手上的
  /// 感觉就是"焦点卡死了"。
  ///
  /// 这一层把规矩放宽成"往那个方向有进展就算"：打分 = 主轴距离 + 2 × 垂直偏移，
  /// 取最小。候选来自起点所在 scope 的 [FocusScopeNode.traversalDescendants]
  /// （`skipTraversal` 的、`ExcludeFocus` 里的自动出局），再过一遍 [canLandOn]
  /// （画得出来、属于最上面那一层路由），并排掉整页大小的落脚点
  /// （[TvFocusSpec.coversWholeView]）——送过去等于把焦点藏起来。
  ///
  /// 返回 false = 这个方向上确实没地方可去，调用方把按键还给框架。
  static bool focusInDirection(TraversalDirection direction, {FocusNode? from}) {
    final node = from ?? FocusManager.instance.primaryFocus;
    if (node == null) return false;
    final scope = node.nearestScope;
    if (scope == null) return false;
    final origin = _rectOf(node);
    if (origin == null) return false;
    final viewSize = _viewSizeOf(node);

    // 主轴上的最小进展：滤掉"中心几乎对齐"的邻居，又不至于挡掉正常的相邻项
    const epsilon = 0.5;
    final center = origin.center;
    FocusNode? best;
    var bestScore = double.infinity;
    for (final candidate in scope.traversalDescendants) {
      if (candidate is FocusScopeNode || identical(candidate, node)) continue;
      if (!canLandOn(candidate)) continue;
      final rect = visibleRect(candidate) ?? candidate.rect;
      if (viewSize != null && TvFocusSpec.coversWholeView(rect, viewSize)) {
        continue;
      }
      final delta = rect.center - center;
      final (double primary, double cross) = switch (direction) {
        TraversalDirection.up => (-delta.dy, delta.dx.abs()),
        TraversalDirection.down => (delta.dy, delta.dx.abs()),
        TraversalDirection.left => (-delta.dx, delta.dy.abs()),
        TraversalDirection.right => (delta.dx, delta.dy.abs()),
      };
      if (primary <= epsilon) continue;
      final score = primary + 2 * cross;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best == null) return false;
    best.requestFocus();
    return true;
  }

  /// 节点的可见矩形（全局坐标）；问不出来返回 null。
  static Rect? _rectOf(FocusNode node) {
    if (node.context == null) return null;
    final rect = visibleRect(node) ?? node.rect;
    return rect.width.isFinite && rect.height.isFinite ? rect : null;
  }

  /// 这个节点所在视图的逻辑尺寸；拿不到返回 null。
  static Size? _viewSizeOf(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return null;
    final view = View.maybeOf(context);
    return view == null ? null : view.physicalSize / view.devicePixelRatio;
  }

  /// 这个节点现在会不会被画出来。
  ///
  /// 先看它还挂不挂在焦点树上；再看尺寸是不是有限值（没布局过的连一帧都没画过，
  /// [visibleRect] 也因此给不出矩形）；最后排掉 `Offstage`（`TabBarView` 切走的那些栏、
  /// `Visibility` 保留状态的那种）——它们还挂在树上、矩形也是旧的，点它们等于
  /// 把焦点送进看不见的地方。
  ///
  /// 给"按坐标找落点"（[focusAt]）、"能不能当落点"（[canLandOn]）和"归还焦点"
  /// （`TvFocusReturn`）用。只接普通节点，scope 节点不算。
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

  /// 这个节点现在能不能当落点：还挂得住、属于最上面那一层路由，而且**预选框
  /// 画得出来**。
  ///
  /// "画得出来"和兜底焦点环（`TvFocusOverlay`）用的是同一套判断（[visibleRect]）：
  /// 控件自己的矩形，跟祖先里所有会裁剪的盒子求交，交空了就是看不见——列表滚上去
  /// 的卡（被视口裁掉）、切走的栏、页面正切栏滑动时还没进场的那一半，全在这里
  /// 落选。再加上"它所在的那一块自己也得在屏幕上"：区域被滚出屏幕时，里面的项
  /// 虽然没被裁掉，送过去同样是画在看不见的地方。
  ///
  /// [within] 是"把它放在哪一块里看"，默认取它的最近 scope（区域里的卡就是那块
  /// 区域）。`TvFocusReturn` 归还焦点时用它核对记下来的那个控件。
  static bool canLandOn(FocusNode node, {FocusNode? within}) {
    if (!node.canRequestFocus) return false;
    if (!isPainted(node)) return false;
    if (!isCurrentRoute(node.context)) return false;
    if (visibleRect(node) == null) return false;
    final area = within ?? node.nearestScope;
    return area == null || _onScreen(area);
  }

  /// 这个控件的**可见**矩形（全局坐标）；一点都看不见返回 null。
  ///
  /// 控件自己的矩形，和祖先里所有会裁剪的盒子自己的矩形求交。
  /// `describeApproximatePaintClip` 是框架给"这个祖辈会不会裁掉子节点"的官方
  /// 口子（`RenderViewportBase` / `RenderClip*` / `RenderSingleChildViewport` /
  /// `RenderStack` / `RenderFlex` 都实现了），它给的裁剪框在**它自己**的坐标系里
  /// （见 SDK `RenderObject.describeApproximatePaintClip` 的说明），所以拿它自己的
  /// 变换送到全局再交。不交这一下的话，列表滚过之后（焦点还停在那张卡上、卡已经
  /// 出了视口）预选框会画在 AppBar 或者相邻区域上。
  ///
  /// 框架原话是"approximate"：`ClipOval` 这类给回来的还是整块 `Offset.zero & size`，
  /// 所以这一层只保证不画到**确定**看不见的地方去，不保证裁得一丝不差。
  ///
  /// 兜底焦点环用它决定"画不画"（画不出来就不画），[canLandOn] 用它决定"能不能
  /// 落"——同一个定义，不会出现"焦点落在环画不出来的地方"。
  static Rect? visibleRect(FocusNode node) {
    final object = node.context?.findRenderObject();
    if (object is! RenderBox || !object.attached) return null;
    var rect = node.rect;
    // 还没布局过 / 已经被收走（`KeepAlive` 里的旧栏、正在销毁的节点）的矩形是
    // NaN，拿它去求交会得到"非空"的假象
    if (!rect.width.isFinite || !rect.height.isFinite) return null;
    RenderObject? child = object;
    for (
      RenderObject? parent = object.parent;
      parent != null;
      parent = parent.parent
    ) {
      final clip = parent.describeApproximatePaintClip(child!);
      if (clip != null) {
        rect = rect.intersect(_globalRect(parent, clip));
        if (rect.isEmpty) return null;
      }
      child = parent;
    }
    return rect;
  }

  /// 这个控件现在能不能看到一点，见 [visibleRect]。
  static bool isVisible(FocusNode node) => visibleRect(node) != null;

  /// 这个节点（区域 / 路由 scope 那一层）自己还在屏幕上吗。
  ///
  /// 和 [visibleRect] 的区别是"问不出来就不拦"：渲染对象还没挂上、或者压根没布局
  /// 过时，宁可当作"在"——拦错了会把落点整个憋掉，而"东西还没建出来"本身有
  /// [canLandOn] 那几道检查兜着。
  static bool _onScreen(FocusNode node) {
    final object = node.context?.findRenderObject();
    if (object is! RenderBox || !object.attached) return true;
    return visibleRect(node) != null;
  }

  static Rect _globalRect(RenderObject object, Rect rect) =>
      MatrixUtils.transformRect(object.getTransformTo(null), rect);

  /// 进入 [route] 时预选框该落在哪儿；给不出像样的落点时返回 null。
  ///
  /// 换页时框架只把焦点交给路由自己的 scope，页面里一个控件都没选中，
  /// 于是第一下方向键会落到"树序第一项"上——通常是 AppBar 的返回键。
  /// 这里按下面的顺序挑一个真正的入口（[TvRouteFocusObserver] 用它）：
  ///
  /// 1. 这一页登记的**锚点**——真控件优先（播放器的播放/暂停按钮、画面那一层），
  ///    标了 `lastResort` 的"整页那一层"（见 [registerAnchor]）排到最后；
  /// 2. 第一个**内容区**（[TvRegionKind.content]）的落点（[_landingOf]：上次待着
  ///    的那一项，没记过就是里头的第一项），空着就往下找；
  /// 3. 标签栏区域（[TvRegionKind.tabBar]）的落点——页面还在加载时的退路；
  /// 4. 这一页里**不在顶栏**的第一个可聚焦项（没套区域的页面靠这条）。
  ///
  /// 两条筛选：顶栏（[AppBar] / [SliverAppBar]）里的控件一律不算入口——AppBar
  /// 在树序上排在内容前面，不排除掉的话任何带返回键 / 搜索键的页面都会把预选框
  /// 停在顶栏上；**画不出预选框的**也不算（见 [canLandOn]），否则列表滚过之后
  /// 预选框会画在屏幕外面，看着还是"焦点丢了"。想指定别的入口（例如顶栏里的搜索框）
  /// 就给内容 `autofocus`，或者把目标套进一个 [TvRegion]。
  ///
  /// `lastResort` 锚点为什么排最后：它常常就是**视口大小**的节点（播放器画面那一层、
  /// 整页的兜底层）。焦点停在那种节点上时，框架的 `inDirection` 要求候选节点
  /// 完全落在它的边之外——页内一个都挑不出来，方向键就"死"了。宁可退到第 2~4 步
  /// 里的真控件上。
  static FocusNode? entryNodeFor(Route<dynamic>? route) {
    // 1. 锚点：真控件一轮，`lastResort` 存着备用
    FocusNode? lastResort;
    for (final entry in _anchors.entries) {
      final node = entry.value;
      if (!node.canRequestFocus || !_isInRoute(node, route)) continue;
      if (_lastResortAnchors.contains(entry.key)) {
        lastResort ??= node;
        continue;
      }
      return node;
    }
    // 2. 内容区 / 3. 标签栏
    FocusScopeNode? tabBar;
    for (final entry in _scopes.values) {
      if (!_isInRoute(entry.node, route)) continue;
      if (entry.kind == TvRegionKind.tabBar) {
        tabBar ??= entry.node;
        continue;
      }
      final landing = _landingOf(entry.node);
      if (landing != null) return landing;
    }
    final tabBarLanding = tabBar == null ? null : _landingOf(tabBar);
    // 4. 没套区域的页面：这一页里第一个不在顶栏里的可聚焦项；再挑不出就退回
    //    `lastResort` 锚点——整页节点当入口不理想，总好过"没有入口"。
    if (tabBarLanding != null) return tabBarLanding;
    final scope = _currentRouteScope(route);
    if (scope == null) return lastResort;
    return _firstNotInTopBar(scope.traversalDescendants, scope.rect) ?? lastResort;
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

/// 落点记忆里的一条：上次焦点停在区域里的哪个控件 + 它在区域里的序号。
///
/// 序号跟着一起记是因为控件随时可能被销毁（列表刷新、卡片换 Key）——那时至少
/// 还有"上次是第几项"这个位置信息，能从同一序号上接回来。
class _Landing {
  const _Landing(this.node, this.index);

  final FocusNode node;
  final int index;
}
