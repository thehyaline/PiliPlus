import 'dart:async';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/focus/tv_shortcuts.dart';
import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart'
    show
        KeyDownEvent,
        KeyEvent,
        KeyUpEvent,
        LogicalKeyboardKey,
        HardwareKeyboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// 播放器的按键层（画面本身 + 整个 OSD 都在它下面）。
///
/// 分两种情况：
/// - 桌面模式（关闭手柄 / 遥控器模式）：原来的键位表，**全屏和非全屏一样**
///   ——方向键 ↑↓ = 音量、←→ = 快进/快退（直播没有进度，只调音量），
///   空格 = 播放暂停，Tab 被吞掉。这一页全程不出现预选框（见 `TvInputMode`
///   的播放页压制）；
/// - 手柄播放器模型（视频页 + 直播页 + `Pref.tvFocus`，见 `isPlayerTvMode`）：
///   * 方向键由这一层接管（[_moveFocus]）：先走框架的几何寻焦，走不通再按方向
///     几何兜底扫描，保证"按了就一定动"；焦点悬在页面那一层/整页落脚点上时，
///     第一下当"唤醒"，先把预选框送进画面；
///   * 确定键（手柄 A / 遥控器确定 / 回车）**无条件放行**，交给画面那一层
///     （见 `TvPlayerSurface`）和控件自己：非全屏时进全屏、全屏时播放/暂停、
///     焦点在控件上时激活那个控件；
///   * 这一层只留播放器自己的键：B 收控制条（收着时让出去，当"退出"用）、
///     空格播放暂停、字母快捷键，以及 [TvMediaKeys] 上的媒体键。
///     桌面键位表那几条只在关掉手柄模式时才管用：手柄模式下焦点在页面里时
///     ↑↓/←→ 要是被桌面键位表当音量、快进吃掉，手柄就困在当前那张卡上了。
///   * 焦点停在控制条（OSD）里时，这一层吃得下的键只剩"重新计时"：
///     跟控制条有关的行为（方向键移动预选框、空格/Tab 交给框架、
///     **ESC / B / 安卓返回键先收控制条**）全都由控件自己和
///     `PlPlayerController.hideControlsOnBack` 负责——ESC 在桌面端根本
///     到不了焦点树（`main.dart` 的 early handler 直接送进 `appBack()`），
///     安卓的返回键也走系统那一路，只有把规则放在它们**共同**的落点上才管用。
///
/// 这一层还登记了两个锚点：`TvLabels.playerPage`（页面级落脚点，画面那一层
/// 不在树上时接住焦点。它是整页大小的节点，标了 `lastResort`）和手柄模式
/// 关闭时的 `TvLabels.playerSurface`（那时它就是整页的键位层）。
/// 它是**落脚点**不是"一个整体焦点"，所以焦点停在自己身上时不画预选框
/// （见 [build] 里 `FocusRing` 的 `hideRing`）。
///
/// 媒体键（键盘/耳机/遥控器上的播放暂停、上一集、快进）挂在 [TvMediaKeys] 上，
/// 页面只要有播放器就生效。
class PlayerFocus extends StatefulWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    this.introController,
    required this.onSendDanmaku,
    this.canPlay,
    this.onSkipSegment,
    this.onRefresh,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final CommonIntroController? introController;
  final VoidCallback onSendDanmaku;
  final ValueGetter<bool>? canPlay;
  final ValueGetter<bool>? onSkipSegment;
  final VoidCallback? onRefresh;

  static bool _shouldHandle(LogicalKeyboardKey logicalKey) {
    return logicalKey == LogicalKeyboardKey.tab ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown;
  }

  @override
  State<PlayerFocus> createState() => _PlayerFocusState();
}

class _PlayerFocusState extends State<PlayerFocus> {
  late final FocusNode _node = FocusNode(debugLabel: 'PlayerFocus');

  PlPlayerController get _ctr => widget.plPlayerController;
  bool get isFullScreen => _ctr.isFullScreen.value;
  bool get hasPlayer => _ctr.videoPlayerController != null;

  /// 手柄 / 遥控器模式（= 手柄播放器模型，`isPlayerTvMode()` 也是它）。
  bool get _tvMode => isPlayerTvMode();

  /// 焦点是不是在 OSD（顶部信息栏 / 底部控制条）里面。
  bool get _inOsd => TvRegions.hasFocus(TvLabels.playerOsd);

  /// 手柄播放器模型下**必须放行**的是确定键（手柄 A / 遥控器确定 / 回车，
  /// [TvKeys.isConfirm]）——由画面那一层或控件自己接。
  ///
  /// 方向键**不放行**，由 [_moveFocus] 自己接管：焦点停在整页大小的落脚点上时，
  /// 框架的几何寻焦一个候选都挑不出来，放行等于"方向键按下去没反应"。
  ///
  /// 空格不放行也一样：空格一直是"播放暂停"，遥控器/手柄也不会发空格，
  /// 桌面键位表继续管它。Tab 同理，框架的 `NextFocusIntent` 不该被播放器吃掉。

  late final TvMediaKeyTarget _mediaKeys = TvMediaKeyTarget(
    onPlayPause: _togglePlay,
    onSeekBackward: () => _seek(isForward: false),
    onSeekForward: () => _seek(isForward: true),
    onPrev: widget.introController?.prevPlay,
    onNext: widget.introController?.nextPlay,
  );

  @override
  void initState() {
    super.initState();
    TvMediaKeys.push(_mediaKeys);
  }

  @override
  void dispose() {
    TvRegions.unregisterAnchor(TvLabels.playerSurface, _node);
    TvRegions.unregisterAnchor(TvLabels.playerPage, _node);
    TvMediaKeys.remove(_mediaKeys);
    _node.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_ctr.isLive || (widget.canPlay?.call() ?? true)) {
      if (hasPlayer) {
        _ctr.onDoubleTapCenter();
      }
    }
  }

  void _seek({required bool isForward}) {
    if (_ctr.isLive || !hasPlayer) {
      return;
    }
    if (isForward) {
      _ctr.onForward(_ctr.fastForBackwardDuration);
    } else {
      _ctr.onBackward(_ctr.fastForBackwardDuration);
    }
  }

  /// 手柄模式下的 B / Esc（[TvKeys.isBack]）：控制条亮着就只收控制条，
  /// 焦点回到画面，返回 true（这个键吃完了，不再走桌面键位表）。
  ///
  /// 控制条本来就收着时不吃它——那时 B 的语义是"退出"，交给上层。
  /// 按下/重复/抬起都吃掉同一个 B：不然抬起时又来一次返回。
  ///
  /// 只在焦点**不在**控制条里时走这里（见 [build]）：焦点停在 OSD 上时这一层
  /// 收不到这个键的判断，那条路交给 `PlPlayerController.hideControlsOnBack`
  /// ——它同时兜住桌面端的 Esc（走不到焦点树）和安卓的返回键。
  bool _handleTvKey(KeyEvent event) {
    if (!TvKeys.isBack(event)) {
      return false;
    }
    if (!_ctr.showControls.value) {
      return false;
    }
    if (TvKeys.isFirstPress(event)) {
      _ctr.controls = false;
      // 走锚点而不是 `_node`：手柄播放器模型下画面那一层自己持有节点
      TvRegions.focusAnchor(TvLabels.playerSurface);
    }
    return true;
  }

  /// 手柄模式下方向键的去处：**让焦点真的动起来**。
  ///
  /// 三级往下走：
  ///
  /// 1. 焦点"悬空"（停在某个 scope 上）或者停在这一页的**落脚点**上
  ///    （[TvLabels.playerPage]，整页那么大）——这一下当"唤醒"：先把预选框送进
  ///    画面（[TvLabels.playerSurface]），画面那一层还没建出来就退回页面入口
  ///    （[TvRegions.focusRouteEntry]）。焦点停在整页节点上时框架的几何寻焦
  ///    一个候选都挑不出来（候选必须完全落在它的边之外），不先挪出来，
  ///    方向键就永远按不动——这就是"移动焦点失效"的那一半。
  /// 2. 框架的几何寻焦（`FocusNode.focusInDirection`，和框架自己那条路完全一样，
  ///    连"反方向按回去"的记忆一起保留）：候选完全落在起点边之外才算，
  ///    最稳，也顺带把候选滚进视口。
  /// 3. 还是没动（起点跨满了一整维、那个方向上没有"完整在外"的候选）：
  ///    [TvRegions.focusInDirection] 按方向几何挑最近的真控件兜底。
  ///
  /// 三级都不行就当这个方向没地方可去，键照样吃掉——留给框架也没有别的动作。
  void _moveFocus(TraversalDirection direction) {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus;
    // ① 悬空 / 停在整页落脚点上
    if (primary == null ||
        primary is FocusScopeNode ||
        identical(primary, TvRegions.anchor(TvLabels.playerPage))) {
      if (TvRegions.focusAnchor(TvLabels.playerSurface)) return;
      TvRegions.focusRouteEntry();
      return;
    }
    // ② 框架那一套：看 `focusInDirection` 的**返回值**，不能看 `primaryFocus`
    //    变没变——`requestFocus` 只是记下"下一个焦点是谁"，真正应用要等一个
    //    微任务（`_markNextFocus`），在同一个同步按键处理器里读到的
    //    `primaryFocus` 永远是老的那个。照那个条件判，兜底扫描就没有不发生的时候，
    //    而它的评分（`dx + 2|dy|`）比框架的"同一条带里取最近"粗得多：
    //    OSD 下栏左下最后一颗按 → 时，框架挑的是居右一组的第一个按钮，
    //    兜底扫描却会挑中横跨整屏的进度条（它的中心离得很近）。
    if (primary.context != null && primary.focusInDirection(direction)) {
      return;
    }
    // ③ 兜底扫描：框架真的一个候选都挑不出来（起点跨满了一整维、那个方向上
    //    没有"完整在它边之外"的候选）才走这里
    TvRegions.focusInDirection(direction, from: primary);
  }

  @override
  Widget build(BuildContext context) {
    // 锚点的登记人按模式换：手柄播放器模型下由画面那一层
    // （`TvPlayerSurface`）登记，其余情况是这一层的页面级节点。
    // 写在 build 里（不是 initState）才能在运行中开关设置后换人；
    // 各自只撤销自己登记的节点（identity 检查），不会互相误删。
    if (!_tvMode) {
      TvRegions.registerAnchor(TvLabels.playerSurface, _node);
    }
    // 页面级锚点：画面那一层被移出树时（切布局、画中画、播放器还没就绪……）
    // 焦点要落到它头上，见 `TvPlayerSurface.dispose`。它是**整页大小**的节点，
    // 所以标成 `lastResort`：挑页面入口（`TvRegions.entryNodeFor`）时排在真控件
    // 后面——焦点停在这上面，框架的几何寻焦会一个候选都挑不出来（方向键"死"）。
    TvRegions.registerAnchor(TvLabels.playerPage, _node, lastResort: true);
    // 这一层是**落脚点**，不是"一个整体焦点"：进出页面、等画面那一层建出来的
    // 空档里焦点会短暂停在它身上（`TvRegions.entryNodeFor` 的锚点、
    // `TvFocusReturn.restore` 的第 3 级），而它占的是整页那么大一块——
    // 兜底环照着画出来就是"进页面时窗口大小的预选框闪一下"。
    // 所以登记成"有焦点也不画环"（详见 `FocusRing.hideRing`）。
    return FocusRing(
      focusNode: _node,
      debugLabel: 'PlayerFocus',
      hideRing: true,
      // 也不替子树里的焦点出预选框：整页那些裸控件（简介里的按钮之类）
      // 该由兜底环兜着，这一层让位只让"焦点停在自己身上"那一下
      ringOnPrimaryFocus: true,
      // 本来就不画环，缩放也别留（焦点停在这一层时整页不该弹一下）
      scale: 1.0,
      builder: (context, node, focused) => Focus(
        focusNode: node,
        autofocus: !_tvMode,
        // 手柄播放器模型下这一层**不再自动聚焦**（树序上祖先会赢过后代，
        // 自动聚焦要留给画面那一层），但必须保持可聚焦：画面那一层从树上
        // 消失时它是唯一还活着、"接得住"的节点。
        // 不会和画面抢方向键——`skipTraversal` 让几何寻焦永远不选它。
        canRequestFocus: true,
        // 手柄模式下画面不参与方向键寻焦：控制条关着的时候，
        // 方向键不应该落在这块"什么都没有"的画面区域上
        skipTraversal: _tvMode,
        onKeyEvent: (node, event) {
          if (_tvMode) {
            // 焦点在控制条里时，任何一次按键都算"人还在操作"：
            // 手柄模式下焦点停在 OSD 里**不再豁免**自动隐藏（一停手就收，
            // 焦点由 `PlayerTvOsd` 拉回画面），所以每按一下都要把计时推后
            if (_inOsd) {
              _ctr.keepControlsAlive();
            }
            // 方向键这一层自己接管：按下/重复/抬起整段吃掉（[_moveFocus] 里
            // 先把框架那条路走一遍，走不通再兜底扫描），不然焦点停在整页大小的
            // 落脚点上时，框架找不到"完全在它边之外"的候选，按下去什么也不动。
            if (TvKeys.isDpad(event)) {
              if (TvKeys.isPressOrRepeat(event)) {
                _moveFocus(TvKeys.directionOf(event)!);
              }
              return KeyEventResult.handled;
            }
            // 确定键**无条件放行**（焦点在控制条里、在页面卡片上、在画面上
            // 都一样）：由画面那层（非全屏进全屏 / 全屏播放暂停）或控件自己
            // （激活）接。这一条不能挪到 `_inOsd` 里面：焦点在页面里时确定键
            // 要是被这里的桌面键位表（回车 = 发弹幕）吃掉，卡片就点不开了。
            if (TvKeys.isConfirm(event)) {
              return KeyEventResult.ignored;
            }
            if (_inOsd) {
              // 空格/Tab 也交回框架（激活焦点控件 / 切换焦点），
              // 桌面键位表里的"空格 = 播放暂停"在控制条里让位
              if (event.logicalKey == LogicalKeyboardKey.space ||
                  event.logicalKey == LogicalKeyboardKey.tab) {
                return KeyEventResult.ignored;
              }
            } else if (_handleTvKey(event)) {
              return KeyEventResult.handled;
            }
          }
          final handled = _handleKey(context, event);
          if (handled ||
              (!_tvMode && PlayerFocus._shouldHandle(event.logicalKey))) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: widget.child,
      ),
    );
  }

  bool _handleKey(BuildContext context, KeyEvent event) {
    final key = event.logicalKey;

    final isKeyQ = key == LogicalKeyboardKey.keyQ;
    if (isKeyQ || key == LogicalKeyboardKey.keyR) {
      if (HardwareKeyboard.instance.isMetaPressed) {
        if (isKeyQ && Platform.isMacOS) {
          exit(0);
        }
        return true;
      }
      if (event is KeyDownEvent) {
        if (_ctr.isLive) {
          widget.onRefresh?.call();
        } else {
          widget.introController!.onStartTriple();
        }
      } else if (event is KeyUpEvent && !_ctr.isLive) {
        widget.introController!.onCancelTriple(isKeyQ);
      }
      return true;
    } else if (event is KeyDownEvent) {
      if (widget.introController?.isTripling ?? false) {
        widget.introController!.onCancelTriple();
      }
    }

    final isArrowUp = key == LogicalKeyboardKey.arrowUp;
    if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
      _updateVolume(event, isIncrease: isArrowUp);
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!_ctr.isLive) {
        if (event is KeyDownEvent) {
          if (hasPlayer && !_ctr.longPressStatus.value) {
            _ctr
              ..longPressTimer?.cancel()
              ..longPressTimer = Timer(
                const Duration(milliseconds: 200),
                () => _ctr
                  ..cancelLongPressTimer()
                  ..setLongPressStatus(true),
              );
          }
        } else if (event is KeyUpEvent) {
          _ctr.cancelLongPressTimer();
          if (hasPlayer) {
            if (_ctr.longPressStatus.value) {
              _ctr.setLongPressStatus(false);
            } else {
              _ctr.onForward(_ctr.fastForBackwardDuration);
            }
          }
        }
      }
      return true;
    }

    if (event is KeyDownEvent) {
      final isDigit1 = key == LogicalKeyboardKey.digit1;
      if (isDigit1 || key == LogicalKeyboardKey.digit2) {
        if (HardwareKeyboard.instance.isShiftPressed && hasPlayer) {
          final speed = isDigit1 ? 1.0 : 2.0;
          if (speed != _ctr.playbackSpeed) {
            _ctr.setPlaybackSpeed(speed);
          }
          SmartDialog.showToast('${speed}x播放');
        }
        return true;
      }

      switch (key) {
        case LogicalKeyboardKey.space:
          if (_ctr.isLive || widget.canPlay!()) {
            if (hasPlayer) {
              _ctr.onDoubleTapCenter();
            }
          }
          return true;

        case LogicalKeyboardKey.keyX:
        case LogicalKeyboardKey.keyF:
          final isFullScreen = this.isFullScreen;
          if (isFullScreen && _ctr.controlsLock.value) {
            _ctr
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          _ctr.triggerFullScreen(
            status: !isFullScreen,
            inAppFullScreen: key == LogicalKeyboardKey.keyX,
          );
          return true;

        case LogicalKeyboardKey.keyD:
          final newVal = !_ctr.enableShowDanmakuAdaptive.value;
          _ctr.enableShowDanmakuAdaptive.value = newVal;
          if (!_ctr.tempPlayerConf) {
            GStorage.setting.put(
              _ctr.isLive
                  ? SettingBoxKey.enableShowLiveDanmaku
                  : SettingBoxKey.enableShowDanmaku,
              newVal,
            );
          }
          return true;

        case LogicalKeyboardKey.keyP:
          if (PlatformUtils.isDesktop && hasPlayer && !isFullScreen) {
            _ctr
              ..toggleDesktopPip()
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          return true;

        case LogicalKeyboardKey.keyM:
          if (hasPlayer) {
            final isMuted = !_ctr.isMuted;
            _ctr.videoPlayerController!.setVolume(
              isMuted ? 0 : _ctr.volume.value * 100,
            );
            _ctr.isMuted = isMuted;
            SmartDialog.showToast('${isMuted ? '' : '取消'}静音');
          }
          return true;

        case LogicalKeyboardKey.keyS:
          if (hasPlayer && isFullScreen) {
            _ctr.takeScreenshot();
          }
          return true;

        case LogicalKeyboardKey.keyL:
          if (isFullScreen || _ctr.isDesktopPip) {
            _ctr.onLockControl(!_ctr.controlsLock.value);
          }
          return true;

        case LogicalKeyboardKey.enter:
          if (widget.onSkipSegment?.call() ?? false) {
            return true;
          }
          widget.onSendDanmaku();
          return true;
      }

      if (!_ctr.isLive) {
        switch (key) {
          case LogicalKeyboardKey.arrowLeft:
            if (hasPlayer) {
              _ctr.onBackward(_ctr.fastForBackwardDuration);
            }
            return true;

          case LogicalKeyboardKey.keyW:
            if (HardwareKeyboard.instance.isMetaPressed) {
              return true;
            }
            widget.introController?.actionCoinVideo();
            return true;

          case LogicalKeyboardKey.keyE:
            widget.introController?.actionFavVideo(isQuick: true);
            return true;

          case LogicalKeyboardKey.keyT || LogicalKeyboardKey.keyV:
            widget.introController?.viewLater();
            return true;

          case LogicalKeyboardKey.keyG:
            if (widget.introController case final UgcIntroController ugcCtr) {
              ugcCtr.actionRelationMod(context);
            }
            return true;

          case LogicalKeyboardKey.bracketLeft:
            if (widget.introController case final introController?) {
              introController.prevPlay();
            }
            return true;

          case LogicalKeyboardKey.bracketRight:
            if (widget.introController case final introController?) {
              introController.nextPlay();
            }
            return true;
        }
      }
    }

    return false;
  }

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? math.min(_ctr.maxVolume, _ctr.volume.value + 0.1)
        : math.max(0.0, _ctr.volume.value - 0.1);
    _ctr.setVolume(volume);
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        _ctr
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      _ctr.cancelLongPressTimer();
    }
  }
}
