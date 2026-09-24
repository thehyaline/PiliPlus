import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/common/widgets/focus/hold_progress.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart' show KeyEvent, KeyDownEvent, KeyUpEvent;
import 'package:material_ui/material_ui.dart';

/// 卡片 / 列表项 = **一个** 焦点节点。
///
/// 这是「焦点简化」的落点：卡片内部的小按钮（点赞、更多、时长角标……）
/// 应该用 [ExcludeFocus] 包起来，让方向键永远只在卡片之间跳，
/// 而不是陷进卡片里。
///
/// 同时它也是「长按确定」的落点。关键机制：
/// 手柄 A / 遥控器确定 在框架里走的是
/// `Shortcuts`(enter→ActivateIntent) → `Actions.invoke(primaryFocus.context)`
/// → `InkWell` 这条链，而 `FocusManager` 派发按键时是
/// **从 `primaryFocus` 沿祖先链向上** 调 `onKeyEvent` 的
/// （`focus_manager.dart` 的 `_handleKeyEvent`）。
/// 也就是说：只要在**卡片自己的焦点节点**上拦截确定键并返回
/// `KeyEventResult.handled`，事件就不会继续传到 `Shortcuts`，
/// `InkWell` 自然也收不到 `ActivateIntent`——长按判定因此得以实现。
///
/// 只有真的配了 [onMore] / [onLongPress] 时才拦截；普通按钮不拦截，
/// 直接走框架默认行为（按下即触发，还带水波纹）。
class TvCard extends StatefulWidget {
  const TvCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onMore,
    this.onHold,
    this.onSecondaryTap,
    this.onKeyEvent,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.enabled = true,
    this.radius = TvFocusSpec.radius,
    this.scale = TvFocusSpec.scale,
    this.holdDuration = TvFocusSpec.longPressDuration,
    this.focusNode,
    this.surface,
    this.debugLabel = 'TvCard',
  });

  final Widget child;

  /// 按一下确定（或点击）触发。
  final VoidCallback? onTap;

  /// 触摸长按。手柄长按请看 [onMore] / [onHold]。
  final VoidCallback? onLongPress;

  /// 长按确定 / 手柄 Y 键 / 遥控器菜单键触发，用来打开「更多」。
  final VoidCallback? onMore;

  /// 长按确定的动作，不传就用 [onMore]。
  /// 受「长按确定打开更多」设置开关控制（关掉后长按=短按）。
  final VoidCallback? onHold;

  final VoidCallback? onSecondaryTap;

  /// 卡片自己的按键钩子，跑在长按判定之前；返回 handled 可完全接管。
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  final bool autofocus;
  final bool canRequestFocus;
  final bool enabled;
  final BorderRadius radius;
  final double scale;
  final Duration holdDuration;
  final FocusNode? focusNode;
  final String debugLabel;

  /// 卡片外表的构造器（`Card(child: ...)`、`Material(type: .transparency, ...)`
  /// ……）。它必须包在 [TvCard] 的 `InkWell` **外面**：水波纹是画在祖先
  /// `Material` 上的，如果卡片外表在 `InkWell` 里面
  /// （`InkWell > Card > 内容`），水波纹会被卡片自己的背景整个盖住，
  /// 触摸就没有点击反馈了。默认一层透明 `Material`——水波纹落在页面背景上，
  /// 不额外画卡片背景。
  final Widget Function(Widget child)? surface;

  @override
  State<TvCard> createState() => _TvCardState();
}

class _TvCardState extends State<TvCard> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: widget.holdDuration,
  )..addStatusListener(_handleHoldStatus);

  bool _holding = false;
  bool _fired = false;

  /// 手柄 Y / 遥控器菜单键：任何时候都可用
  VoidCallback? get _moreAction => widget.onMore ?? widget.onLongPress;

  /// 长按确定：受设置开关控制，关掉后确定键完全交还给框架（长按=短按）
  VoidCallback? get _holdAction =>
      Pref.tvLongPressOk ? (widget.onHold ?? _moreAction) : null;

  static void _noop() {}

  /// `InkWell` 自己决定能不能聚焦：`_canRequestFocus = enabled && canRequestFocus`，
  /// 而 `enabled` 只看它有没有手势回调（`isWidgetEnabled`）。所以只配了
  /// [onMore] / [onHold] 这种"按键专用"动作的卡片会被判定为不可用，
  /// 连同手柄焦点一起废掉——补个空 onTap 兜住。全无动作的卡片则保持不可聚焦
  /// （纯展示用，不该被方向键选中）。
  VoidCallback? get _effectiveOnTap =>
      widget.onTap ??
      (widget.onMore != null || widget.onHold != null ? _noop : null);

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _handleHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_holding) return;
    _fired = true;
    final action = _holdAction;
    // 环停在满格，同时把动作抛出去；`_fired` 让随后的抬起不再算点击
    if (mounted) setState(() {});
    action?.call();
  }

  void _startHold() {
    _holding = true;
    _fired = false;
    setState(() {});
    _hold.forward(from: 0);
  }

  void _finishHold({required bool tap}) {
    if (!_holding) return;
    final fired = _fired;
    _holding = false;
    _fired = false;
    _hold.reset();
    if (mounted) setState(() {});
    if (tap && !fired) widget.onTap?.call();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKeyEvent;
    if (custom != null) {
      final result = custom(node, event);
      if (result != KeyEventResult.ignored) return result;
    }
    if (!widget.enabled) return KeyEventResult.ignored;

    if (TvKeys.isMore(event)) {
      final action = _moreAction;
      if (action == null) return KeyEventResult.ignored;
      if (TvKeys.isFirstPress(event)) action();
      return KeyEventResult.handled;
    }

    if (!TvKeys.isOk(event)) return KeyEventResult.ignored;

    // 没有长按动作就别抢键，交给框架默认的 ActivateIntent，反馈更即时
    if (_holdAction == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      // 系统按键重复不算新的一次按下
      if (!_holding) _startHold();
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _finishHold(tap: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  Widget? _buildOverlay() {
    if (!_holding || _holdAction == null) return null;
    return AnimatedBuilder(
      animation: _hold,
      builder: (_, _) =>
          HoldProgressRing(progress: _hold.value, radius: widget.radius),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.surface ?? _transparentSurface;
    if (!Pref.tvFocus) {
      return surface(
        InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          borderRadius: widget.radius,
          child: widget.child,
        ),
      );
    }
    return FocusRing(
      focusNode: widget.focusNode,
      canRequestFocus: widget.canRequestFocus,
      enabled: widget.enabled,
      radius: widget.radius,
      scale: widget.scale,
      debugLabel: widget.debugLabel,
      onKeyEvent: _handleKey,
      onFocusChange: (focused) {
        // 焦点被抢走时作废这次长按，避免"松手后跳页"
        if (!focused) _finishHold(tap: false);
      },
      overlay: _buildOverlay(),
      builder: (context, node, _) => surface(
        InkWell(
          focusNode: node,
          autofocus: widget.autofocus,
          canRequestFocus: widget.canRequestFocus,
          onTap: _effectiveOnTap,
          onLongPress: widget.onLongPress,
          onSecondaryTap: widget.onSecondaryTap,
          borderRadius: widget.radius,
          // 焦点视觉由 FocusRing 负责，关掉 Material 自带的 focus 高亮
          focusColor: Colors.transparent,
          child: widget.child,
        ),
      ),
    );
  }
}

Widget _transparentSurface(Widget child) =>
    Material(type: .transparency, child: child);

/// 带 M3 卡片外表的 [TvCard.surface]：`Card` 自带的 4dp 外边距正好当卡片间距，
/// 所以这里不动它（焦点框画在整格边界上，和 blbl 的 stroke 一样留一圈余量）。
Widget tvCardSurface(Widget child) => Card(child: child);

/// 卡片 / 弹层里不该被方向键选中的子控件（点赞、更多、时长角标、底弹层的拖拽把手……）。
///
/// 只是 [ExcludeFocus] 的一层语义包装，写起来更清楚：
/// `TvCardSubAction(child: ...)` 一眼能看出"这是次要操作，方向键不该停在这儿"。
/// 触摸、鼠标行为都不受影响，关掉手柄模式时连焦点也照旧。
class TvCardSubAction extends StatelessWidget {
  const TvCardSubAction({
    super.key,
    required this.child,
    this.excluding = true,
  });

  final Widget child;
  final bool excluding;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    // 关掉手柄模式时别动原来的焦点行为（Tab 还是能摸到卡内按钮）
    excluding: excluding && Pref.tvFocus,
    child: child,
  );
}
