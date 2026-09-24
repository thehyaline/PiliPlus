import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

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
    this.edgeBehavior = TraversalEdgeBehavior.parentScope,
  });

  final Widget child;
  final String debugLabel;

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
    TvRegions.register(widget.debugLabel, _node);
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
  static final Map<String, FocusScopeNode> _scopes = {};
  static final Map<String, FocusNode> _anchors = {};

  static void register(String label, FocusScopeNode node) =>
      _scopes[label] = node;

  static void unregister(String label, FocusScopeNode node) {
    if (identical(_scopes[label], node)) _scopes.remove(label);
  }

  /// 登记一个"锚点"节点：不是区域，但需要在别处把焦点**送回去**。
  ///
  /// 目前只有播放器画面用它（控制条收起来时焦点回到画面上，
  /// 见 `TvLabels.playerSurface`）。
  static void registerAnchor(String label, FocusNode node) =>
      _anchors[label] = node;

  static void unregisterAnchor(String label, FocusNode node) {
    if (identical(_anchors[label], node)) _anchors.remove(label);
  }

  /// 把焦点送回登记过的锚点；返回 false 表示没登记过（或已经销毁、
  /// 或者它属于被盖住的路由）。
  static bool focusAnchor(String label) {
    final node = _anchors[label];
    if (node == null || !node.canRequestFocus) return false;
    if (!isCurrentRoute(node.context)) return false;
    node.requestFocus();
    return true;
  }

  /// 这块区域（或锚点）现在是否持有焦点——含里面的控件。
  ///
  /// 给"焦点在不在这一块里"这类分支用，例如播放器：
  /// 焦点落在控制条里时方向键要让给控件间导航。
  static bool hasFocus(String label) =>
      (_scopes[label] ?? _anchors[label])?.hasFocus ?? false;

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
    final node = _scopes[label];
    if (node == null || !isCurrentRoute(node.context)) return false;
    // descendants 是按树序展开的，所以序号就是视觉顺序
    final nodes = node.traversalDescendants;
    if (index >= nodes.length) return false;
    nodes.elementAt(index).requestFocus();
    return true;
  }
}
