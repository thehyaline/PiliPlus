import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 路由级的"进页面就把预选框送进去"。
///
/// 挂到 `GetMaterialApp.navigatorObservers` 上（见 `main.dart`，
/// [tvRouteFocusObserver]）。
///
/// ## 为什么需要它
///
/// `ModalRoute` 换页时只做一件事：把焦点 **scope** 交接给新页面
/// （`FocusScopeNode.setFirstFocus`）。页面里没有任何控件拿到焦点，于是：
///
/// - 预选框不画（焦点在路由自己的 scope 上，不属于任何控件）；
/// - 第一次按方向键时，框架从这个"覆盖整屏的 scope 矩形"开始做几何寻焦，
///   四个方向都走不出去，只好兜底回到 scope 自身、再往下沉到**树序第一项**
///   ——通常是 AppBar 的返回键。用户看到的就是"进了页面手柄焦点就丢了，
///   一按还跑到左上角去了"。
///
/// 所以这里在换页之后主动把焦点送到 [TvRegions.entryNodeFor] 算出来的入口上。
///
/// ## 什么时候不动手
///
/// - `Pref.tvFocus` 关掉时整条路径不生效，行为完全退回改动前；
/// - 路由自己不想要焦点（`requestFocus: false`，例如"别抢焦点"的弹层）；
/// - 页面里已经有**控件**拿到焦点了——包括页面自己的 `autofocus`
///   （搜索页的搜索框、视频页的播放器画面）：那是这一页自己安排的落点，
///   比这里算出来的准；
/// - 退栈时框架把焦点还给了上一页的控件；
/// - 页面里还没有像样的入口（[TvRegions.entryNodeFor] 返回 null，
///   例如列表还在加载、这一页只有顶栏按钮）：这时候留给按键层——
///   第一次按方向键会由 `TvRegions.focusRouteEntry` 再试一次。
///
/// ## 帧序
///
/// 换页那一帧之后**跳过一帧**再动手，这一帧是留给上面那些"页面自己安排焦点"
/// 的机制的：`autofocus` 是帧末的 microtask 里才应用的（那一刻
/// `FocusManager` 的标记还停在路由 scope 上），退栈时框架的焦点恢复
/// （`setFirstFocus`）也一样。抢在它们前面动手会把它们顶掉——`Autofocus`
/// 只看"这个 scope 里有没有 focusedChild"，被顶掉之后不会再补。
/// 之后再连看几帧，等懒加载的列表项建出来。
///
/// 连看用的是 post-frame 回调链而不是 `Timer`：闲置时不会让引擎一直画帧
/// （和 `TvFocusMemory` 同一套），测试里也不会留下待决的定时器。
class TvRouteFocusObserver extends NavigatorObserver {
  /// 换页之后先空看几帧，留给页面自己的 `autofocus` / 框架的焦点恢复。
  static const int _skipFrames = 1;

  /// 再往后连看几帧（一帧 16ms，12 帧约 200ms）：懒加载的列表项是分帧建出来的。
  static const int _watchFrames = 12;

  /// 当前正在"等它把焦点的落点准备好"的路由。
  Route<dynamic>? _route;
  int _frames = 0;
  bool _scheduled = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _watch(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _watch(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _watch(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _watch(previousRoute);
  }

  /// 用户正拿手指/鼠标拖页面时别动焦点：这时候焦点该跟着手势走。
  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) => _stop();

  void _watch(Route<dynamic>? route) {
    if (!Pref.tvFocus || route == null || !route.requestFocus) {
      _stop();
      return;
    }
    _route = route;
    _frames = 0;
    _schedule();
  }

  void _stop() {
    _route = null;
    _frames = 0;
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_frames < _skipFrames) {
        _frames++;
        _schedule();
        return;
      }
      _try();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _try() {
    final route = _route;
    if (route == null) return;
    if (!route.isCurrent) {
      // 已经不再是顶上那一层了（又被盖住 / 已经退掉）
      _stop();
      return;
    }
    // 页面里的控件已经拿到焦点：那是这一页自己安排的落点，别动它
    if (!_floating(route)) {
      _stop();
      return;
    }
    final target = TvRegions.entryNodeFor(route);
    if (target != null) {
      // 先收手再送焦点，免得被自己送出去的焦点变化又触发一轮
      _stop();
      target.requestFocus();
      return;
    }
    if (++_frames > _watchFrames) {
      _stop();
      return;
    }
    _schedule();
  }

  /// 这一页现在"没有控件拿到焦点"？（焦点悬在路由自己的 scope 上，或者根本没焦点）
  static bool _floating(Route<dynamic> route) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return true;
    if (focus is! FocusScopeNode) return false;
    final context = focus.context;
    // 悬在一个已经销毁的节点上，也算没焦点
    if (context == null || !context.mounted) return true;
    // 区域（[TvRegion]）自己的 scope 也算"还没落到控件上"
    return identical(ModalRoute.of(context), route);
  }
}

/// 全局实例：挂进 `GetMaterialApp.navigatorObservers`。
final NavigatorObserver tvRouteFocusObserver = TvRouteFocusObserver();
