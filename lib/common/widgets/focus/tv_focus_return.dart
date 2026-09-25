import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 焦点归还：从 A 进 B、再从 B 退回 A 时，把焦点还给"当初从哪儿进的"。
///
/// 框架自己会做一半：B 那一层的 scope 被拆掉时，A 的 `_focusedChildren` 里还留着
/// "上一次聚焦的那个节点"，框架会把它重新点亮。但只有**那个节点还在树上**的时候
/// 才成立——列表刷新过、Key 变了、卡片被删了，框架就只能把焦点交给 A 的
/// **路由 scope**：预选框没了，方向键也动不了，得先瞎按一下才回来。
///
/// 所以这里在 push 的那一刻把"上一页焦点在哪儿"记下来（节点 + 所在区域 +
/// 在区域里的序号），退回时按三级往下退：
///
/// 1. 那个控件还在 → 直接还给它（"从哪儿进的退到哪儿"）；
/// 2. 控件没了（列表重建过）→ 回到**同一块区域里的同一个序号**，位置大差不差；
/// 3. 连区域都没了 → 交给 [TvRegions.entryNodeFor] 那套页面入口规则。
///
/// 只在"焦点浮着"的时候调用（见 [TvRouteFocusObserver]）：页面里有控件拿着焦点
/// 时不许抢，那是页面自己的选择（`autofocus`、`TvFocusMemory` 都可能在干活）。
abstract final class TvFocusReturn {
  /// 最多记几条。导航栈深不了，这只是防止反复 push/pop 之后越攒越多。
  static const int _maxEntries = 8;

  static final Map<Route<dynamic>, _Entry> _entries = {};

  /// 记下 [route] 上现在的焦点，供它被盖住之后再露出来时归还。
  ///
  /// 在 `didPush` 里调用：那时候 `primaryFocus` 通常**还是**上一页那张卡片
  /// （框架把焦点交给新路由的 scope 是下个微任务的事）。
  /// 抓不到像样的目标（没焦点、焦点浮在 scope 上、焦点不在这一层）就不记，
  /// 归还时自然落到第 3 级。
  static void remember(Route<dynamic>? route) {
    if (route == null || !Pref.tvFocus) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus is FocusScopeNode) return;
    final context = focus.context;
    if (context == null || !context.mounted) return;
    // 焦点不在这一层上（比如停在更上面那个弹层里）：记了也没用
    if (!identical(ModalRoute.of(context), route)) return;
    final scope = focus.nearestScope;
    final nodes = scope?.traversalDescendants.toList();
    final index = nodes == null ? -1 : nodes.indexOf(focus);
    if (_entries.length >= _maxEntries) _entries.remove(_entries.keys.first);
    _entries[route] = _Entry(focus, scope, index < 0 ? null : index);
  }

  static void forget(Route<dynamic>? route) {
    if (route != null) _entries.remove(route);
  }

  /// 把焦点还给 [route] 上"上次离开时待着的地方"。
  ///
  /// 按上面那三级往下退；没记过东西（或者记的都没了）就落在页面入口上。
  /// 返回 false = 这一层现在一个能接焦点的地方都没有（列表还在加载），
  /// 看护循环接着等。
  static bool restore(Route<dynamic>? route) {
    if (route == null || !Pref.tvFocus) return false;
    // 被别的层盖住时不许动手：会把盖在上面那层的焦点抢走
    if (!route.isCurrent) return false;
    final entry = _entries[route];
    if (entry != null) {
      // 1. 离开时待着的那个控件还在——最准的一档
      if (_usable(entry.node)) {
        entry.node.requestFocus();
        return true;
      }

      // 2. 控件没了：回到同一块区域里的同一个序号（列表刷新过、卡片换过 Key）
      final scope = entry.scope;
      if (scope != null && scope.context != null && scope.context!.mounted) {
        final nodes = scope.traversalDescendants.toList();
        if (nodes.isNotEmpty) {
          nodes[(entry.index ?? 0).clamp(0, nodes.length - 1)].requestFocus();
          return true;
        }
      }
    }

    // 3. 没记过、或者记的东西都没了：页面入口那套规则
    //    （锚点 → 内容区首项 → 标签栏 → 不在顶栏的第一项）
    final node = TvRegions.entryNodeFor(route);
    if (node == null) return false;
    node.requestFocus();
    return true;
  }

  /// 这个节点现在能不能接住焦点。
  ///
  /// `context` 在节点销毁之后**不会**被清空（见 [TvRegions.focusAnchor]），
  /// 所以"还活着"要看它挂着的 element 在不在；`Offstage`（切走的栏、折叠起来的
  /// 区块）里的节点还挂着，但焦点送进去就等于送进看不见的地方。
  static bool _usable(FocusNode node) =>
      node.canRequestFocus &&
      TvRegions.isPainted(node) &&
      TvRegions.isCurrentRoute(node.context);
}

/// 登记表里的一条：离开时焦点待着的控件 + 它所在的区域 + 在区域里的序号。
class _Entry {
  const _Entry(this.node, this.scope, this.index);

  final FocusNode node;
  final FocusScopeNode? scope;
  final int? index;
}
