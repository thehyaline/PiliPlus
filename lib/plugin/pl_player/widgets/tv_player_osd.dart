import 'dart:async';

import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:material_ui/material_ui.dart';

/// 播放器 OSD（顶部信息栏 + 底部控制条）的手柄外壳，视频页和直播页共用。
///
/// 只在手柄模式（`Pref.tvFocus`）下生效，做五件事：
/// - 整层套一个 [TvRegion]，方向键在控制条亮着的时候走不出播放器
///   （外面是详情页的卡片，手柄很容易"飘"出去）；
/// - 收起时用 `ExcludeFocus` 把整层移出焦点树。`AppBarAni` 只是个位移/透明
///   动画，藏起来之后里面的按钮照样能聚焦，方向键会落到看不见的控件上；
/// - 手柄播放器模型下（[videoMode]）**非全屏时整层也不可聚焦**：那种状态下
///   播放器只有"整块画面"一个焦点（见 `TvPlayerSurface`），OSD 是给鼠标/触摸
///   用的浮层，能聚焦只会让焦点跑进一块随时会自己隐藏的浮层里；
/// - 焦点停进控制条时不让它自动隐藏（3 秒定时器会把焦点甩掉，见
///   `PlPlayerController.tvFocusInControls`）；
/// - 焦点在控制条里、控制条却被别的方式收了（触摸、切全屏、锁屏）时
///   把焦点送回画面，免得按键落进看不见的按钮。
class PlayerTvOsd extends StatefulWidget {
  const PlayerTvOsd({
    super.key,
    required this.showControls,
    required this.onFocusInOsd,
    required this.child,
    this.videoMode = false,
    this.fullScreen,
  });

  /// 控制条可见性，直接给 `PlPlayerController.showControls`。
  final RxBool showControls;

  /// 焦点进出控制条的通知（写给 `PlPlayerController.tvFocusInControls`）。
  final ValueChanged<bool> onFocusInOsd;

  /// 手柄播放器模型（`isPlayerTvMode`）：视频页和直播页都开着它就是 true。
  final bool videoMode;

  /// 全屏状态，直接给 `PlPlayerController.isFullScreen`。
  ///
  /// 只有 [videoMode] 开着时才需要传：它决定控制条能不能聚焦。
  final RxBool? fullScreen;

  final Widget child;

  @override
  State<PlayerTvOsd> createState() => _PlayerTvOsdState();
}

class _PlayerTvOsdState extends State<PlayerTvOsd> {
  bool _inOsd = false;
  StreamSubscription<bool>? _visibility;
  StreamSubscription<bool>? _fullScreen;

  /// 控制条现在能不能被焦点系统访问。
  ///
  /// 手柄播放器模型下非全屏是**不能**的：那个状态下播放器的唯一焦点是整块
  /// 画面（确定键进全屏），方向键该在页面里移动预选框，而不是走进这层
  /// 一碰就会自己隐藏的浮层——进去了画面那一层还会跟着画一圈，
  /// 同屏两个预选框。
  bool get _focusable =>
      !widget.videoMode || (widget.fullScreen?.value ?? false);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
    _visibility = widget.showControls.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _fullScreen = widget.fullScreen?.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(PlayerTvOsd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fullScreen != oldWidget.fullScreen) {
      _fullScreen?.cancel();
      _fullScreen = widget.fullScreen?.listen((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    _visibility?.cancel();
    _fullScreen?.cancel();
    // 只改一个 bool 字段：控制器有可能先于这一层销毁
    widget.onFocusInOsd(false);
    super.dispose();
  }

  void _onFocusChange() {
    final inOsd = TvRegions.hasFocus(TvLabels.playerOsd);
    final wasInOsd = _inOsd;
    _inOsd = inOsd;
    if (inOsd) {
      if (!wasInOsd) {
        widget.onFocusInOsd(true);
      }
      return;
    }
    if (!wasInOsd) {
      return;
    }
    // 焦点离开了控制条，三种情况：
    // 1. 按了 B（`PlayerFocus` 已经把焦点送回画面了）；
    // 2. 控制条被别的方式收掉：触摸点一下画面、3 秒自动隐藏、切全屏、锁屏。
    //    这些收法框架会把焦点退回根 scope，之后播放器的音量/快进/确定键全都
    //    没反应，所以必须把焦点拉回画面；
    // 3. 从控制条上打开了面板/菜单（画质、弹幕设置、播放信息……）。这时播放器
    //    所在的路由已经不是最上层了：**不能抢焦点**（会把面板的选项抢走），
    //    也不能报告"焦点离开控制条"（否则自动隐藏会把控制条收掉，面板关掉
    //    之后焦点就没地方回了）。
    // `mounted` 一起看：拆树的时候这一层可能已经 deactivate 了，
    // 那种状态下查祖先（`ModalRoute.of`）会被框架拦下来
    if (!mounted || !TvRegions.isCurrentRoute(context)) {
      return;
    }
    widget.onFocusInOsd(false);
    TvRegions.focusAnchor(TvLabels.playerSurface);
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) {
      return widget.child;
    }
    return ExcludeFocus(
      excluding: !widget.showControls.value || !_focusable,
      child: TvRegion(
        debugLabel: TvLabels.playerOsd,
        // stop：控制条亮着的时候方向键留在 OSD 里（按 B 收起来才回到画面）
        edgeBehavior: TraversalEdgeBehavior.stop,
        child: widget.child,
      ),
    );
  }
}
