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

  /// 自**上一次换页**以来，用户用手动过没有（按过键、点/触过屏幕）。
  ///
  /// 只读它一件事、只有一个读者：[TvPlayerSurface] 的"入口焦点要不要接手"
  /// （见那里的 `_claimFocus`）。视频页 / 直播页的画面是等详情、等流地址之后
  /// 才建出来的，比路由入口那一下晚得多——那时焦点已经落在简介区第一项或者
  /// 内容区第一张卡上，画面这一层要是只认"悬空"这一种情况就再也接不过来，
  /// 用户看到的是"进了视频页，预选框停在简介上"。
  ///
  /// 没动过手 = 现在这个落点不是用户挑的，画面可以接手（**只抢这一次**：
  /// 动过一下就不再抢，用户后面走到哪儿是哪儿，包括他自己退回来那一下）。
  ///
  /// 置位在 [init] 挂的那两个全局钩子里（按键按下、指针按下）；
  /// **换页清零**交给 [TvRouteFocusObserver]——只有它知道"一页"从哪儿算起。
  /// 注意按下/抬起要分开：进这一页的那颗确定键，它的**抬起**是在 push 之后
  /// 才派发的，跟着抬起置位的话，每次进页面都会立刻把这次机会用掉。
  static bool get userActedSinceEntry => _userActed;

  static void noteUserInput() => _userActed = true;

  static void resetUserInput() => _userActed = false;

  static bool _userActed = false;

  /// 撤掉两个全局钩子、把内部状态复位，好让下一次 [init] 重新挂一遍。
  ///
  /// **只在测试里用。** `flutter_test` 每个用例收尾都会
  /// `HardwareKeyboard.instance.clearState()`（框架那边写着"为了让用例互相隔离"），
  /// 而那一下会把**所有**按键处理器连锅端掉；[init] 的幂等闸又拦着不让重挂。
  /// 结果就是"挂一次只对紧随其后的那一个用例有效"，后面用例里的按键事件全是哑的
  /// ——预设的输入源、`fromKeys` 的判定统统不动，测试却在别处"碰巧"通过。
  /// 测试文件的全局 `setUp` 里 `reset()` 一遍（这套宿主默认不挂钩子），要测输入源
  /// 本身的组再自己 `setUp(TvInputMode.init)`（见 `docs/tv_focus.md` 的
  /// 「写测试时的几个坑」）。
  ///
  /// 生产上不需要：那两个钩子在 `main()` 里挂一次，是进程级的东西，没人清它。
  @visibleForTesting
  static void reset() {
    // 没挂过就什么都别撤：`removeGlobalRoute` 对没登记过的路由是断言失败
    if (_initialized) {
      _initialized = false;
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    _applied = null;
    _pointer = false;
    _userActed = false;
    _playerPages = 0;
  }

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
  ///
  /// 播放页（视频页 / 直播页）里例外：总开关关掉时那两页**全程不出现预选框**
  /// （连 Material 自带的焦点高亮一起），见 [pushPlayerPage]。
  static void sync() {
    if (Pref.tvFocus) return;
    if (_playerPages > 0) {
      _forceTouch();
      return;
    }
    _applied = null;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  }

  /// 压在栈上的"播放页"数量（视频页 + 直播页；全屏是同一棵树，自动算在里面）。
  static int _playerPages = 0;

  /// 进视频页 / 直播页时压栈。
  ///
  /// 总开关**关掉**时，这两页的预选框要彻底消失：方向键在那儿是音量/进度，
  /// 焦点环除了闪人没有别的用处。压栈期间强制 [FocusHighlightStrategy.alwaysTouch]，
  /// 并且按键不再把它切回 `traditional`（[sync] 会一直把它按回去），
  /// 于是按键、鼠标、触摸都唤不出环。
  ///
  /// 总开关**打开**时这个计数不参与：那两页的预选框是正常功能，照常出现。
  /// 计数不是为了嵌套页面，而是为了"页面还没退干净就又进来一个"时别提前解压。
  static void pushPlayerPage() {
    _playerPages++;
    sync();
  }

  static void popPlayerPage() {
    if (_playerPages > 0) _playerPages--;
    sync();
  }

  /// 强制"预选框收起来"（策略被我们钉住之后，框架那半边就不管用了，
  /// 得由我们替它把触摸/指针那一路处理掉）。
  static void _forceTouch() => _apply(FocusHighlightStrategy.alwaysTouch);

  static void _onPointer(PointerEvent event) {
    if (!Pref.tvFocus) {
      sync();
      return;
    }
    _pointer = true;
    if (event is! PointerDownEvent) return;
    noteUserInput();
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
    // 按下和长按重复都算"在用按键"；抬起不算，免得松开手柄时把环收起来，
    // 也免得"进这一页那颗确定键的抬起"白占掉一次画面接手的机会
    if (event is! KeyUpEvent) {
      noteUserInput();
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
