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
  /// **放大只允许发生在控件自己的矩形里**（见 [_buildContent]）：内容照原尺寸
  /// 布局，聚焦时整体放大这个倍数、再按控件自己的形状（[radius] / [circle]）
  /// 裁一刀，顶出去的那部分不画。环（描边 / [fillColor] / [overlay]）画在控件
  /// 边界上、**不跟着放大**，于是"预选框"恒等于控件自己的矩形。
  ///
  /// 这一条是"预选框永远看得见"的全部保证：环再也不出控件边界，就不会被邻卡
  /// 邻行盖住（后画的一律压在前画的上面）、被 `AppBar` 底边压住、被列表视口 /
  /// 抽屉 / `SingleChildScrollView` 的裁剪线削掉，也不会被屏幕边切掉。
  ///
  /// 比例缩放最难受的是**宽/高的大控件**：1.04 倍 = 每边顶出控件尺寸的 2%，
  /// 一条 1000 逻辑像素宽的评论卡左右各顶出去 20px——两条竖描边整个跑到屏幕
  /// 外面，看着就是"预选框被挡住了"（用户报的就是这个）。放大收进控件里之后
  /// 这类位置一律正常，代价只是那 20px 的放大被裁掉：有内边距的卡片看着仍是
  /// "整块弹一下"（溢出本来就落在内边距里），贴边的图/背景则变成"框不动、
  /// 里面的内容放大"。
  ///
  /// 传 1.0 = 完全不放大（连 `AnimatedScale` 都不建）。**不是**"留余量就别传"——
  /// 余量那套规则（`TabletNavItem` 的 `tilePadding`、抽屉头部给头像留的 4dp）
  /// 已经不需要了，留在那儿只是布局上的留白。
  ///
  /// 设置里那个「焦点放大效果」关着时（[Pref.tvFocusScale] 默认关），这里传什么
  /// 都按 1.0 走：焦点位置只由环表达，内容一个像素都不动（见 [_scale]）。
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

  /// 登记进 [TvFocusRings] 时用的 `coversSubtree`——撤登记要对上号
  /// （见 [TvFocusRings.add] 和 [_coversSubtree]）。
  late bool _registeredCoversSubtree;

  FocusNode get _node => widget.focusNode ?? _internalNode!;

  /// 这一圈环会不会在"焦点落在子树里"时亮着——判断的依据是"环什么时候画"：
  /// 只有 `hasFocus` 那一档才是"子树里有焦点就亮"，另外两档（[FocusRing.hideRing]
  /// 根本不画、[FocusRing.ringOnPrimaryFocus] 只在焦点停在自己身上时画）
  /// 替子树里的焦点出不了预选框。
  bool get _coversSubtree => !(widget.hideRing || widget.ringOnPrimaryFocus);

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
    _registeredCoversSubtree = _coversSubtree;
    TvFocusRings.add(node, coversSubtree: _registeredCoversSubtree);
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
      if (oldNode != null) {
        TvFocusRings.remove(oldNode, coversSubtree: _registeredCoversSubtree);
      }
      _node.removeListener(_handleFocusChange);
      widget.focusNode?.addListener(_handleFocusChange);
      _registeredCoversSubtree = _coversSubtree;
      TvFocusRings.add(_node, coversSubtree: _registeredCoversSubtree);
      _focused = _isFocused;
    } else if (_coversSubtree != _registeredCoversSubtree) {
      // 同一个节点，但这一圈环"画法"变了（`TvPlayerSurface` 全屏时
      // `hideRing: true` 就是这么切的）：登记也跟着换一边
      TvFocusRings.remove(_node, coversSubtree: _registeredCoversSubtree);
      _registeredCoversSubtree = _coversSubtree;
      TvFocusRings.add(_node, coversSubtree: _registeredCoversSubtree);
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
      TvFocusRings.remove(node, coversSubtree: _registeredCoversSubtree);
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

  /// 这一层实际用的放大倍数。
  ///
  /// 「焦点放大效果」（[Pref.tvFocusScale]）默认**关**，关着一律按 1.0 走：
  /// 于是 [_buildContent] 连 `AnimatedScale` 都不建，焦点进出只有描边/底纹在动。
  /// 开关的位置在设置 → 外观 → 手柄 / 遥控器，它只改视觉、不动焦点行为。
  double get _scale => Pref.tvFocusScale ? widget.scale : 1.0;

  /// 焦点在自己身上时，这一圈环会不会是"整个视图那么大"。
  ///
  /// 这是**绘制**层的最后一道闸（见 [TvFocusSpec.coversWholeView]）：
  /// 结构性规则（[_coversSubtree] / `TvFocusRings.covers`）管的是"环会不会替
  /// 子树里的焦点亮着"，而"落脚点自己有整页那么大"要靠这里挡——进页面/切布局
  /// 的头一两帧、焦点被路由入口按在"页面那一层"上时，照着整页描一圈就是
  /// 用户看到的"窗口大小的预选框闪一下"。
  bool get _wholeViewVeto {
    final context = _node.context;
    if (context == null) return false;
    final object = context.findRenderObject();
    if (object == null || !object.attached) return false;
    // 视口一律走 [TvFocusSpec.viewSizeOf]：那个算式带着界面缩放
    // （`View.devicePixelRatio` 是引擎报的原始值，uiScale 一开就永远对不上）
    final viewSize = TvFocusSpec.viewSizeOf(context);
    return viewSize != null && TvFocusSpec.coversWholeView(_node.rect, viewSize);
  }

  void _syncRing() {
    // 命中一票否决时，缩放（`AnimatedScale`）和底纹也要一起收掉：
    // 它们画在整个 `Stack` 上，只拦描边的话还是会"整页弹一下"
    final veto = _wholeViewVeto;
    final viewSize = _viewSizeOf();
    if (veto && _wantRing) {
      TvFocusSpec.reportWholeViewRing(widget.debugLabel, _node.rect, viewSize);
    }
    final showRing =
        !veto && _wantRing && widget.enabled && FocusRing.highlightEnabled;
    if (showRing == _showRing || !mounted) return;
    // 画得出来、可又大得可疑（比视口小一圈那种），报一行是谁：一票否决管不到
    // 这一档，而这种框十有八九是落点选错了（见 [TvFocusSpec.nearWholeView]）
    if (showRing &&
        TvFocusSpec.nearWholeView(_node.rect, viewSize)) {
      TvFocusSpec.reportNearWholeViewRing(
        widget.debugLabel,
        _node.rect,
        viewSize,
      );
    }
    setState(() => _showRing = showRing);
  }

  /// 只给上报日志用；拿不到视图就退回 `Size.zero`。
  Size _viewSizeOf() => TvFocusSpec.viewSizeOf(_node.context) ?? Size.zero;

  /// 描边/底纹的公共外壳：这里的约束是**紧的**（`Positioned.fill` 给的就是
  /// 这一圈环的真实大小），所以量出来的尺寸和画出去的那一圈完全一致——
  /// 比 [_syncRing] 读节点矩形更准，而且布局一变就会重新判一次。
  Widget _paintIfFits(Widget Function() decoration) {
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            // 视口算法只有一处（[TvFocusSpec.viewSizeOf]）：界面缩放开着时
            // 它和 `View.devicePixelRatio` 那个老算式不是一回事（见那边的说明）
            final viewSize = TvFocusSpec.viewSizeOf(context);
            if (viewSize != null && size.isFinite) {
              if (_lastLayoutSize != size) {
                _lastLayoutSize = size;
                _scheduleRecheck();
              }
              if (TvFocusSpec.coversWholeView(Offset.zero & size, viewSize)) {
                return const SizedBox.shrink();
              }
            }
            return decoration();
          },
        ),
      ),
    );
  }

  /// 上一次布局量到的这一层大小（[_paintIfFits] 里比对这个就知道"布局变没变"）。
  Size? _lastLayoutSize;

  bool _recheckScheduled = false;

  /// 排一帧 post-frame 的复检。
  ///
  /// 绘制那一层（[_paintIfFits]）是布局驱动的，当帧就对；可缩放（`AnimatedScale`）
  /// 和 [_showRing] 是**状态**，只有焦点/高亮模式变化才会重算——尺寸变了却没有
  /// 这两个事件时，它们就停在旧判定上。进页面、切全屏、切布局正好都是这样：
  /// 头一两帧节点还是"整页那么大"，等布局量准了却没人通知我们，
  /// 于是整页的环/缩放已经画出去了才在下一帧收掉——用户看到的就是"闪一下"。
  ///
  /// 只在**这一层真的重新布局过**时才排，所以收敛：复检不改变状态就不会再排。
  void _scheduleRecheck() {
    if (_recheckScheduled || !mounted) return;
    _recheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckScheduled = false;
      if (mounted) _syncRing();
    });
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
    return Stack(
      clipBehavior: Clip.none,
      // 约束原样透传：焦点环不该改变内容的尺寸行为
      // （`loose` 会把紧约束放宽，调用方靠 `Expanded`/`SizedBox` 撑开的宽度就没了）
      fit: StackFit.passthrough,
      children: [
        // 底纹垫在内容下面，所以标签文字不会被染色
        if (widget.fillColor case final fill?)
          _paintIfFits(
            () => AnimatedContainer(
              duration: TvFocusSpec.duration,
              curve: Curves.easeOut,
              decoration: _decoration(color: _showRing ? fill : null),
            ),
          ),
        _buildContent(context),
        _paintIfFits(
          () => AnimatedContainer(
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
        if (widget.overlay case final overlay?)
          Positioned.fill(child: IgnorePointer(child: overlay)),
      ],
    );
  }

  /// 内容层——整个 [FocusRing] 里**唯一**会缩放的层，而且放大只在自己的矩形内。
  ///
  /// 缩放和环是分开的两件事：
  ///
  /// - 环（描边 / 底纹 / [FocusRing.overlay]）画在控件边界上，**不缩放**；
  /// - 内容按 [FocusRing.scale] 放大，超出控件矩形的部分由这里裁掉。
  ///
  /// 所以"预选框"永远等于控件自己的矩形：既不会被后画的邻卡邻行盖住，也不会
  /// 被祖先的裁剪线（`AppBar` 底边、列表视口、抽屉、屏幕边）切掉——详情见
  /// [FocusRing.scale]。
  ///
  /// **树形结构不跟着焦点变**：焦点进出只改 `AnimatedScale.scale` 和
  /// `clipBehavior` 两个参数，包的还是同一个 widget。本来只在聚焦时才套裁剪
  /// 更省，但那样等于在焦点变化时换掉内容上面那一层的类型——`Element` 认类型
  /// （`Widget.canUpdate`），换掉就把整棵子树重建一遍：`InkWell` 自己那个
  /// `FocusNode`、滚动位置这些内部状态全丢，焦点当场掉到最近的 scope 上
  /// （`PopupMenuButton` 这种"外壳画环、落点在里面"的控件就是这么被踩到的）。
  ///
  /// `scale: 1.0` 的控件连 `AnimatedScale` 都不建，和改动前一个字节不差
  /// （准则 6「默认零侵入」）——这条只看控件自己的配置，不随焦点变。
  Widget _buildContent(BuildContext context) {
    final content = widget.builder(context, _node, _showRing);
    final scale = _scale;
    if (scale == 1.0) return content;
    final scaled = AnimatedScale(
      scale: _showRing ? scale : 1.0,
      duration: TvFocusSpec.duration,
      curve: Curves.easeOut,
      child: content,
    );
    // 不聚焦时 `Clip.none`：内容本来就在框里，不用裁（也不会建裁剪层）
    final clipBehavior = _showRing ? Clip.hardEdge : Clip.none;
    // 裁成控件自己的形状：和环（描边）同一套圆角，贴边的图/背景放大了之后
    // 看着仍是"这一格的形状"，而不是被切出一个方角
    return widget.circle
        ? ClipOval(clipBehavior: clipBehavior, child: scaled)
        : ClipRRect(
            clipBehavior: clipBehavior,
            borderRadius: widget.radius,
            child: scaled,
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
/// 不过放大现在只发生在**控件自己的矩形里**（见 [FocusRing.scale]），所以
/// "紧贴容器裁剪边要留余量"这条老规矩在这里也不用守了——平板抽屉里头像就在
/// 抽屉最上沿，环也不会被抽屉的 `Clip.hardEdge` 削掉（`_sideBar()` 头部那 4dp
/// 留着只是留白，见 `docs/tv_focus.md` 的「主界面导航栏（平板抽屉）」）。
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
///
/// [onKeyEvent] 透传给 [FocusRing]，用来在**节点这一层**接管按键：这一层比
/// `RadioGroup` 内部那套 `Shortcuts.manager` 更深，先收到键，所以拦得住它
/// （见 `tvRadioTile`）。[focusNode] 同理透传，给"节点在别处"的场景用。
Widget listTileFocusRing({
  required String debugLabel,
  required Widget Function(FocusNode? focusNode) builder,
  KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent,
  FocusNode? focusNode,
}) {
  if (!Pref.tvFocus) return builder(null);
  return FocusRing(
    debugLabel: debugLabel,
    focusNode: focusNode,
    onKeyEvent: onKeyEvent,
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
/// 靠这一条工作的），所以只登记外层那一个节点就够。**但**只有"焦点落在子树里
/// 时这一圈环照样亮着"的才算——[FocusRing.hideRing] /
/// [FocusRing.ringOnPrimaryFocus] 这两种只有焦点正好停在自己身上才画
/// （或者根本不画），替子树里的焦点出不了预选框：让位让出去就是一个框都没有。
/// 这类登记成 `coversSubtree: false`（见 [add]）。
///
/// 不挂 `Pref.tvFocus`：开关是**画不画**的事（两边都读
/// [FocusRing.highlightEnabled]），登记本身一个字节都不影响行为。
abstract final class TvFocusRings {
  /// 节点 → 登记次数：同一个节点可能被两层 [FocusRing] 借用（见
  /// [FocusRing.builder] 的用法），撤一次不算撤。这一份管"焦点停在**它自己**
  /// 身上时算不算有环"。
  static final Map<FocusNode, int> _counts = HashMap<FocusNode, int>.identity();

  /// 同上，但只收 [add] 里 `coversSubtree: true` 的那些：环会替**子树里**的
  /// 焦点亮着，所以祖先里有一个就够，兜底环一路让位。
  static final Map<FocusNode, int> _subtreeCounts =
      HashMap<FocusNode, int>.identity();

  /// [markLanding] 记过的落脚点。单开一份账是因为它要能单独问
  /// （[isLanding]）：`TvRegions.focusAt` 得把"落脚点"和"控件"分开。
  static final Map<FocusNode, int> _landingCounts =
      HashMap<FocusNode, int>.identity();

  /// [coversSubtree] 见类注释：这一圈环会不会在"焦点落在子树里"时亮着。
  static void add(FocusNode node, {bool coversSubtree = true}) {
    _bump(_counts, node);
    if (coversSubtree) _bump(_subtreeCounts, node);
  }

  static void remove(FocusNode node, {bool coversSubtree = true}) {
    _drop(_counts, node);
    if (coversSubtree) _drop(_subtreeCounts, node);
  }

  /// 登记一个**落脚点**：焦点会（短暂地）停在它身上，但它不是控件——
  /// 这一层自己不出预选框，兜底层也别照着它画。
  ///
  /// 和 [FocusRing] 那两档的区别是"谁画的"：`hideRing` / `ringOnPrimaryFocus`
  /// 是"这个环先不画"，落脚点是"这里根本没有环这件事"。用到的有
  /// `TvSelectionArea`（整块只读文本，只借它的节点把方向键摘出遍历）、
  /// `PlayerFocus`（整页那一层，见那边的 `FocusRing(hideRing: true)`）。
  static void markLanding(FocusNode node) {
    add(node, coversSubtree: false);
    _bump(_landingCounts, node);
  }

  static void unmarkLanding(FocusNode node) {
    remove(node, coversSubtree: false);
    _drop(_landingCounts, node);
  }

  /// [node] 是不是 [markLanding] 登记过的落脚点。
  ///
  /// 给 `TvRegions.focusAt` 用：鼠标点在"整页大小"的落脚点上（播放器那一层、
  /// 只读正文）是**设计好的**——点画面聚焦、点正文进去选字——不该被
  /// "整页大小的不接点击"那条规则挡掉。所以这里得能把"落脚点"和"普通控件"
  /// 分开问，光用 [covers] 分不出来（每个 [FocusRing] 的节点也都在那份账上）。
  static bool isLanding(FocusNode node) => _landingCounts.containsKey(node);

  static void _bump(Map<FocusNode, int> map, FocusNode node) =>
      map.update(node, (count) => count + 1, ifAbsent: () => 1);

  static void _drop(Map<FocusNode, int> map, FocusNode node) {
    final count = map[node];
    if (count == null) return;
    if (count > 1) {
      map[node] = count - 1;
    } else {
      map.remove(node);
    }
  }

  /// [node] 自己或者它的某个祖先是不是已经有环了。
  static bool covers(FocusNode? node) {
    if (node == null) return false;
    if (_counts.containsKey(node)) return true;
    if (_subtreeCounts.isEmpty) return false;
    for (final ancestor in node.ancestors) {
      if (_subtreeCounts.containsKey(ancestor)) return true;
    }
    return false;
  }
}
