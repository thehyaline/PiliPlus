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
import 'package:PiliPlus/utils/storage_pref.dart';
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
/// 两种模式，靠 [Pref.tvFocus] 分流：
/// - 桌面模式（关闭手柄模式）：原来的键位表，方向键 = 音量/快进，Tab 被吞掉；
/// - 手柄模式：
///   * 焦点停在**画面**上时，方向键保持音量/快进（但会先把控制条亮起来，
///     让人知道"这里还有一套控件"），确定键（手柄 A / 遥控器确定）=
///     播放暂停 + 亮控制条；
///   * 焦点停在**控制条**里时，方向键/确定键全部让出去，交给框架做控件间
///     导航与确定——所以 [Focus.onKeyEvent] 里第一件事就是判断焦点在哪；
///   * 控制条亮着时按 B 只收控制条、焦点回到画面（对齐 blbl：不顺手退出播放器）；
///   * 媒体键（键盘/耳机/遥控器上的播放暂停、上一集、快进）挂在
///     [TvMediaKeys] 上，页面只要有播放器就生效。
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
  bool get _tvMode => Pref.tvFocus;

  /// 焦点是不是在 OSD（顶部信息栏 / 底部控制条）里面。
  bool get _inOsd => TvRegions.hasFocus(TvLabels.playerOsd);

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
    TvRegions.registerAnchor(TvLabels.playerSurface, _node);
    TvMediaKeys.push(_mediaKeys);
  }

  @override
  void dispose() {
    TvRegions.unregisterAnchor(TvLabels.playerSurface, _node);
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

  /// 手柄模式的键位。返回 true 表示这个键已经被吃完，不用再走桌面键位表。
  ///
  /// 只有"焦点在画面上"这一种情况会走到这里：焦点进控制条之后，
  /// 方向键和确定键在 [build] 里就放行了。
  bool _handleTvKey(KeyEvent event) {
    // 返回：控制条亮着就先只收控制条，焦点回到画面
    if (TvKeys.isBack(event)) {
      if (_ctr.showControls.value) {
        if (TvKeys.isFirstPress(event)) {
          _ctr.controls = false;
          _node.requestFocus();
        }
        // 按下/重复/抬起都吃掉，免得抬起时又来一次返回
        return true;
      }
      return false;
    }

    // 遥控器确定 / 手柄 A：控制条亮着就进控制条，没亮就是播放暂停 + 亮起来。
    // 键盘回车/空格保持原来的桌面语义（跳过片头、发弹幕、播放暂停）。
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      if (TvKeys.isFirstPress(event)) {
        if (_ctr.showControls.value) {
          TvRegions.focusFirst(TvLabels.playerOsdBar);
        } else {
          _togglePlay();
          _ctr.controls = true;
        }
      }
      return true;
    }

    // 方向键：先亮控制条（按键有反馈），音量/快进这些原行为继续生效
    if (TvKeys.isDpad(event) && TvKeys.isPressOrRepeat(event)) {
      if (!_ctr.showControls.value) {
        _ctr.controls = true;
      }
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: true,
      // 手柄模式下画面不参与方向键寻焦：控制条关着的时候，
      // 方向键不应该落在这块"什么都没有"的画面区域上
      skipTraversal: _tvMode,
      onKeyEvent: (node, event) {
        if (_tvMode) {
          if (_inOsd) {
            // 焦点在控制条里：方向键/确定键/Tab 交回框架（控件间导航 + 确定）
            if (TvKeys.isDpad(event) ||
                TvKeys.isOk(event) ||
                event.logicalKey == LogicalKeyboardKey.tab) {
              return KeyEventResult.ignored;
            }
          } else if (_handleTvKey(event)) {
            return KeyEventResult.handled;
          }
        }
        final handled = _handleKey(context, event);
        if (handled || (!_tvMode && PlayerFocus._shouldHandle(event.logicalKey))) {
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
