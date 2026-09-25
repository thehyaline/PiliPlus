import 'package:PiliPlus/common/widgets/focus/tv_focus_on_open.dart';
import 'package:PiliPlus/common/widgets/focus/tv_focus_return.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 换页看护：新的一页 / 弹层出来之后，把预选框送进它里面。
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
/// ## 这是一条看护循环，不是"换页时送一次"
///
/// - 换页（push / pop / replace / remove）之后开始看护目标那一层；
/// - 每帧看一眼焦点：落到控件上就收手；浮着（没焦点、或焦点停在某个 scope 上）
///   就想办法送进去——**退栈**优先还给"当初从这儿进去的那个控件"
///   （[TvFocusReturn]），**进新页**按 [TvRegions.entryNodeFor] 挑一个入口；
/// - 看护窗口 [_watchFrames] 帧（≈1.5 秒）。窗口内被别的层盖住（pop 动画还没
///   收尾、上面又开了个弹层）只是"不动手"，不是"放弃"——早先的版本在这里收手
///   收早了（判一句 `!route.isCurrent` 就停），于是退回 A 之后预选框再也回不来；
/// - 另外还盯着 `FocusManager`：页面自己把焦点弄丢（列表刷新干掉了焦点所在的
///   那张卡、切栏重建、锚点被拆掉）也会被同一套逻辑接住，不用等用户按键。
///
/// ## 什么时候不动手
///
/// - `Pref.tvFocus` 关掉时整条路径不生效，行为完全退回改动前；
/// - 路由自己不想要焦点（`requestFocus: false`，例如"别抢焦点"的弹层）；
/// - 这一层里已经有**控件**拿到焦点了——包括页面自己的 `autofocus`
///   （搜索页的搜索框、视频页的播放器画面）：那是这一页自己安排的落点，
///   比这里算出来的准；
/// - 焦点浮在**弹层**的 scope 上（`TvFocusOnOpen` 在管，见 [TvOverlayScopes]）；
/// - 页面里还没有像样的入口（[TvRegions.entryNodeFor] 返回 null，
///   例如列表还在加载、这一页只有顶栏按钮）：看护继续等；
///   第一次按方向键还会由 `TvRegions.focusRouteEntry` 再试一次。
///
/// ## 帧序
///
/// 换页那一帧之后**跳过一帧**再动手：`autofocus` 和框架的焦点交接都是帧末的
/// 微任务里才应用的，而微任务要等整帧（含这里的 post-frame 回调）跑完才轮到。
/// 抢在它们前面动手会把它们顶掉——`Autofocus` 只看"这个 scope 里有没有
/// focusedChild"，被顶掉之后不会再补。
///
/// 连看用的是 post-frame 回调链而不是 `Timer`：闲置时不会让引擎一直画帧
/// （和 `TvFocusMemory` 同一套），测试里也不会留下待决的定时器。
class TvRouteFocusObserver extends NavigatorObserver {
  TvRouteFocusObserver() {
    // 焦点每次变化都看一眼：页面把焦点弄丢时这里能第一时间接管
    FocusManager.instance.addListener(_onFocusChange);
  }

  /// 看护起点：第一帧只看不动，见类说明的「帧序」。
  static const int _skipFrames = 1;

  /// 看护窗口：90 帧 ≈ 1.5 秒。
  ///
  /// 旧版是 12 帧（≈200ms）：网络列表第一帧根本还是空的，看护一收手预选框就
  /// 一直浮着，直到用户按下第一个方向键。
  static const int _watchFrames = 90;

  /// 焦点浮在**区域**上时多等几帧，让页面自己的 `TvFocusMemory.restore()`
  /// （按序号就近恢复，最多试 4 帧）先落地。
  static const int _regionGrace = 6;

  /// 同一个浮空状态最快隔多久再看护一次。
  ///
  /// 有的落点是"要不到"的（例如它在 `descendantsAreFocusable: false` 的子树里，
  /// 框架会把焦点交给最近的祖先），这时"送进去 → 又浮起来"会变成死循环。
  /// 同一个 scope 上刚试过就歇一会儿再说。
  static const Duration _retryGap = Duration(milliseconds: 400);

  /// 最近一次"最上面那一层"的路由。`FocusManager` 的监听靠它找看护目标。
  Route<dynamic>? _current;

  /// 正在看护的路由。
  Route<dynamic>? _watching;
  int _frames = 0;
  bool _scheduled = false;

  /// 上一次动手时浮着的那个 scope + 时间（见 [_retryGap]）。
  FocusScopeNode? _lastFloat;
  DateTime _lastActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 从 A 进 B：先记住 A 上待着的地方，退回 A 时还给人家
    TvFocusReturn.remember(previousRoute);
    TvFocusReturn.forget(route);
    _current = route;
    _watch(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    TvFocusReturn.forget(oldRoute);
    if (newRoute == null) return;
    _current = newRoute;
    _watch(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 被 pop 掉的那一层不用再记了，下面那一层要归还
    TvFocusReturn.forget(route);
    _current = previousRoute;
    _watch(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    TvFocusReturn.forget(route);
    _current = previousRoute;
    _watch(previousRoute);
  }

  /// 用户正拿手指/鼠标拖页面时别动焦点：这时候焦点该跟着手势走。
  @override
  void didStartUserGesture(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) => _stop();

  /// 焦点一浮空就看护——页面自己弄丢焦点的情况（列表刷新把聚焦的卡片干掉、
  /// 切栏重建、锚点被拆）全靠这一条，不用等用户按键。
  void _onFocusChange() {
    if (_watching != null) return; // 已经在看护了，别插队
    final route = _current;
    if (route == null) return;
    final place = _placeOf(route);
    if (place == _Place.settled || place == _Place.panel) return;
    // 同一个落点刚试过就先别动（见 [_retryGap]）
    if (identical(FocusManager.instance.primaryFocus, _lastFloat) &&
        DateTime.now().difference(_lastActionAt) < _retryGap) {
      return;
    }
    _watch(route);
  }

  void _watch(Route<dynamic>? route) {
    if (!Pref.tvFocus || route == null || !route.requestFocus) {
      _stop();
      return;
    }
    _watching = route;
    _frames = 0;
    _schedule();
  }

  void _stop() {
    _watching = null;
    _frames = 0;
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _try();
    });
    // 页面静止（没有动画、也没有重建）时也得有帧回调，不然看护就断了
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _try() {
    final route = _watching;
    if (route == null) return;
    if (_frames++ < _skipFrames) {
      _schedule();
      return;
    }
    if (_frames > _watchFrames) {
      _stop();
      return;
    }
    if (!route.isCurrent) {
      // 被别的层盖住了（pop 动画还没收尾、上面又开了个弹层）：不动手，但继续看
      _schedule();
      return;
    }
    switch (_placeOf(route)) {
      case _Place.settled || _Place.panel:
        // 已经有控件接住了 / 弹层自己在管（`TvFocusOnOpen`）：收手
        _stop();
      case _Place.region:
        if (_frames > _regionGrace && _focusRegionFirst()) {
          _acted();
          return;
        }
        _schedule();
      case _Place.empty || _Place.page:
        // 退栈归还优先（"从哪儿进的退到哪儿"），没记过就落页面入口
        if (TvFocusReturn.restore(route)) {
          _acted();
          return;
        }
        _schedule();
      case _Place.elsewhere:
        // 焦点在别的层上（下面那页、上面盖着的弹层）：不关我们的事，先看着
        _schedule();
    }
  }

  /// 焦点浮在区域 scope 上：落到区域首项（`TvFocusMemory` 没接住时的兜底）。
  bool _focusRegionFirst() {
    final focus = FocusManager.instance.primaryFocus;
    return focus is FocusScopeNode && TvRegions.focusFirstInScope(focus);
  }

  /// 送进去之后收手，并记下"刚才是从哪个浮空状态修好的"（见 [_retryGap]）。
  ///
  /// 这里读到的 `primaryFocus` 还是**动手前**那个：`requestFocus` 是延迟到
  /// 微任务才生效的，所以记下来正好是我们修掉的那个 scope。
  void _acted() {
    final focus = FocusManager.instance.primaryFocus;
    _lastFloat = focus is FocusScopeNode ? focus : null;
    _lastActionAt = DateTime.now();
    _stop();
  }

  /// 焦点相对 [route] 这一层是个什么状态。
  static _Place _placeOf(Route<dynamic> route) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || identical(focus, FocusManager.instance.rootScope)) {
      return _Place.empty;
    }
    final context = focus.context;
    if (context == null || !context.mounted) return _Place.empty;
    if (!identical(ModalRoute.of(context), route)) return _Place.elsewhere;
    // 控件拿着焦点：这一层落地了
    if (focus is! FocusScopeNode) return _Place.settled;
    if (TvOverlayScopes.contains(focus)) return _Place.panel;
    if (TvRegions.isRegion(focus)) return _Place.region;
    return _Place.page;
  }
}

/// 焦点相对"正在被看护的那一层"的状态，见 [TvRouteFocusObserver._placeOf]。
enum _Place {
  /// 这一层里有控件拿着焦点：落地了，收手。
  settled,

  /// 没焦点，或者焦点停在根 scope 上。
  empty,

  /// 焦点浮在这一层**路由自己**的 scope 上（换页刚发生时的常态）。
  page,

  /// 焦点浮在这一层某个**区域**的 scope 上（区域里的项刚被销毁）。
  region,

  /// 焦点浮在这一层某个**弹层**的 scope 上（`TvFocusOnOpen` 在管）。
  panel,

  /// 焦点在**别的层**上（被盖住的那页、上面盖着的弹层）：不动手，但继续看。
  elsewhere,
}

/// 全局实例：挂进 `GetMaterialApp.navigatorObservers`。
final NavigatorObserver tvRouteFocusObserver = TvRouteFocusObserver();
