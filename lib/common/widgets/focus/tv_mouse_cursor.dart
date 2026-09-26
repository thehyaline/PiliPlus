import 'dart:async';

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';

/// 应用级的鼠标自动隐藏：手柄/遥控器模式下，指针闲着就把光标藏起来。
///
/// 播放器里本来就有这一套（`PlPlayerController.playerCursor`：控制条收着就藏），
/// 但它只管画面那一块。10-foot 场景里鼠标是"用一下就不管了"的东西，
/// 停在首页、简介、设置页、弹层上一样碍事，所以同一件事在**整个应用**上再做一遍：
/// 指针闲置 [idle] 之后 `SystemMouseCursors.none`，之后任何一次指针动作
/// （移动 / 拖动 / 滚轮 / 按下）当场换回 [MouseCursor.defer]。
///
/// 两个前提，缺一个都不成立（挂哪儿见 `main.dart` 的 `_builder`）：
///
/// - **必须是命中路径上最靠前的那一层**。光标归谁由 `MouseTracker` 定：
///   `MouseCursorManager.handleDeviceCursorUpdate` 拿命中路径上各 `MouseRegion`
///   的光标当候选，`_DeferringMouseCursor.firstNonDeferred` **取第一个非 `defer`
///   的**，而候选是按命中顺序**从最前面往后**排的（`result.path` 的顺序）。
///   所以只有比控件更靠前的那一层说 `none` 才算数——挂在最外层
///   （`MaterialApp` 外面）反而是"排在最后"，任何一颗 `InkWell` 自带的
///   `click` 都能把 `none` 顶掉。
/// - **不吃事件**。`MouseRegion(opaque: false)` + `HitTestBehavior.translucent`：
///   这一层会进命中路径（悬停事件正是从这条路来的），但 `hitTest` 返回 false，
///   底下的控件照常收得到点击 / 拖动 / 滚轮。
///
/// 总开关关掉时原样返回 [SizedBox.shrink]：`Listener` / `MouseRegion` 一个都不建，
/// 命中路径和改动前完全一样。
class TvMouseCursor extends StatefulWidget {
  const TvMouseCursor({super.key});

  /// 指针闲着多久算"没人动"。
  ///
  /// 和播放器控制条共用一套时长（`Pref.enableLongShowControl`：3s / 30s），
  /// 不自己定一个：这一层在最上面，它说藏，播放器想要的 `defer` 也留不住光标，
  /// 两边各定各的就是"控制条还亮着、光标先没了"。
  static Duration get idle => Pref.enableLongShowControl
      ? const Duration(seconds: 30)
      : const Duration(seconds: 3);

  /// 手指不算"指针动作"：光标这个东西只跟着鼠标 / 触控板（含手写笔的悬停）走，
  /// 触摸屏上既没有光标可藏，滑动列表时也不需要每一次 move 都重新计时。
  static bool isCursorDevice(PointerDeviceKind kind) =>
      kind != PointerDeviceKind.touch;

  @override
  State<TvMouseCursor> createState() => _TvMouseCursorState();
}

class _TvMouseCursorState extends State<TvMouseCursor> {
  /// 起手就把时长定下来：重新计时是**每次指针动作**都要做的事，
  /// 而 `Pref` 每读一次都要过一次 Hive。
  late final Duration _idle = TvMouseCursor.idle;

  Timer? _timer;

  /// 光标现在是藏着的。起点是亮的——刚进应用，还没人动过鼠标。
  bool _hidden = false;

  /// 指针按着（拖动中）。
  ///
  /// 这期间不藏，和播放器"拖进度条时不收控制条"（`isSeeking`）同一条道理：
  /// 光标在自己正操作的东西底下消失，看着就是失灵。松手时重新计时。
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (Pref.tvFocus) _wake();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 指针动了：光标先回来，再重新计一次时。
  void _wake() {
    _timer?.cancel();
    if (_hidden) {
      setState(() => _hidden = false);
    }
    _timer = Timer(_idle, _sleep);
  }

  void _sleep() {
    _timer = null;
    if (!mounted || _hidden || _pressed) return;
    setState(() => _hidden = true);
  }

  void _onDown(PointerDownEvent event) {
    if (!TvMouseCursor.isCursorDevice(event.kind)) return;
    _pressed = true;
    _wake();
  }

  void _onRelease(PointerEvent event) {
    if (!TvMouseCursor.isCursorDevice(event.kind)) return;
    _pressed = false;
    _wake();
  }

  void _onMove(PointerEvent event) {
    if (!TvMouseCursor.isCursorDevice(event.kind)) return;
    _wake();
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return const SizedBox.shrink();
    return Listener(
      // 进命中路径但不吃事件：底下的控件照常收得到点击 / 拖动 / 滚轮
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onRelease,
      onPointerCancel: _onRelease,
      onPointerHover: _onMove,
      onPointerMove: _onMove,
      onPointerSignal: _onMove,
      child: MouseRegion(
        // 藏着就说 `none`；其余时候 `defer`——把光标让给底下的控件，
        // 播放器画面那一层、各处 `click` / `text` 全都照旧
        cursor: _hidden ? SystemMouseCursors.none : MouseCursor.defer,
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        child: const SizedBox.expand(),
      ),
    );
  }
}
