import 'dart:collection' show HashMap;

import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
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
/// 落点如果**不该**是第一项（合集弹窗要落在"正在播放"的那一台上），用
/// [TvFocusOnOpen.target] 指定即可，不必另写一套"抢焦点"。
/// `Pref.tvFocus` 关掉时什么都不做，弹层行为完全退回改动前。
class TvFocusOnOpen extends StatefulWidget {
  const TvFocusOnOpen({super.key, required this.child, this.target});

  final Widget child;

  /// 打开时该落到哪一项；不传 = scope 里的第一项（老行为）。
  ///
  /// 有些弹层里"第一项"不是该选中的那一项：合集弹窗要落在**正在播放**的那一台
  /// 上，而它在列表中间。给了 [target] 之后 [TvFocusOnOpen] 就只等它——等待
  /// 期间不碰"第一项"，所以不会出现"先落到第一项、下一帧又被抢走"的闪烁；
  /// 它还没建出来（数据还在加载）就一直等，等超了才退回"第一项"
  /// （上限见 [_TvFocusOnOpenState._maxTargetFrames]）。
  ///
  /// [target] 是按 **scope** 记的（见 [TvOpenFocusTargets]）：同一个弹层上可能
  /// 套着两层 [TvFocusOnOpen]（`TvPanelScope` / `PublishRoute` 自带一层，面板
  /// 自己也套一层），两层读同一份申请才不会互相打架。
  final FocusNode? target;

  @override
  State<TvFocusOnOpen> createState() => _TvFocusOnOpenState();
}

/// "打开时该落到哪一项"的申请处（见 [TvFocusOnOpen.target]）。
///
/// 按 **scope** 记而不是按 widget 记：同一个 scope 上套两层 [TvFocusOnOpen] 是
/// 常态（`TvPanelScope` 立 scope 时自带一层，面板内容自己还会再兜一层），
/// 只挂在其中一层上的话，另一层会照老规矩先落到"第一项"。
///
/// 申请方（拿到 [TvFocusOnOpen.target] 的那一层）在销毁时撤销，所以面板关掉
/// 就不会留下过期的落点。
abstract final class TvOpenFocusTargets {
  static final Map<FocusScopeNode, FocusNode> _targets =
      HashMap<FocusScopeNode, FocusNode>.identity();

  static void set(FocusScopeNode scope, FocusNode node) =>
      _targets[scope] = node;

  /// 撤销 [node] 的申请。申请已经被别的东西换掉了就不动（同一个 scope 上
  /// 先后住过两个面板时，撤销晚一步的不该把新申请抹掉）。
  static void clear(FocusScopeNode scope, FocusNode node) {
    if (identical(_targets[scope], node)) _targets.remove(scope);
  }

  /// [scope] 上现在申请了哪一项；没人申请返回 null。
  static FocusNode? of(FocusScopeNode? scope) =>
      scope == null ? null : _targets[scope];
}

class _TvFocusOnOpenState extends State<TvFocusOnOpen> {
  /// 最多试多少帧（≈660ms）。
  ///
  /// 弹层里常见的是网络列表（选集、收藏夹、评论），第一帧完全是空的；
  /// 只试一帧的话预选框要等到用户按下第一个方向键才出现。
  static const int _maxFrames = 40;

  /// 有指定落点（[TvFocusOnOpen.target]）时最多等多少帧（≈2s）。
  ///
  /// 比 [_maxFrames] 宽得多：那一项常常是"数据到了才建出来"的。等待期间不碰
  /// "第一项"，所以是静默的；但也不能一直等下去——等超了就退回"第一项"，
  /// 否则焦点会一直浮在 scope 上，方向键落在 scope 自己身上，
  /// 用户看到的是"弹层打开了，可按键没反应"。
  static const int _maxTargetFrames = 120;

  FocusScopeNode? _scope;
  int _tried = 0;
  int _targetTried = 0;
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
    final scope = FocusScope.of(context);
    if (identical(scope, _scope)) return;
    // 换了 scope：把上一条申请摘掉（见 [TvOpenFocusTargets]）
    _releaseTarget();
    _scope = scope;
    // 指定了落点：按 scope 登记，和同一层 scope 上那几层 [TvFocusOnOpen] 共用
    if (widget.target case final target?) {
      TvOpenFocusTargets.set(scope, target);
    }
  }

  /// 撤销这一层登记的落点申请（有的话）。
  void _releaseTarget() {
    final target = widget.target;
    final scope = _scope;
    if (target != null && scope != null) {
      TvOpenFocusTargets.clear(scope, target);
    }
  }

  @override
  void dispose() {
    _releaseTarget();
    super.dispose();
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
    final scope = _scope;
    if (scope == null) return;
    // 有人申请了落点（[TvFocusOnOpen.target]）：只等它，不去碰"第一项"。
    // 等超了（[_maxTargetFrames]）才往下走，退回老规矩。
    final target = TvOpenFocusTargets.of(scope);
    if (target != null && _targetTried <= _maxTargetFrames) {
      _targetTried++;
      if (_mayAct(scope) && TvRegions.canLandOn(target)) {
        target.requestFocus();
        return;
      }
      _schedule();
      return;
    }
    if (++_tried > _maxFrames) return;
    if (!_mayAct(scope)) return;
    final nodes = scope.traversalDescendants;
    if (nodes.isEmpty) {
      _schedule();
      return;
    }
    nodes.first.requestFocus();
  }

  /// 现在轮到这一层动手吗——焦点要么浮在 scope 上（还没人接住），要么还在
  /// 外面没过界（第一帧的常态）。返回 false 表示收手。
  bool _mayAct(FocusScopeNode scope) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return true;
    if (identical(focus, scope) || _isInside(focus, scope)) {
      _owned = true;
      // 焦点在 scope **里**却不是 scope 自己：有控件接住了
      return identical(focus, scope);
    }
    // 焦点又跑出去了：后开的弹层接手了
    return !_owned;
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
