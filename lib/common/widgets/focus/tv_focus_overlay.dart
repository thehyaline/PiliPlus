import 'dart:math' as math;

import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 焦点环的**兜底层**：没自己画环的控件，焦点停上去时在这里补一个框。
///
/// [FocusRing] 是"谁用谁画"，而框架自己造的那些控件外面包不进去——`AppBar`
/// 自动生成的返回键、`CloseButton`、任何一处裸的 `IconButton` / `PopupMenuItem`、
/// 还没换成 `TvTabBar` 的 `TabBar`……焦点停上去只剩框架那层几乎看不见的
/// `focusColor` 底纹（`onSurfaceVariant` 10% 灰），手柄上看着就是"没有预选框"。
/// 逐处去包一遍是不可能包全的（框架在 `AppBar` 里新建返回键的地方根本没有扩展点），
/// 所以这一层挂在 `MaterialApp.builder` 上（`Navigator` 之上、路由和弹层之上），
/// 每帧看一眼 `FocusManager.primaryFocus`，给**没有环**的落点补框。
///
/// 三条边界：
///
/// - **已经有环的不画**：[FocusRing] 建出来时把自己的节点登记进 [TvFocusRings]，
///   兜底环见到就直接让位——卡片那套 1.04 倍缩放、底纹、圆角全是它自己的事，
///   这里再框一圈就成了两个框。登记用的是 `hasFocus` 的语义（焦点落在子树里
///   祖先也算有环），所以 `TvNavDestination` / `TvTextField` 那种"外壳画环、
///   落点在里面"的控件也照让不误。
/// - **看不见的不画**：先过 [TvRegions.isPainted]（`Offstage`、还没布局的），
///   再和祖先里所有**会裁剪**的盒子求交——列表滚过之后预选框不会画到视口外面去。
/// - **零侵入**：关掉「手柄/遥控器模式」、或者这一下是鼠标/触摸来的，一个字都不画，
///   判定直接读 [FocusRing.highlightEnabled]（和 [FocusRing] 同一个口子）。
///
/// 形状：方方正正的小控件（图标按钮、头像）画成**圆**，和 `FocusRing(circle: true)`
/// 那一档同一套视觉；其余按圆角矩形来。描边宽度和圆角取 [TvFocusSpec]。
///
/// 和 [FocusRing] 的唯一差别是**不缩放**：控件不是我们的子树，缩不了。对这几类
/// 控件本来也看不出来——它们的 `Material` 背景是透明的，`FocusRing` 那时缩的
/// 其实只有图标本身（4% 的 24dp 图标 = 1dp）。
class TvFocusOverlay extends StatefulWidget {
  const TvFocusOverlay({super.key});

  /// 正在画的那一圈的 key（测试靠它量环的位置）。
  static const ringKey = ValueKey('tv-focus-overlay-ring');

  /// 超过这个尺寸的方控件不再当"一颗按钮"看（内切圆会让描边整圈离开控件边界）。
  static const circularMaxSize = 64.0;

  /// 方方正正的小控件（图标按钮、头像）画成圆；其余圆角矩形。
  ///
  /// 阈值就是"内切圆还贴着控件边界"的范围：再大方框和内切圆之间就空出一大圈，
  /// 看着不像这颗按钮的框了。
  static bool isCircular(Rect rect) =>
      (rect.width - rect.height).abs() < 1 &&
      rect.shortestSide <= circularMaxSize;

  @override
  State<TvFocusOverlay> createState() => _TvFocusOverlayState();
}

class _TvFocusOverlayState extends State<TvFocusOverlay> {
  /// 这一帧该画的环（全局坐标）；null = 什么都不画。
  Rect? _rect;
  bool _circle = false;

  /// 跟帧采样的开关。
  ///
  /// 环的位置会随着滚动/动画动，只看"焦点变了没"是不够的；但又不能自己去请求帧
  /// （播放器、列表动画都在出帧，凭空多一路 60fps 的循环不值）。所以用
  /// `addPostFrameCallback` 搭便车——它**不会**产生新帧，只在已经有帧时插一脚；
  /// 没有环要画时就把这条链收掉。
  bool _sampling = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_sync);
    // 输入源一换（鼠标点一下 / 按一下手柄）就得重算：已经画着的那圈要当帧收起来
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
    _sampling = true;
    WidgetsBinding.instance.addPostFrameCallback(_tick);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_sync);
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    _sampling = false;
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode mode) => _sync();

  void _sync() {
    if (!mounted) return;
    final target = _target();
    if (target == null) {
      // 没有落点要画（焦点浮在 scope 上 / 已经有环 / 看不见 / 指针输入）：链到此为止
      _sampling = false;
      if (_rect != null) {
        setState(() {
          _rect = null;
          _circle = false;
        });
      }
      return;
    }
    if (!_sampling) {
      _sampling = true;
      WidgetsBinding.instance.addPostFrameCallback(_tick);
    }
    if (target.$1 != _rect || target.$2 != _circle) {
      setState(() {
        _rect = target.$1;
        _circle = target.$2;
      });
    }
  }

  /// 跟下一帧（[_sync] 里会按需把自己接回这条链）。
  void _tick(Duration _) {
    if (!mounted) {
      _sampling = false;
      return;
    }
    _sync();
    if (_sampling && mounted) {
      WidgetsBinding.instance.addPostFrameCallback(_tick);
    }
  }

  /// 这一帧该给谁画环：`(矩形, 是不是圆)`，没有合适的落点返回 null。
  (Rect, bool)? _target() {
    if (!FocusRing.highlightEnabled) return null;
    final focus = FocusManager.instance.primaryFocus;
    // 焦点浮在某个 scope（路由 / 区域 / 弹层）上时不属于任何控件。那几种状态
    // 各有各的接管者（`TvRouteFocusObserver` / `TvFocusMemory` / `TvFocusReturn`），
    // 这里画一圈"整个 scope"的框只会让人以为焦点还活着。
    if (focus == null || focus is FocusScopeNode) return null;
    // 自己会画环的（FocusRing / TvCard / TvButton / TvTabBar / TvTextField…）不插手
    if (TvFocusRings.covers(focus)) return null;
    if (!TvRegions.isPainted(focus)) return null;
    final rect = _visibleRect(focus);
    if (rect == null || rect.width <= 0 || rect.height <= 0) return null;
    return (rect, TvFocusOverlay.isCircular(rect));
  }

  /// 焦点控件的**可见**矩形（全局坐标）：控件自己的矩形，和祖先里所有会裁剪的
  /// 盒子自己的矩形求交。
  ///
  /// `describeApproximatePaintClip` 是框架给"这个祖辈会不会裁掉子节点"的官方口子
  /// （`RenderViewportBase` / `RenderClip*` / `RenderSingleChildViewport` /
  /// `RenderStack` / `RenderFlex` 都实现了），它给的裁剪框就在**它自己**的坐标系里
  /// （见 SDK `RenderObject.describeApproximatePaintClip` 的说明），所以拿它自己的
  /// 变换送到全局再交。不交这一下的话，列表滚过之后（焦点还停在那张卡上、卡已经
  /// 出了视口）预选框会画在 AppBar 或者相邻区域上。
  ///
  /// 框架原话是"approximate"：`ClipOval` 这类给回来的还是整块 `Offset.zero & size`，
  /// 所以这一层只保证不画到**确定**看不见的地方去，不保证裁得一丝不差。
  static Rect? _visibleRect(FocusNode node) {
    final object = node.context?.findRenderObject();
    if (object is! RenderBox || !object.attached) return null;
    var rect = node.rect;
    RenderObject? child = object;
    for (
      RenderObject? parent = object.parent;
      parent != null;
      parent = parent.parent
    ) {
      final clip = parent.describeApproximatePaintClip(child!);
      if (clip != null) {
        rect = rect.intersect(_globalRect(parent, clip));
        if (rect.isEmpty) return null;
      }
      child = parent;
    }
    return rect;
  }

  static Rect _globalRect(RenderObject object, Rect rect) =>
      MatrixUtils.transformRect(object.getTransformTo(null), rect);

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (rect != null)
          Positioned.fromRect(
            key: TvFocusOverlay.ringKey,
            rect: rect,
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FocusRingPainter(
                  color: ColorScheme.of(context).primary,
                  borderWidth: TvFocusSpec.borderWidth,
                  circle: _circle,
                  radius: math.min(
                    TvFocusSpec.radius.topLeft.x,
                    rect.shortestSide / 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  const _FocusRingPainter({
    required this.color,
    required this.borderWidth,
    required this.circle,
    required this.radius,
  });

  final Color color;
  final double borderWidth;
  final bool circle;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..color = color;
    // 描边压在控件边界**内侧**：和 `FocusRing` 的 `Positioned.fill` + `Border.all`
    // 落在同一圈上（`strokeAlign` 默认 inside）
    final rect = (Offset.zero & size).deflate(borderWidth / 2);
    if (circle) {
      canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.circle != circle ||
      oldDelegate.radius != radius;
}
