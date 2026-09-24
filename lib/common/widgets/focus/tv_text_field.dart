import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent;
import 'package:material_ui/material_ui.dart';

/// 手柄 / 遥控器上的输入框：**两段式焦点**。
///
/// 直接把 `TextField` 交给手柄是不行的：它一拿到焦点就弹键盘，方向键也被它
/// 吃掉变成"移光标"，于是输入框这一格"进得去出不来"——按方向键不动、按返回
/// 退回上一步、按确定只能换行/提交。所以这里把焦点拆成两层：
///
/// - **导航态**：外面这层节点拿着焦点（画焦点环），键盘不弹，方向键照常进出这一格；
///   按确定（手柄 A / 遥控器确定）才把焦点交给下面的输入框——"按 A 才能输入"。
/// - **编辑态**：输入框自己的节点拿着焦点，软键盘弹起来，按键都进输入框；
///   按返回键（B / Esc）把焦点交回导航态：键盘收起、焦点环还在这一格上，
///   再按确定可以接着改——这就是"脱出逻辑"，退出编辑态不会顺手退出页面。
///
/// 用法（别自己再给里面的 `TextField` 传 `focusNode:`，用 [builder] 给的 [FocusNode]）：
///
/// ```dart
/// TvTextField(
///   builder: (context, node) => TextField(focusNode: node, ...),
/// )
/// ```
///
/// 触摸行为完全不变：点一下输入框，框架自己就会把焦点给输入框（直接进编辑态，
/// 键盘照样弹）。关掉「手柄/遥控器模式」时整层消失，退回原来的 `TextField`。
class TvTextField extends StatefulWidget {
  const TvTextField({
    super.key,
    required this.builder,
    this.editFocusNode,
    this.navFocusNode,
    this.enabled = true,
    this.autofocus = false,
    this.radius = TvFocusSpec.radius,
    this.debugLabel = 'TvTextField',
  });

  /// 输入框本体。用 [FocusNode] 当它的 `focusNode`。
  final Widget Function(BuildContext context, FocusNode node) builder;

  /// 输入框自己的焦点节点；不传则内部创建。
  /// 调用方已经有节点（比如控制器持有的 `searchFocusNode`）时传进来，
  /// 那样 `requestFocus()` / `unfocus()` 这些老代码照旧能用。
  final FocusNode? editFocusNode;

  /// 导航态的焦点节点；不传则内部创建。
  final FocusNode? navFocusNode;

  final bool enabled;

  /// 进页面就把**导航态**焦点放在输入框上（要按确定才能输入）。
  ///
  /// 只想让方向键有个落点、不希望自动弹键盘的页面上用它。
  final bool autofocus;

  final BorderRadius radius;
  final String debugLabel;

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  FocusNode? _internalNavNode;
  FocusNode? _internalEditNode;

  FocusNode get _navNode => widget.navFocusNode ?? _internalNavNode!;
  FocusNode get _editNode => widget.editFocusNode ?? _internalEditNode!;

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.navFocusNode == null) {
      _internalNavNode = FocusNode(debugLabel: widget.debugLabel);
    }
    if (widget.editFocusNode == null) {
      _internalEditNode = FocusNode(debugLabel: '${widget.debugLabel}.edit');
    }
    // 输入框自己不参与遍历：方向键在这一格上应该是"路过"，不是"进去"
    // （编辑态下也无所谓，那时按键都归输入框）
    _editNode.skipTraversal = true;
    _editNode.addListener(_handleEditFocus);
    _editing = _editNode.hasFocus;
  }

  @override
  void dispose() {
    _editNode.removeListener(_handleEditFocus);
    _internalNavNode?.dispose();
    _internalEditNode?.dispose();
    super.dispose();
  }

  /// 焦点进/出输入框时同步状态。
  ///
  /// 触摸也能走到这里——点一下输入框，框架直接把焦点给了输入框，
  /// 那就算进了编辑态（键盘该弹就弹）。
  void _handleEditFocus() {
    final editing = _editNode.hasFocus;
    if (editing == _editing) return;
    setState(() => _editing = editing);
  }

  void _enterEdit() {
    if (_editing) return;
    _editNode.requestFocus();
    // 焦点变化是在帧末统一应用的，这里先自己切状态：焦点环要立刻稳住
    setState(() => _editing = true);
  }

  void _exitEdit() {
    _editNode.unfocus();
    _navNode.requestFocus();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;

    if (_editing) {
      // 编辑态只抢返回键（脱出用），其余按键全部交给输入框自己
      if (TvKeys.isBack(event)) {
        if (TvKeys.isFirstPress(event)) _exitEdit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (TvKeys.isOk(event)) {
      // 按下/重复/抬起都吃掉：漏出去就会变成框架的一次 ActivateIntent
      if (TvKeys.isFirstPress(event)) _enterEdit();
      return KeyEventResult.handled;
    }

    // 直接敲字（硬件键盘）：自动进编辑态。
    // 这一下字符会丢——输入法连接刚要建立——但"抬手指就能打字"比
    // "少按一次确定、代价是吃掉一个字"更合理。
    // 控制字符（Tab、Esc、方向键在部分平台会带字符）不算敲字。
    final char = event.character;
    if (event is KeyDownEvent &&
        char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 0x20) {
      _enterEdit();
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) {
      return widget.builder(context, _editNode);
    }
    return FocusRing(
      focusNode: _navNode,
      enabled: widget.enabled,
      // 进了编辑态焦点在输入框自己身上，但这一格仍然是"当前目标"
      showRing: _editing,
      radius: widget.radius,
      debugLabel: widget.debugLabel,
      onKeyEvent: _handleKey,
      builder: (context, node, _) => Focus(
        focusNode: node,
        autofocus: widget.autofocus,
        debugLabel: '${widget.debugLabel}.nav',
        child: widget.builder(context, _editNode),
      ),
    );
  }
}
