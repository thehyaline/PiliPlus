import 'dart:collection' show HashMap;

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
    this.hideRing = false,
    this.radius = TvFocusSpec.radius,
    this.scale = TvFocusSpec.scale,
    this.borderWidth = TvFocusSpec.borderWidth,
    this.circle = false,
    this.ringOnPrimaryFocus = false,
    this.fillColor,
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

  /// 有焦点也不画环（描边、缩放、底纹都不会出现）。
  ///
  /// 给"焦点停在这里只是个落脚点"用：播放器**全屏**时上下栏收起来之后焦点停在
  /// 画面上（那时候确定键是播放/暂停、方向键唤起上下栏），但画面不该被框起来——
  /// 全屏下它已经不是"一个整体焦点"了（见 `TvPlayerSurface`）。
  /// 想彻底不进焦点树用 [enabled] / [canRequestFocus]，不是这个。
  final bool hideRing;

  /// 只在**焦点自己**停在这个节点上时画环，焦点落在里面的子节点上时不画。
  ///
  /// 默认（false）用的是 `hasFocus`——焦点在子树里时祖先节点也算"有焦点"。
  /// 这对小控件是想要的（按钮和它内部的 `InkWell` 本来就是同一个节点），
  /// 但对"一大片容器"就成了同屏两个预选框：播放器画面那一层是整块视频，
  /// 焦点进到底部控制条之后它仍然 `hasFocus`，于是画面一圈、按钮一圈
  /// （见 `TvPlayerSurface`）。
  final bool ringOnPrimaryFocus;

  final BorderRadius radius;

  /// 聚焦时内容放大的倍数。
  ///
  /// 环画在控件边界**之内**，所以放大是"往外顶"：控件要是紧贴某个容器的裁剪
  /// 边（ `Clip.hardEdge` 的抽屉、列表视口），顶出去的那一点就会被切掉一条。
  /// 两种解法：在那个位置上留余量（`TabletNavItem` 的 `tilePadding`、抽屉头部
  /// 给头像留的那 4dp），或者这里传 1.0 不放大。
  final double scale;

  final double borderWidth;

  /// 把预选框画成**圆形**（内切于控件矩形）而不是圆角矩形。
  ///
  /// 播放器控件在手柄播放器模型下的规格（对齐电视端"圆形预选框"的手感）：
  /// 播放器按钮大多是 30~42 见方的小方块，圆角矩形看着像在框一个按钮，
  /// 圆形看着像在"Hover 这一颗"。此时 [radius] 不起作用。
  final bool circle;

  /// 聚焦时垫在内容**底下**的一层底色（预选框的"底纹"）。
  ///
  /// 和描边不同，它画在 [builder] 内容的下面：标签文字不会被染上颜色，
  /// 看着像这个格子亮了起来（blbl 的 `blbl_focus_bg_round.xml`）。
  /// 传一个低不透明度的主题色即可，例如 `TvTabBar`。
  final Color? fillColor;

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
      ..canRequestFocus = widget.canRequestFocus && widget.enabled;
    _applyKeyHandler(node, null);
    node.addListener(_handleFocusChange);
    TvFocusRings.add(node);
    FocusManager.instance.addListener(_syncRing);
    // 输入源一换（鼠标点一下 / 按一下手柄）就得立刻收放：只听 `FocusManager`
    // 的焦点变化是不够的，已经画着的环要等下一次焦点变化才消失，
    // 看着就是"鼠标点了环还在"。
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    _focused = _isFocused;
    _showRing = _wantRing && widget.enabled && FocusRing.highlightEnabled;
  }

  @override
  void didUpdateWidget(FocusRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      // 旧节点也要撤登记（这时 `_node` 已经是新节点了；`_internalNode` 只在
      // 旧 `focusNode` 为 null 时建过，所以它就是旧节点）
      final oldNode = oldWidget.focusNode ?? _internalNode;
      if (oldNode != null) TvFocusRings.remove(oldNode);
      _node.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
      TvFocusRings.add(_node);
      _focused = _isFocused;
    }
    _applyKeyHandler(_node, oldWidget.onKeyEvent);
    final canRequestFocus = widget.canRequestFocus && widget.enabled;
    if (_node.canRequestFocus != canRequestFocus) {
      _node.canRequestFocus = canRequestFocus;
      if (!canRequestFocus && _node.hasFocus) {
        _node.unfocus();
      }
    }
    _syncRing();
  }

  /// 只在**真的传了** [FocusRing.onKeyEvent] 时才动节点的按键处理。
  ///
  /// 节点不一定是我们的：`TvTabBar` 把 `InkWell` 自己的节点借给 [FocusRing]
  /// 用，调用方也可能递进来一个已经配好 `onKeyEvent` 的外部节点。`Focus` 的
  /// `onKeyEvent` getter 会回退去读节点上的值，所以写了 null 一般也不会立刻
  /// 出问题——但那是巧合。"不传"就该是"不动别人的"。
  void _applyKeyHandler(
    FocusNode node,
    KeyEventResult Function(FocusNode, KeyEvent)? old,
  ) {
    final handler = widget.onKeyEvent;
    if (handler != null) {
      node.onKeyEvent = handler;
    } else if (old != null) {
      // 我们先前挂过一个，现在撤掉
      node.onKeyEvent = null;
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncRing);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    final node = _internalNode ?? widget.focusNode;
    if (node != null) {
      node.removeListener(_handleFocusChange);
      TvFocusRings.remove(node);
    }
    // 只撤我们自己挂上去的那个，别动别人的（见 [_applyKeyHandler]）
    if (widget.onKeyEvent != null) node?.onKeyEvent = null;
    _internalNode?.dispose();
    super.dispose();
  }

  /// `highlightMode` 变了（按键 ↔ 鼠标）——不关心具体变成什么，重算一次就够。
  void _onHighlightMode(FocusHighlightMode mode) => _syncRing();

  void _handleFocusChange() {
    final focused = _isFocused;
    if (focused != _focused) {
      _focused = focused;
      widget.onFocusChange?.call(focused);
    }
    _syncRing();
  }

  /// 这个节点现在算不算"有焦点"——见 [FocusRing.ringOnPrimaryFocus]。
  ///
  /// 焦点在子树里移动时 `hasFocus` 不变，所以 [FocusManager] 的监听
  /// （[_syncRing]）是必须的：`hasPrimaryFocus` 会在那里被重新求值。
  bool get _isFocused =>
      widget.ringOnPrimaryFocus ? _node.hasPrimaryFocus : _node.hasFocus;

  bool get _wantRing =>
      !widget.hideRing && (_isFocused || widget.showRing);

  void _syncRing() {
    final showRing = _wantRing && widget.enabled && FocusRing.highlightEnabled;
    if (showRing == _showRing || !mounted) return;
    setState(() => _showRing = showRing);
  }

  /// 焦点框的形状——`shape` 和 `borderRadius` 互斥，圆形的圆角交给内切圆去算。
  BoxDecoration _decoration({Color? color, Border? border}) => BoxDecoration(
    shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: widget.circle ? null : widget.radius,
    color: color,
    border: border,
  );

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
          // 底纹垫在内容下面，所以标签文字不会被染色
          if (widget.fillColor case final fill?)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: TvFocusSpec.duration,
                  curve: Curves.easeOut,
                  decoration: _decoration(color: _showRing ? fill : null),
                ),
              ),
            ),
          widget.builder(context, _node, _showRing),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: TvFocusSpec.duration,
                curve: Curves.easeOut,
                decoration: _decoration(
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

/// 给"本身就是圆的"控件加**圆形**预选框（头像 / 消息 / 搜索这类圆按钮，
/// 见 `docs/tv_focus.md` 的「主界面导航栏」）。圆角矩形那一档直接用 [FocusRing]。
///
/// [builder] 收到的是 [FocusRing] 持有的那一个节点，交给内部的可聚焦控件
/// （`InkWell` / `IconButton` 都接受 `focusNode`）。`Pref.tvFocus` 关掉时把
/// `null` 直接递进去、**[FocusRing] 也不建**——准则 6「默认零侵入」，节点一个不多。
///
/// 这些按钮是共享控件（`userAvatar` / `msgBadge` / 侧栏的搜索按钮同时出现在
/// 手机顶栏、平板抽屉、「我的」页头部），环加在这里四处就一致了。
///
/// 放大（1.04 倍）照旧：它是焦点框的通用逻辑，这几颗和别的控件一样会弹一下。
/// 代价是环会顶出控件边界 4%，所以**紧贴容器裁剪边的位置得留余量**——平板抽屉
/// 里头像就在抽屉最上沿，`_sideBar()` 的头部因此留了 4dp（见
/// `docs/tv_focus.md` 的「主界面导航栏（平板抽屉）」）。
Widget circularFocusRing({
  required String debugLabel,
  required Widget Function(FocusNode? focusNode) builder,
}) {
  if (!Pref.tvFocus) return builder(null);
  return FocusRing(
    debugLabel: debugLabel,
    circle: true,
    builder: (_, focusNode, _) => builder(focusNode),
  );
}

/// 给**自己内部造 `ListTile`** 的控件套焦点环（`RadioListTile`、
/// `CheckboxListTile`、`OrderedCheckboxListTile`——设置页里那一堆单选/多选行）。
///
/// 这类控件只有 `focusNode` 一个口子，没有 `focusColor`：节点递进去之后，框架
/// 自带的那层 `focusColor` 底纹照样会画，和焦点环叠成两层（普通 `ListTile` 靠
/// `focusColor: Colors.transparent` 压掉，见 `popup_item.dart`）。所以这里顺手
/// 改一下 `Theme.focusColor` —— 视觉统一交给 [FocusRing]。
///
/// [builder] 收到的是 [FocusRing] 持有的那一个节点；`Pref.tvFocus` 关掉时把
/// `null` 递进去、环也不套（准则 6「默认零侵入」）。
Widget listTileFocusRing({
  required String debugLabel,
  required Widget Function(FocusNode? focusNode) builder,
}) {
  if (!Pref.tvFocus) return builder(null);
  return FocusRing(
    debugLabel: debugLabel,
    builder: (context, focusNode, _) => Theme(
      data: Theme.of(context).copyWith(focusColor: Colors.transparent),
      child: builder(focusNode),
    ),
  );
}

/// "这个焦点节点自己会画环"的登记处。
///
/// [FocusRing] 建出来的时候把自己的节点登记进来、销毁时撤掉，
/// `TvFocusOverlay`（全局兜底环）靠它决定"要不要让位"——不让位的话焦点停在
/// 卡片上会里外两个框。
///
/// 判定用的是 `hasFocus` 的语义：焦点落在**子树里**时祖先节点也算"有环"
/// （`TvNavDestination` / `TvTextField` 那类"外壳画环、落点在里面"的控件正是
/// 靠这一条工作的），所以只登记外层那一个节点就够。
///
/// 不挂 `Pref.tvFocus`：开关是**画不画**的事（两边都读
/// [FocusRing.highlightEnabled]），登记本身一个字节都不影响行为。
abstract final class TvFocusRings {
  /// 节点 → 登记次数：同一个节点可能被两层 [FocusRing] 借用（见
  /// [FocusRing.builder] 的用法），撤一次不算撤。
  static final Map<FocusNode, int> _counts = HashMap<FocusNode, int>.identity();

  static void add(FocusNode node) =>
      _counts.update(node, (count) => count + 1, ifAbsent: () => 1);

  static void remove(FocusNode node) {
    final count = _counts[node];
    if (count == null) return;
    if (count > 1) {
      _counts[node] = count - 1;
    } else {
      _counts.remove(node);
    }
  }

  /// [node] 自己或者它的某个祖先是不是已经有环了。
  static bool covers(FocusNode? node) {
    if (node == null || _counts.isEmpty) return false;
    if (_counts.containsKey(node)) return true;
    for (final ancestor in node.ancestors) {
      if (_counts.containsKey(ancestor)) return true;
    }
    return false;
  }
}
