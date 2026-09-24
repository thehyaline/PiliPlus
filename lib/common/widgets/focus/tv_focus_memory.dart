import 'package:material_ui/material_ui.dart';

/// 焦点寄存：让"列表变了之后焦点去哪儿"变成一件可预期的事。
///
/// 列表刷新、删除卡片、清空重建时，正在聚焦的那个卡片会被销毁，
/// 焦点不会自己落到旁边的卡片上，而是被框架交给**包含它的那个 scope**
/// （`FocusScopeNode._removeChild`：谁家的孩子没了，谁自己接管）——
/// 也就是 [TvRegion] 的节点；只有连这个 scope 都没了，
/// `applyFocusChangesIfNeeded` 才退到根 scope。
/// 表现就是焦点框消失、方向键要重新按好几下才回来。这是电视上最难受的一种体验。
///
/// 用法很简单：
/// ```dart
/// TvFocusMemory.park();      // 数据要变之前
/// ...                        // 刷新 / 删除
/// TvFocusMemory.restore();   // 变完之后（内部会等重建和布局）
/// ```
///
/// 位置就是"区域里第几个可聚焦项"，所以不需要给卡片编号，
/// 也不需要页面登记任何东西；区域靠 [FocusNode.nearestScope] 自己找。
abstract final class TvFocusMemory {
  /// 最多重试几帧（列表重建 + 布局可能不止一帧）
  static const int _maxAttempts = 4;

  static FocusScopeNode? _scope;
  static int _index = 0;
  static int? _prefer;
  static int _attempt = 0;

  /// 记住当前焦点在所在区域里的位置。数据变化之前调用。
  static void park() {
    _prefer = null;
    _attempt = 0;
    final focus = FocusManager.instance.primaryFocus;
    final scope = focus?.nearestScope;
    if (focus == null || scope == null) {
      _scope = null;
      return;
    }
    final index = scope.traversalDescendants.toList().indexOf(focus);
    if (index < 0) {
      _scope = null;
      return;
    }
    _scope = scope;
    _index = index;
  }

  /// 把焦点放回区域里最接近的位置。
  ///
  /// [preferIndex] 用于"删掉了第 i 项"这类页面自己知道位置的情况；
  /// 不传就用 [park] 记下的位置。
  ///
  /// 调用的时机通常是"数据已经改了"，但**卡片要到下一帧重建时才消失**，
  /// 所以这里不能只看当前这一帧：焦点还在就等下一帧再看，直到
  /// [TvFocusMemory._maxAttempts] 帧都没丢才算"用户自己换了地方"，收手。
  ///
  /// 反过来，只要焦点还在区域里、或者用户已经跑到区域外面（顶栏、底栏），
  /// 就不会去动它，免得把用户抢回去。
  static void restore({int? preferIndex}) {
    if (_scope == null) return;
    _prefer = preferIndex ?? _prefer;
    _schedule();
  }

  /// 直接聚焦区域里的第 [index] 个可聚焦项（夹在合法范围内）。
  static bool focusIndex(int index) {
    final scope = _scope;
    if (scope == null) return false;
    final nodes = scope.traversalDescendants.toList();
    if (nodes.isEmpty) return false;
    nodes[index.clamp(0, nodes.length - 1)].requestFocus();
    return true;
  }

  /// 焦点确实丢了才会动手。
  ///
  /// 焦点节点被销毁时框架的处理是 `FocusManager._markDetached` 把
  /// primaryFocus 置空，然后在 `applyFocusChangesIfNeeded` 里一路
  /// **向上找能接管的 scope**（先区域、最后根 scope），所以"丢了"的表现是：
  /// 焦点为空、焦点上浮到了区域本身、或者已经退到根 scope。
  ///
  /// 用户如果自己跑到顶栏/底栏去了（区域外的普通节点），这里什么也不做。
  static bool _lost() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return true;
    if (identical(focus, FocusManager.instance.rootScope)) return true;
    return identical(focus, _scope);
  }

  static void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback(_tryRestore);
  }

  static void _tryRestore(Duration _) {
    final scope = _scope;
    // 区域自己都被销毁了（页面退出）就不用管了
    if (scope == null || scope.context == null) {
      _reset();
      return;
    }
    if (!_lost()) {
      // 还没丢：要么数据变化引起的重建还没跑到这一帧，要么用户自己挪走了。
      // 等下一帧再看，等不到就收手。
      if (++_attempt < _maxAttempts) {
        _schedule();
      } else {
        _reset();
      }
      return;
    }
    final nodes = scope.traversalDescendants.toList();
    if (nodes.isNotEmpty) {
      final start = (_prefer ?? _index).clamp(0, nodes.length - 1);
      // 就近取：原位 → 原位之后 → 原位之前
      for (var distance = 0; distance <= nodes.length; distance++) {
        final after = start + distance;
        final before = start - distance;
        if (after < nodes.length) {
          nodes[after].requestFocus();
          _reset();
          return;
        }
        if (before >= 0) {
          nodes[before].requestFocus();
          _reset();
          return;
        }
      }
    }
    if (++_attempt < _maxAttempts) {
      _schedule();
    } else {
      _reset();
    }
  }

  static void _reset() {
    _attempt = 0;
    _prefer = null;
  }
}
