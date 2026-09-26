import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_back.dart';
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
///   按返回键（B / Esc / 安卓与遥控器返回键）把焦点交回导航态：键盘收起、
///   焦点环还在这一格上，再按确定可以接着改——这就是"脱出逻辑"，
///   退出编辑态不会顺手退出页面。
///
/// "返回键先脱出"这一条要同时盖住三条路（它们不在焦点树里汇合，见
/// `docs/tv_focus.md` 的「返回键：一套语义」）：手柄 B 走焦点树的
/// `onKeyEvent`、桌面 Esc 走 `TvBack` 拦截栈（它在焦点树**之前**）、
/// 安卓 / 遥控器返回键走路由的 `popDisposition`（`PopScope`）。
/// 三条都只做一件事：把焦点交回外层，然后接着走各自原来的逻辑。
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
    TvBack.remove(_handleBack);
    _editNode.removeListener(_handleEditFocus);
    _internalNavNode?.dispose();
    _internalEditNode?.dispose();
    super.dispose();
  }

  /// 这一格现在是不是"两段式焦点"：总开关开着、控件也可用。
  ///
  /// 关掉「手柄/遥控器模式」（或者控件是禁用态）时一个指头都不许伸出去，
  /// 返回键的行为退回改动前。
  bool get _navMode => Pref.tvFocus && widget.enabled;

  /// 编辑态要拦住返回键（见 [_handleBack]）。
  bool get _blockBack => _editing && _navMode;

  /// 焦点进/出输入框时同步状态。
  ///
  /// 触摸也能走到这里——点一下输入框，框架直接把焦点给了输入框，
  /// 那就算进了编辑态（键盘该弹就弹）。
  void _handleEditFocus() => _setEditing(_editNode.hasFocus);

  /// 进出编辑态的唯一入口：状态、返回键拦截、重建一起换。
  void _setEditing(bool editing) {
    if (editing == _editing) return;
    // 拦返回键要在**焦点已经在输入框里**的时候挂上；摘掉则不挑条件，
    // 免得开关中途变过、或者焦点被别处抢走时留下一个吃键的处理函数。
    if (editing && _navMode) {
      TvBack.push(_handleBack);
    } else {
      TvBack.remove(_handleBack);
    }
    setState(() => _editing = editing);
  }

  void _enterEdit() {
    if (_editing) return;
    _editNode.requestFocus();
    // 焦点变化是在帧末统一应用的，这里先自己切状态：焦点环要立刻稳住
    _setEditing(true);
  }

  void _exitEdit() {
    _editNode.unfocus();
    _navNode.requestFocus();
  }

  /// 编辑态下的返回键：**先脱离输入状态，这一下到此为止**。
  ///
  /// 桌面 Esc 走 `TvBack` 拦截栈（`main.dart` 的 early handler 跑在焦点树
  /// 之前，所以 `onKeyEvent` 抢不到它），安卓 / 遥控器返回键走 `PopScope`
  /// 那一层（它经路由的 `popDisposition`）。手柄 B 则是 [_handleKey] 直接接。
  /// 三条路都在这里汇合，语义只有一条：退出编辑态不等于退出页面。
  bool _handleBack() {
    if (!_blockBack) return false;
    if (!_editNode.hasFocus) {
      // 焦点已经不在输入框里了（触摸点到别处、被别的控件抢走），
      // 状态跟着修正，但这一下返回不归我们接手。
      _setEditing(false);
      return false;
    }
    _exitEdit();
    return true;
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
    return PopScope(
      // 编辑态里返回键先"脱出输入框"，再按一次才是真的返回（见 [_handleBack]）
      canPop: !_blockBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleBack();
      },
      child: FocusRing(
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
      ),
    );
  }
}
