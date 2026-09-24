import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 给任意可聚焦控件加统一的焦点视觉（缩放 + 描边）。
///
/// 自己持有 [FocusNode]，用 `builder` 把它交给内部的可聚焦控件
/// （`InkWell` / `IconButton` / `ListTile` 都接受 `focusNode` 参数），
/// 这样整棵子树只有一个焦点节点。
///
/// 焦点框只在**按键输入**之后出现：直接读 `FocusManager.highlightMode`，
/// 触摸设备上永远看不到（等价于 blbl 的 `isInTouchMode` 判断）。
///
/// 描边画在控件**自己的边界内**（`Positioned.fill` + `Border.all`），
/// 所以不会被视口裁切，也不存在和邻卡的 z 序问题。
///
/// 这个组件本身不改变焦点行为（节点还是内部控件那一个），所以可以放心地
/// 用在共享控件里（`iconButton` / `ToolbarIconButton` 就都包了一层）；
/// 真正的"TV 专属行为"都挂在 `Pref.tvFocus` 上，环也一样。
class FocusRing extends StatefulWidget {
  const FocusRing({
    super.key,
    required this.builder,
    this.focusNode,
    this.canRequestFocus = true,
    this.enabled = true,
    this.showRing = false,
    this.radius = TvFocusSpec.radius,
    this.scale = TvFocusSpec.scale,
    this.borderWidth = TvFocusSpec.borderWidth,
    this.overlay,
    this.onKeyEvent,
    this.onFocusChange,
    this.debugLabel = 'FocusRing',
  });

  /// 把焦点节点交给内部可聚焦控件。
  ///
  /// [focused] 是按键高亮是否应该显示（已综合考虑焦点与输入类型），
  /// 需要自己做视觉时用它；只是想加焦点环的话用 [FocusRing] 自带的即可。
  /// `autofocus` 也要在这里传给内部控件，[FocusRing] 自己不管自动聚焦。
  final Widget Function(BuildContext context, FocusNode focusNode, bool focused)
  builder;

  /// 外部焦点节点；不传则内部创建。
  final FocusNode? focusNode;
  final bool canRequestFocus;
  final bool enabled;

  /// 即使 [focusNode] 没有焦点也画出焦点环。
  ///
  /// 给"焦点在内部子节点上"的场景用：输入框进了编辑态之后焦点在
  /// `EditableText` 自己的节点上，但视觉上这一格仍然是当前目标
  /// （见 `TvTextField`）。
  final bool showRing;

  final BorderRadius radius;
  final double scale;
  final double borderWidth;

  /// 聚焦时叠在内容之上的额外绘制层（例如长按进度环）。
  final Widget? overlay;

  /// 焦点节点上的按键拦截。
  ///
  /// 这里返回 [KeyEventResult.handled] 会**阻止**按键继续向上派发，
  /// 也就是说可以拦住 `Shortcuts` → `InkWell` 的 `ActivateIntent`，
  /// 从而实现"长按确定"这类自定义语义。
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  final ValueChanged<bool>? onFocusChange;
  final String debugLabel;

  /// 当前是否应该画出焦点环——要同时满足三个条件：控件有焦点、
  /// 输入来自按键（触摸时不画）、手柄模式开着（关掉就完全退回改动前）。
  static bool get highlightEnabled =>
      Pref.tvFocus &&
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  FocusNode? _internalNode;
  bool _focused = false;
  bool _showRing = false;

  FocusNode get _node => widget.focusNode ?? _internalNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalNode = FocusNode(debugLabel: widget.debugLabel);
    }
    final node = _node
      ..canRequestFocus = widget.canRequestFocus && widget.enabled
      ..onKeyEvent = widget.onKeyEvent
      ..addListener(_handleFocusChange);
    FocusManager.instance.addListener(_syncRing);
    _focused = node.hasFocus;
    _showRing = _wantRing && widget.enabled && FocusRing.highlightEnabled;
  }

  @override
  void didUpdateWidget(FocusRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      _node.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
      _focused = _node.hasFocus;
    }
    _node.onKeyEvent = widget.onKeyEvent;
    final canRequestFocus = widget.canRequestFocus && widget.enabled;
    if (_node.canRequestFocus != canRequestFocus) {
      _node.canRequestFocus = canRequestFocus;
      if (!canRequestFocus && _node.hasFocus) {
        _node.unfocus();
      }
    }
    _syncRing();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncRing);
    (_internalNode ?? widget.focusNode)
      ?..removeListener(_handleFocusChange)
      ..onKeyEvent = null;
    _internalNode?.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    final focused = _node.hasFocus;
    if (focused != _focused) {
      _focused = focused;
      widget.onFocusChange?.call(focused);
    }
    _syncRing();
  }

  bool get _wantRing => _focused || widget.showRing;

  void _syncRing() {
    final showRing = _wantRing && widget.enabled && FocusRing.highlightEnabled;
    if (showRing == _showRing || !mounted) return;
    setState(() => _showRing = showRing);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return AnimatedScale(
      scale: _showRing ? widget.scale : 1.0,
      duration: TvFocusSpec.duration,
      curve: Curves.easeOut,
      child: Stack(
        clipBehavior: Clip.none,
        // 约束原样透传：焦点环不该改变内容的尺寸行为
        // （`loose` 会把紧约束放宽，调用方靠 `Expanded`/`SizedBox` 撑开的宽度就没了）
        fit: StackFit.passthrough,
        children: [
          widget.builder(context, _node, _showRing),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: TvFocusSpec.duration,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: widget.radius,
                  border: Border.all(
                    width: widget.borderWidth,
                    color: _showRing ? colorScheme.primary : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
          if (widget.overlay case final overlay?)
            Positioned.fill(child: IgnorePointer(child: overlay)),
        ],
      ),
    );
  }
}
