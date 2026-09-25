import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerDeviceKind,
        PointerDownEvent,
        PointerEvent;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent, KeyUpEvent;
import 'package:material_ui/material_ui.dart';

/// 输入源跟踪：把"这一下是按键还是鼠标"变成全局可查的一件事，
/// 并顺手把**鼠标点击**变成一次焦点移动。
///
/// 一共两件事：
///
/// 1. **输入源 → 高亮模式**。鼠标/触摸板按下 → [FocusHighlightStrategy.alwaysTouch]
///    （预选框立刻收起来），任何按键按下 → [FocusHighlightStrategy.alwaysTraditional]
///    （预选框立刻回来）。手柄 A/B、遥控器方向键都是 key event，所以键盘、手柄、
///    遥控器共用"按键"这一条。
/// 2. **鼠标点击 → 焦点跟着走**。按下时把焦点交给指针底下那个控件
///    （[TvRegions.focusAt]），于是"点一下再用方向键"是从点的地方继续。
///    触摸**不动焦点**：手指抬起后控件可能已经不在了，而且触屏用户没有方向键。
///
/// 为什么翻 [FocusManager.highlightStrategy] 而不是自建一套视觉开关：
/// [FocusRing] 的 `highlightEnabled` 和 Material 自带的 `InkWell.focusColor`
/// **都**读 `FocusManager.highlightMode`，一处改就全应用同步，两边的判定逻辑
/// 一行都不用动。
///
/// 为什么得我们自己来：Flutter 3.47 里 `_HighlightModeManager.handlePointerEvent`
/// 对 `mouse` / `trackpad` 是**空实现**（上游 PR #162417 有意为之，理由是"鼠标
/// 点击不该被当成触摸"），而 `InkWell` 这类控件点击时又从不 `requestFocus`。
/// 于是"鼠标点了不显示预选框、但焦点确实跟着走"这件鼠标用户默认期待的事，
/// 框架两半都没做。
///
/// 触摸那一半框架照做（`touch`/`stylus` 会切 `touch`），我们照做一遍不冲突：
/// 策略被我们钉住之后框架那半边就失效了，得由这里替它把触摸处理掉。
abstract final class TvInputMode {
  static bool _initialized = false;

  /// 我们上一次设进去的策略。只在真的变化时写，免得每次事件都白跑一遍
  /// `updateMode()`。
  static FocusHighlightStrategy? _applied;

  /// 最近一次交互是不是指针（鼠标 / 触摸板 / 手指）。
  static bool _pointer = false;

  /// 最近一次交互是否来自**按键**（键盘 / 手柄 / 遥控器）。
  ///
  /// 给"按键切页才把焦点送进新页面，鼠标点击不抢焦点"这类判断用
  /// （见 `main/view.dart` 的底栏）。
  static bool get fromKeys => !_pointer;

  /// 在 `main()` 里挂两个全局监听。要在 `WidgetsFlutterBinding` 之后调用。
  static void init() {
    if (_initialized) return;
    _initialized = true;
    // 挂在全局路由上（不是某个 `Listener`），所以不碰任何控件、也不吃事件
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    // 广播通道：焦点树之外的地方也能看到按键（按 primaryFocus 派发的 `onKeyEvent`
    // 只在焦点树里跑）。返回 false = 不消费。
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  /// 把高亮策略还给框架（手柄模式关掉时调，零侵入）。
  static void sync() {
    if (Pref.tvFocus) return;
    _applied = null;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  }

  static void _onPointer(PointerEvent event) {
    if (!Pref.tvFocus) {
      sync();
      return;
    }
    _pointer = true;
    if (event is! PointerDownEvent) return;
    _apply(FocusHighlightStrategy.alwaysTouch);
    switch (event.kind) {
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.trackpad:
        // 焦点落到指针底下那个控件上，键盘/手柄接着从这儿继续
        TvRegions.focusAt(event.position);
      case PointerDeviceKind.touch:
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.unknown:
        // 手指：不动焦点
        break;
    }
  }

  static bool _onKey(KeyEvent event) {
    if (!Pref.tvFocus) {
      sync();
      return false;
    }
    _pointer = false;
    // 按下和长按重复都算"在用按键"；抬起不算，免得松开手柄时把环收起来
    if (event is! KeyUpEvent) {
      _apply(FocusHighlightStrategy.alwaysTraditional);
    }
    return false;
  }

  static void _apply(FocusHighlightStrategy strategy) {
    if (_applied == strategy) return;
    _applied = strategy;
    FocusManager.instance.highlightStrategy = strategy;
  }
}
