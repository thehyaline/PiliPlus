import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        KeyUpEvent,
        LogicalKeyboardKey;

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

  /// 这一次按下已经被长按用掉了（`TvCard` 长按判定触发动作时标记）。
  ///
  /// 长按判定是在**按键还按着的时候**完成的（环满即触发），长按打开的菜单
  /// 这时才刚拿到焦点；而确定键在框架里同时还是 `ActivateIntent`
  /// （`WidgetsApp` 的 `_defaultShortcuts` 把 enter / space / gameButtonA /
  /// select 全映射成它，且默认连按键重复一起认），于是按着不动的确定键
  /// 继续送来的重复事件会被刚聚焦的菜单项当成"确定"按下去——长按一条动态
  /// 就直接执行了菜单第一项（图文=保存动态的截图面板、视频=稍后再看）。
  static void markPressConsumed() {
    _consumedPress = true;
    // 松手作废的清理挂在键盘层，而不是等按键派发到焦点树：没有 `TvShortcuts`
    // （纯触摸页面、widget 测试）或者事件没送到焦点树时，抬起也照样收得到，
    // 标记不会漏清——漏清的下一条确定会被白白吞掉一次。
    if (_watchingRelease) return;
    _watchingRelease = true;
    HardwareKeyboard.instance.addHandler(_handleRelease);
  }

  /// 抬起确定键就把这次按下作废；只旁观不吃键，永远返回 `false`。
  ///
  /// 同一颗静态方法的 tear-off 是同一个实例（`removeHandler` 要求
  /// [identical]），重复标记也不会把处理器加两遍。
  static bool _handleRelease(KeyEvent event) {
    if (!isRelease(event) || !isOk(event)) return false;
    _consumedPress = false;
    if (_watchingRelease) {
      _watchingRelease = false;
      HardwareKeyboard.instance.removeHandler(_handleRelease);
    }
    return false;
  }

  static bool _watchingRelease = false;

  /// 这次按键是不是属于"已经被长按用掉的那一次按下"——是就整条吃掉。
  ///
  /// 只认确定键：框架默认给它们挂了 `ActivateIntent`（[ok] 正好就是这个集合），
  /// 别的键（手柄 Y / 遥控器菜单键）没有这层默认行为。
  ///
  /// 判定不看时间，只看那个确定键**还按着没有**：按着就算同一次按下，松手
  /// （或者下一条事件到达时发现已经松手）就作废——不会把后面真正的按下吞掉，
  /// 也不会因为抬起事件没送到就永远卡住。
  ///
  /// 吃的是整段而不只是 `KeyRepeatEvent`：平台确实会为同一次按下送来不止一个
  /// `KeyDownEvent`（框架自己都为这种情况留了 `_logEventIfIrregular`，
  /// 见 flutter/flutter#125975），多出来的那一下到 `Shortcuts` 那里
  /// 一样会变成 `ActivateIntent`。
  static bool isConsumedPress(KeyEvent event) {
    if (!_consumedPress) return false;
    if (!ok.any(HardwareKeyboard.instance.isLogicalKeyPressed)) {
      _consumedPress = false;
      return false;
    }
    return isOk(event);
  }

  static bool _consumedPress = false;
}
