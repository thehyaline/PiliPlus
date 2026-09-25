import 'dart:async';

import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:material_ui/material_ui.dart';

/// 播放器（视频页和直播页共用）"**整块画面**"这一层焦点。
///
/// 只在手柄 / 遥控器模式（[TvPlayerSurface.enabled]，见 `isPlayerTvMode`）下装，
/// 关着时原样返回 [child]，这一层不进焦点树、不画框、不注册锚点。
///
/// 两种状态的分工就是 `isFullScreen`（窗口全屏和全屏一样算全屏）：
///
/// - **非全屏**：整块画面 = 一个焦点，播放器里的控件一个都进不了焦点树
///   （`PlayerTvOsd` 在非全屏把整层 `ExcludeFocus`），焦点环贴着视频内边缘画
///   （`FocusRing` 的描边是 `Positioned.fill` 画在边界内的，不会被视口裁掉，
///   也不用给布局留外间距）。确定键 = 进全屏——这也是非全屏下**唯一**能进全屏的
///   路，控制条那时根本不能聚焦。方向键原样放行，走框架的几何寻焦去页面里
///   别的卡片。
/// - **全屏**：画面不再是"一个整体焦点"（焦点能进上下栏了），它退化成
///   "上下栏收起来时焦点停的地方"，所以**不画环**。这时候：
///   * 确定键 = 播放/暂停（对齐 BBLL）；
///   * 任何方向键 = 唤起上下栏 + 焦点送到播放/暂停按钮（[onWakeControls]），
///     所以"上下栏收着"是这一层唯一会停留的状态，按一下方向键就进控件；
///   * 上下栏自己用进栏锁把落点锁死（`TvEntryLock`），不用在这一层判方向。
///
/// 为什么不缩放：`scale` 保持 1.0。1.04 倍会把整块画面推出视口，
/// 而且画面本来就不该"被焦点框起来抖一下"。
class TvPlayerSurface extends StatefulWidget {
  const TvPlayerSurface({
    super.key,
    required this.enabled,
    required this.fullScreen,
    required this.onOk,
    required this.onWakeControls,
    required this.child,
  });

  /// 手柄 / 遥控器模式（`isPlayerTvMode`）。
  final bool enabled;

  /// 全屏状态，直接给 `PlPlayerController.isFullScreen`。
  ///
  /// 窗口全屏（`inAppFullScreen`）也是全屏——两种全屏都会让 `isFullScreen`
  /// 为真，这一层只认这一个值。
  final RxBool fullScreen;

  /// 确定键：手柄 A / 遥控器确定 / 回车。
  final VoidCallback onOk;

  /// 全屏下按方向键：唤起上下栏，并把焦点送到播放/暂停按钮。
  final VoidCallback onWakeControls;

  final Widget child;

  @override
  State<TvPlayerSurface> createState() => _TvPlayerSurfaceState();
}

class _TvPlayerSurfaceState extends State<TvPlayerSurface> {
  late final FocusNode _node = FocusNode(debugLabel: 'TvPlayerSurface');
  StreamSubscription<bool>? _fullScreen;

  /// 这一层被移出树的时候，焦点是不是还在自己（含 OSD 里的子节点）身上。
  ///
  /// 必须在 [deactivate] 里记：那是整棵子树**从外往内**第一个回调，
  /// 再往后（`Focus` 那一层的 `deactivate`）节点就 detach 了，
  /// 到 `dispose` 时 `hasFocus` 只会是 false，问不出真实情况。
  bool _hadFocus = false;

  bool get _full => widget.fullScreen.value;

  @override
  void initState() {
    super.initState();
    _listenFullScreen();
    // 播放器是**后来才建出来**的：`videoState` 没就绪、`autoPlay` 关着、
    // 切布局、拉流失败重试……这些时候 `PLVideoPlayer` 被换成
    // `SizedBox.shrink()`，这一层也跟着不在树上。等它建出来，这一页的焦点
    // 多半已经悬在一层 scope 上（换页之后框架只把焦点交给路由的 scope）
    // 或者悬在 `TvLabels.playerPage` 那个页面级节点上——"进页面时焦点落在
    // 视频上"得由画面自己接手（`autofocus` 只在同一批里没人拿焦点时才有用）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _claimFocus();
    });
  }

  @override
  void didUpdateWidget(TvPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fullScreen != oldWidget.fullScreen) {
      _listenFullScreen();
    }
    // 运行中把「手柄/遥控器模式」关掉：这一层下一帧就不在树上了，
    // 焦点同样是"要人接"的情况，规矩和画面被移除时一样。
    if (oldWidget.enabled && !widget.enabled && _node.hasFocus) {
      TvRegions.focusAnchor(TvLabels.playerPage);
    }
    if (!oldWidget.enabled && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _claimFocus();
      });
    }
  }

  @override
  void deactivate() {
    if (_node.hasFocus) {
      _hadFocus = true;
    }
    super.deactivate();
  }

  @override
  void activate() {
    // 被 GlobalKey 之类搬了个位置又重新插回树上，焦点其实没丢
    _hadFocus = false;
    super.activate();
  }

  @override
  void dispose() {
    _fullScreen?.cancel();
    TvRegions.unregisterAnchor(TvLabels.playerSurface, _node);
    if (_hadFocus) {
      _hadFocus = false;
      // 画面没了，焦点得有人接：交给页面那一层（`PlayerFocus`）。
      // 它还活着（它包的是播放器所在的那块区域，不是播放器本身），
      // 而且手柄播放器模型下它的方向键本来就是让给焦点系统的，接着按就能继续走。
      // 整页退出时它会先一步（子树先 dispose）变成不可用，
      // `focusAnchor` 那个 mounted 检查会发现，什么也不做——
      // 那种情况该由新页面自己接管焦点。
      // `checkRoute: false`：dispose 里不能查祖先（见 `focusAnchor` 的说明）。
      TvRegions.focusAnchor(TvLabels.playerPage, checkRoute: false);
    }
    _node.dispose();
    super.dispose();
  }

  /// 全屏状态变化：环的画法（[FocusRing.hideRing]）和方向键的语义跟着走；
  /// **退出全屏**时把焦点交回画面。
  ///
  /// 退出全屏时焦点可能停在控制条上，而控制条这一帧之后就不可聚焦了
  /// （`PlayerTvOsd` 在非全屏把整层 `ExcludeFocus`），不接一把焦点就悬空——
  /// 那之后按方向键什么都不会发生（环没了、也没有下一个控件可去）。
  void _listenFullScreen() {
    _fullScreen?.cancel();
    _fullScreen = widget.fullScreen.listen((_) {
      if (!mounted) return;
      final full = _full;
      setState(() {});
      if (full || !widget.enabled) return;
      if (!TvRegions.isCurrentRoute(context)) return;
      _node.requestFocus();
    });
  }

  /// 焦点"悬空"时把它接到画面这一层。
  ///
  /// 悬空 = 没有焦点、停在某个 scope 上（换页之后框架只把焦点交给路由的
  /// scope）、或者停在 `PlayerFocus` 的页面级节点上。这三种情况都说明这一页
  /// 还没有真正的落点，画面该接下来。
  void _claimFocus() {
    final primary = FocusManager.instance.primaryFocus;
    final dangling =
        primary == null ||
        primary is FocusScopeNode ||
        identical(primary, TvRegions.anchor(TvLabels.playerPage));
    if (!dangling || !TvRegions.isCurrentRoute(context)) return;
    _node.requestFocus();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 只有焦点真的停在画面**本身**上时才接管：控制条（`PlayerTvOsd`）也是
    // 这块画面的子节点，焦点落在里面的按钮上时这个节点会作为祖先跟着收到
    // 同一颗确定键——那时必须放行，否则按确定激活不了按钮。
    if (node.hasPrimaryFocus) {
      if (TvKeys.isConfirm(event)) {
        if (TvKeys.isFirstPress(event)) {
          widget.onOk();
        }
        return KeyEventResult.handled;
      }
      // 全屏：上下栏收着的时候焦点哪儿也去不了（环也不画），方向键在这里
      // 被吃掉，用来把上下栏唤起来、把焦点交给播放/暂停按钮。
      // 长按的重复事件只吞不重复唤栏。
      if (_full && TvKeys.isDpad(event)) {
        if (TvKeys.isFirstPress(event)) {
          widget.onWakeControls();
        }
        return KeyEventResult.handled;
      }
    }
    // 其余按键（空格、字母、B……）继续冒泡给 `PlayerFocus` 的键位表；
    // 非全屏时方向键也从这里放行，去页面里别的卡片
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // 每次 build 同步一次锚点：运行中开关这个设置时，锚点要能跟着换人
    // （关掉这一模式时锚点该回到 `PlayerFocus` 那个页面级节点）。
    // 撤销走 identity 检查，不会误删刚被 `PlayerFocus` 重新登记进去的节点。
    if (!widget.enabled) {
      TvRegions.unregisterAnchor(TvLabels.playerSurface, _node);
      return widget.child;
    }
    TvRegions.registerAnchor(TvLabels.playerSurface, _node);
    return FocusRing(
      focusNode: _node,
      debugLabel: 'TvPlayerSurface',
      radius: TvFocusSpec.surfaceRadius,
      borderWidth: TvFocusSpec.surfaceBorderWidth,
      // 整块画面，缩放会顶出视口；画面也不是"按钮"，不需要缩放反馈
      scale: 1.0,
      // 全屏下这一层只是"上下栏收起来时焦点停的地方"，不画环
      hideRing: _full,
      // 焦点进到 OSD 的按钮上时这一层仍然 `hasFocus`，但它不该再画一圈：
      // 同屏两个预选框看着像焦点坏了（画面那圈还留着，按钮那圈也在）
      ringOnPrimaryFocus: true,
      onKeyEvent: _onKeyEvent,
      builder: (context, node, focused) => Focus(
        focusNode: node,
        autofocus: true,
        debugLabel: 'TvPlayerSurface',
        child: widget.child,
      ),
    );
  }
}
