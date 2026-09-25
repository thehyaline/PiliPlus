import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 已登记的弹层 scope（[TvPanelScope] / [TvOverlayScope] 立起来的那些）。
///
/// `TvRouteFocusObserver` 用它区分"焦点浮在**弹层**的 scope 上"和"焦点浮在
/// **页面**的 scope 上"：前者归弹层自己（[TvFocusOnOpen]），看护循环不许插手
/// ——不然会把焦点从刚打开的弹层里拽回底下的卡片。
abstract final class TvOverlayScopes {
  static final Set<FocusScopeNode> _scopes = {};

  static void add(FocusScopeNode node) => _scopes.add(node);

  static void remove(FocusScopeNode node) => _scopes.remove(node);

  static bool contains(FocusScopeNode node) =>
      _scopes.any((e) => identical(e, node));
}

/// 弹层内容：打开之后把焦点送到里面**第一项**。
///
/// `showModalBottomSheet` / `showDialog` 都是独立路由，框架把焦点挪到
/// **弹层自己的 scope** 上就算完事（`ModalRoute` 只做 `focusScopeNode` 的交接），
/// 里面一项都没选中。表现是"菜单弹出来了，按确定没反应"——得先瞎按一下方向键
/// 才知道自己停在哪儿。
///
/// 顺带说一句框架已经做好的部分：弹层 scope 之外的东西（底下的卡片）不在这个
/// scope 的 `traversalDescendants` 里，所以面板打开期间方向键不会跑到底下去；
/// 面板关掉时框架也会把焦点还给打开它的那个控件。
///
/// 用法就是套在弹层内容外面：
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => TvFocusOnOpen(child: Column(children: [...])),
/// );
/// ```
///
/// 送的是第一项而不是"上次选中的那一项"：弹层的内容各不相同，记位置没有意义。
/// 面板里第一项如果是个不能聚焦的东西（分割线、装饰），会被自动跳过——
/// `traversalDescendants` 本身就是"能停的节点"的序列。
/// `Pref.tvFocus` 关掉时什么都不做，弹层行为完全退回改动前。
class TvFocusOnOpen extends StatefulWidget {
  const TvFocusOnOpen({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusOnOpen> createState() => _TvFocusOnOpenState();
}

class _TvFocusOnOpenState extends State<TvFocusOnOpen> {
  /// 最多试多少帧（≈660ms）。
  ///
  /// 弹层里常见的是网络列表（选集、收藏夹、评论），第一帧完全是空的；
  /// 只试一帧的话预选框要等到用户按下第一个方向键才出现。
  static const int _maxFrames = 40;

  FocusScopeNode? _scope;
  int _tried = 0;
  bool _scheduled = false;
  bool _waitedFirstFrame = false;

  /// 焦点是不是**轮到过**这个弹层。
  ///
  /// 第一帧焦点通常还在"打开弹层的那个控件"上（框架把焦点交给弹层 scope 是
  /// 下个微任务的事，而微任务在整帧跑完之后才轮到），所以要容忍"焦点还在外面"。
  /// 但只要焦点**进过一次**这一层，再跑出去就说明是后开的弹层接手了——
  /// 那时候必须收手，不然会把用户正要用的那一层拽回来。
  bool _owned = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 弹层里的第一个 Focus 祖先是路由自己的 scope
    // （用 `FocusScope.of`：`Focus.of` 不允许拿到 scope 本身）
    _scope = FocusScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    if (!Pref.tvFocus) return;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      // 第一帧只看不动：`autofocus`（面板里的输入框）和框架把焦点交给这一层
      // scope 的那一下都是帧末微任务里应用的，而微任务要等整帧跑完才轮到；
      // 抢在它们前面动手会把它们顶掉。下一帧再动手，那时候焦点看得见了。
      if (!_waitedFirstFrame) {
        _waitedFirstFrame = true;
        _schedule();
        return;
      }
      _try();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// 一帧试一次：里面的控件接住焦点就收手，还没建出来（网络列表）等下一帧。
  void _try() {
    if (++_tried > _maxFrames) return;
    final scope = _scope;
    if (scope == null) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null) {
      if (identical(focus, scope) || _isInside(focus, scope)) {
        _owned = true;
        if (!identical(focus, scope)) return; // 有控件接住了
      } else if (_owned) {
        return; // 焦点又跑出去了：后开的弹层接手了
      }
    }
    final nodes = scope.traversalDescendants;
    if (nodes.isEmpty) {
      _schedule();
      return;
    }
    nodes.first.requestFocus();
  }

  bool _isInside(FocusNode node, FocusScopeNode scope) {
    FocusNode? current = node;
    while (current != null) {
      if (identical(current, scope)) return true;
      current = current.parent;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 同上，但给**不走路由**的弹层用（`SmartDialog.show`、`MiniScaffold` 的面板
/// 这类）。
///
/// 路由弹层（`showDialog` / `showModalBottomSheet`）有自己的 `FocusScope`，
/// 里面的焦点怎么走都不影响底下那页。而 `SmartDialog` 和
/// `MiniScaffold.showBottomSheet` 只是往 overlay / 同一个路由里插一层控件，
/// 和页面**共用同一个 scope**，于是有两件事不对：
///
/// 1. 焦点还停在打开它的那张卡片上，方向键就在底下那页里转，弹层像张画；
/// 2. `TvFocusOnOpen` 送焦点的目标是"当前 scope 的第一项"——这里会送到
///    底下那页的第一张卡片上去，等于没送。
///
/// 所以这里先立一个自己的 [FocusScope]（`autofocus` 会直接把焦点落到
/// 里面第一项上），把弹层和页面隔开，再把"第一项"这件事交给 [TvFocusOnOpen]
/// 兜底（比如弹层里第一帧还没建出可聚焦项的情况）。同时把这个 scope 登记进
/// [TvOverlayScopes]，让 `TvRouteFocusObserver` 的看护循环知道"这儿有主了"。
/// `Pref.tvFocus` 关掉时什么都不做。
class TvPanelScope extends StatelessWidget {
  const TvPanelScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return child;
    return FocusScope(
      autofocus: true,
      child: _OverlayScopeRegistrar(child: TvFocusOnOpen(child: child)),
    );
  }
}

/// [TvOverlayScope] = [TvPanelScope]（留着这个别名，叫法更贴近调用点）。
class TvOverlayScope extends StatelessWidget {
  const TvOverlayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TvPanelScope(child: child);
}

/// 把自己所在的这个 scope 登记进 [TvOverlayScopes]，走的时候摘掉。
class _OverlayScopeRegistrar extends StatefulWidget {
  const _OverlayScopeRegistrar({required this.child});

  final Widget child;

  @override
  State<_OverlayScopeRegistrar> createState() => _OverlayScopeRegistrarState();
}

class _OverlayScopeRegistrarState extends State<_OverlayScopeRegistrar> {
  FocusScopeNode? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 最近的这个 scope 就是 [TvPanelScope] 立起来的那个
    final scope = FocusScope.of(context);
    if (identical(scope, _scope)) return;
    if (_scope != null) TvOverlayScopes.remove(_scope!);
    _scope = scope;
    TvOverlayScopes.add(scope);
  }

  @override
  void dispose() {
    if (_scope != null) TvOverlayScopes.remove(_scope!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
