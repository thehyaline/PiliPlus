import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, KeyUpEvent, LogicalKeyboardKey;

/// 10-foot（手柄 / 遥控器 / 键盘）键位词表。
///
/// 页面里不要直接写 `LogicalKeyboardKey.xxx` 比较，统一走这里，
/// 这样以后换键位、加游戏手柄型号只需要改一个文件。
/// 键位与 Android scan code 的对应关系见 `docs/tv_focus.md`。
abstract final class TvKeys {
  /// 确定：手柄 A、遥控器确定(DPAD_CENTER)、键盘回车/空格。
  static final ok = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.space,
  };

  /// 确定但**不含空格**：手柄 A、遥控器确定(DPAD_CENTER)、键盘回车。
  ///
  /// 播放器里空格是"播放/暂停"，和"确定"是两件事（[ok] 里的空格只给
  /// `ActivateIntent` 那条路用），要自己接确定键的场景统一用这一份。
  static final confirm = <LogicalKeyboardKey>{
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
  };

  /// 返回：手柄 B、遥控器返回、键盘 Esc。
  /// （Android 的 KEYCODE_BACK 由系统直接 popRoute，不会到达框架）
  static final back = <LogicalKeyboardKey>{
    LogicalKeyboardKey.gameButtonB,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.gameButtonSelect,
  };

  /// 更多 / 上下文菜单：手柄 Y、遥控器菜单键、键盘上下文菜单键。
  static final more = <LogicalKeyboardKey>{
    LogicalKeyboardKey.gameButtonY,
    LogicalKeyboardKey.contextMenu,
    LogicalKeyboardKey.gameButtonStart,
  };

  static final dpad = <LogicalKeyboardKey>{
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  /// 上一栏 / 下一栏：手柄 L1/R1、键盘 `[` `]`。
  ///
  /// 故意不含 PageUp/PageDown：它们要留给框架默认的 `ScrollIntent`，
  /// 否则桌面端翻页会失效。
  static final prevSection = <LogicalKeyboardKey>{
    LogicalKeyboardKey.gameButtonLeft1,
    LogicalKeyboardKey.bracketLeft,
  };

  static final nextSection = <LogicalKeyboardKey>{
    LogicalKeyboardKey.gameButtonRight1,
    LogicalKeyboardKey.bracketRight,
  };

  /// 快退 / 快进：手柄 L2/R2。
  static final fastBackward = <LogicalKeyboardKey>{
    LogicalKeyboardKey.gameButtonLeft2,
    LogicalKeyboardKey.mediaRewind,
  };

  static final fastForward = <LogicalKeyboardKey>{
    LogicalKeyboardKey.gameButtonRight2,
    LogicalKeyboardKey.mediaFastForward,
  };

  /// 播放 / 暂停：手柄 Start、遥控器播放键、媒体键。
  static final playPause = <LogicalKeyboardKey>{
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.mediaPlay,
    LogicalKeyboardKey.mediaPause,
    LogicalKeyboardKey.mediaStop,
  };

  static final prevMedia = <LogicalKeyboardKey>{
    LogicalKeyboardKey.mediaTrackPrevious,
  };

  static final nextMedia = <LogicalKeyboardKey>{
    LogicalKeyboardKey.mediaTrackNext,
  };

  static bool isOk(KeyEvent event) => ok.contains(event.logicalKey);
  static bool isConfirm(KeyEvent event) =>
      confirm.contains(event.logicalKey);
  static bool isBack(KeyEvent event) => back.contains(event.logicalKey);
  static bool isMore(KeyEvent event) => more.contains(event.logicalKey);
  static bool isDpad(KeyEvent event) => dpad.contains(event.logicalKey);
  static bool isPrevSection(KeyEvent event) =>
      prevSection.contains(event.logicalKey);
  static bool isNextSection(KeyEvent event) =>
      nextSection.contains(event.logicalKey);

  /// 首次按下（排除系统按键重复）。
  ///
  /// 长按判定必须用这个：`KeyRepeatEvent` 是系统级重复，
  /// 用它判长按会在第一次重复时立刻触发，且手柄按钮通常不产生重复事件。
  static bool isFirstPress(KeyEvent event) => event is KeyDownEvent;

  static bool isPressOrRepeat(KeyEvent event) =>
      event is KeyDownEvent || event is KeyRepeatEvent;

  static bool isRelease(KeyEvent event) => event is KeyUpEvent;
}
