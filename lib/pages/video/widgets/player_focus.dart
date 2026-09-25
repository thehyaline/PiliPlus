import 'dart:async';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

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
/// - 桌面模式（关闭手柄 / 遥控器模式）：原来的键位表，方向键 = 音量/快进，
///   空格 = 播放暂停，Tab 被吞掉；
/// - 手柄播放器模型（视频页 + 直播页 + `Pref.tvFocus`，见 `isPlayerTvMode`）：
///   * 方向键和确定键（手柄 A / 遥控器确定 / 回车）**全部放行**，交给焦点系统
///     和画面那一层（见 `TvPlayerSurface`）：非全屏时方向键在页面里移动预选框、
///     确定键进全屏；全屏时方向键唤起上下栏并把焦点送回播放/暂停按钮、
///     上下栏收着时确定键是播放/暂停；
///   * 这一层只留播放器自己的键：B 收控制条（收着时让出去，当"退出"用）、
///     空格播放暂停、字母快捷键，以及 [TvMediaKeys] 上的媒体键。
///   * 焦点停在控制条（OSD）里时，这一层吃得下的键只剩"重新计时"：
///     跟控制条有关的行为（方向键移动预选框、空格/Tab 交给框架、
///     **ESC / B / 安卓返回键先收控制条**）全都由控件自己和
///     `PlPlayerController.hideControlsOnBack` 负责——ESC 在桌面端根本
///     到不了焦点树（`main.dart` 的 early handler 直接送进 `appBack()`），
///     安卓的返回键也走系统那一路，只有把规则放在它们**共同**的落点上才管用。
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

  /// 手柄播放器模型下**必须放行**的键：方向键 + 确定（手柄 A / 遥控器确定 /
  /// 回车），见 `TvKeys.isConfirm`。
  ///
  /// 不含空格：空格一直是"播放暂停"，遥控器/手柄也不会发空格，桌面键位表继续管它。
  /// 不含 Tab：框架的 `NextFocusIntent`，本来也不该被播放器吃掉。
  static bool _isFocusKey(KeyEvent event) =>
      TvKeys.isDpad(event) || TvKeys.isConfirm(event);

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
    // 焦点要落到它头上，见 `TvPlayerSurface.dispose`
    TvRegions.registerAnchor(TvLabels.playerPage, _node);
    return Focus(
      focusNode: _node,
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
            // 方向键/确定键一律放行——方向键走几何寻焦在界面里移动预选框，
            // 确定键由画面那层（进全屏 / 播放暂停）或控件自己（激活）接
            if (_isFocusKey(event)) {
              return KeyEventResult.ignored;
            }
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
