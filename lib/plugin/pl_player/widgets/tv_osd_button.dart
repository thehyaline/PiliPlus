import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// 播放器上栏那一排的按钮：`IconButton` + 播放器规格的**圆形**预选框。
///
/// 上栏原来是一排裸的 `IconButton`。兜底环（`TvFocusOverlay`）本来能兜住它们，
/// 但兜底环画的是"圆角矩形 + 默认描边"，而紧挨着的返回键、下栏的 `ComBtn`
/// 全是圆形 + 1.1 倍缩放 + `playerBorderWidth`——一排里两种框看着就是没做完。
/// 所以这里自己套一圈，规格和 `TvButton` 对齐。
///
/// 不用 `ComBtn`：上栏这几颗要的是 `IconButton` 自己的水波纹、hover 和禁用态
/// （`ComBtn` 里面是 `GestureDetector`，只接"确定键 = 点击"）。直播页上栏反过来，
/// 那边从头到尾都是 `ComBtn`，不掺这一味。
///
/// 焦点节点还是 `IconButton` 自己那一个（`FocusRing.builder` 把节点递进去），
/// 一个按钮仍然只是一个落点。关掉「手柄/遥控器模式」时环都不套，
/// 原样返回 [IconButton]（准则 6「默认零侵入」）。
class TvOsdIconButton extends StatelessWidget {
  const TvOsdIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.width = 42,
    this.height = 34,
    this.debugLabel,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;

  /// 格子的尺寸，默认上栏那一排的 42×34（下栏的图标按钮走 `ComBtn`，35×30）。
  ///
  /// 预选框画的就是这个格子——所以"文字按钮的框看着小一圈"这类问题，
  /// 根子都在容器尺寸上，见 [TvOsdPopupButton]。
  final double width;
  final double height;

  /// 调试名；不给就用 [tooltip]（测试里按它找节点）。
  final String? debugLabel;

  static const _style = ButtonStyle(padding: WidgetStatePropertyAll(.zero));

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) {
      return SizedBox(
        width: width,
        height: height,
        child: IconButton(
          tooltip: tooltip,
          style: _style,
          icon: icon,
          onPressed: onPressed,
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: FocusRing(
        debugLabel: debugLabel ?? tooltip,
        radius: TvFocusSpec.playerRadius,
        borderWidth: TvFocusSpec.playerBorderWidth,
        scale: TvFocusSpec.playerScale,
        circle: true,
        // 没有点击行为的按钮不进焦点树（和 `TvButton` 同一条）
        canRequestFocus: onPressed != null,
        builder: (context, focusNode, focused) => IconButton(
          focusNode: focusNode,
          tooltip: tooltip,
          style: _style,
          icon: icon,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// 播放器上下栏里的下拉按钮（画质 / 倍速 / 超分辨率 / 翻译 / 字幕）。
///
/// 单独包一层的唯一原因：**`PopupMenuButton` 不暴露 `focusNode`**——里面那个
/// `InkWell` 自己建节点，外面拿不到，环就没法跟着落点走。所以这里用
/// "外壳 + 落点"的写法：外壳的节点**不进遍历**（`canRequestFocus: false`），
/// 只当预选框的画布；焦点其实停在里面的 `InkWell` 上，外壳因为
/// `FocusNode.hasFocus` 含后代而"有焦点"，环跟着亮，同时也把兜底环挡掉
/// （登记走的是同一套 `hasFocus` 语义，见 [TvFocusRings]）。
///
/// 两种用法，对应 OSD 里本来就有的两档控件：
///
/// - [TvOsdPopupButton.capsule]：**文字**按钮（画质 / 倍速 / 超分辨率）。
///   容器定高 30，和 `ComBtn` 的图标按钮一样——文字按钮原来只有一行字那么高
///   （13 号字 ≈ 18），预选框照着画出来就小一圈，还容易和邻座看成两行。
///   形状用**胶囊**：它比图标按钮宽，圆形会切着字走，胶囊（圆角 = 高度的一半）
///   才是"文字按钮版的圆"。
/// - [TvOsdPopupButton.circle]：**图标**按钮（翻译 / 字幕）。尺寸由里面那颗
///   自己定（`SizedBox(width: 35, height: 30)` 之类），环走**内切圆**，
///   和 `ComBtn` 一模一样。
///
/// 关掉「手柄/遥控器模式」时环都不套（准则 6「默认零侵入」）；定高那一步在
/// 两种模式下都做——它是"容器高度对齐"，不是手柄专属的视觉。
class TvOsdPopupButton extends StatelessWidget {
  /// 文字按钮：定高 30 + 胶囊预选框。
  const TvOsdPopupButton.capsule({
    super.key,
    required this.child,
    required this.debugLabel,
  }) : _height = 30,
       _circle = false;

  /// 图标按钮：尺寸由里面那颗自己定 + 圆形预选框。
  const TvOsdPopupButton.circle({
    super.key,
    required this.child,
    required this.debugLabel,
  }) : _height = null,
       _circle = true;

  /// 里面那颗 `PopupMenuButton`。
  final Widget child;

  /// 调试名（测试里按它找节点）。
  final String debugLabel;

  final double? _height;
  final bool _circle;

  /// 胶囊的圆角：高度的一半（30 → 15）。
  static const _capsuleRadius = BorderRadius.all(Radius.circular(15));

  @override
  Widget build(BuildContext context) {
    final height = _height;
    var content = child;
    if (height != null) {
      // `widthFactor: 1` 是必须的：`Center` 在横向会把 `Row` 里剩下的宽度全吃掉
      // （那样整条下栏都会被这一格顶开），加上它才是"刚好包住文字、上下居中"
      content = SizedBox(
        height: height,
        child: Center(widthFactor: 1, child: child),
      );
    }
    if (!Pref.tvFocus) return content;
    return FocusRing(
      debugLabel: debugLabel,
      radius: _capsuleRadius,
      circle: _circle,
      borderWidth: TvFocusSpec.playerBorderWidth,
      scale: TvFocusSpec.playerScale,
      // 落点是里面那颗，外壳自己不是——见类注释
      canRequestFocus: false,
      builder: (context, focusNode, focused) => Focus(
        focusNode: focusNode,
        canRequestFocus: false,
        debugLabel: '$debugLabel.shell',
        child: content,
      ),
    );
  }
}
