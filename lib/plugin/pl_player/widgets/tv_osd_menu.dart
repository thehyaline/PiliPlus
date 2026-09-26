import 'dart:ui' show SemanticsRole;

import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';

/// OSD 上的**单选菜单**：视频页的倍速 / 画质 / 字幕 / 超分辨率 / 翻译，
/// 直播页的画质，都是它。
///
/// ## 一处一套外观
///
/// 用法是 [tvOsdSelectMenu]（建那颗 `PopupMenuButton`）+ [TvOsdMenuItem]（建每一行），
/// 外面照旧套 `TvOsdPopupButton`（那颗按钮的预选框，见 `tv_osd_button.dart`）。
///
/// 为什么要自己画行，而不是直接用 `PopupMenuItem`——两处和播放器里其它控件对不上：
///
/// - **当前值那道底纹是直角的**：`_PopupMenuState` 把 `initialValue` 命中的那一项
///   包一层 `ColoredBox(Theme.highlightColor)`。手柄停在某一项上时画的却是
///   [TvFocusSpec.radius]（12）的圆角预选框——一张菜单里两种形状，一眼就看得出
///   "没做完"；
/// - **容器的圆角比行的小**：主题默认是 4，比行上那个 12 小一圈，看着像"框比容器圆"。
///
/// 现在行自带圆角 12 的底纹（和预选框同一个形状、同一个半径），容器圆角取
/// 18 = 12 + 行外边距 6，两圈**同心**（见 [TvOsdMenuSpec]）。
///
/// ## 手柄 / 遥控器
///
/// `requestFocus` 只在手柄模式下给 true。菜单是独立路由，路由自己不要焦点的话
/// （原来的写法）手柄按进去什么都不会发生——就是 `docs/tv_focus.md` 里那条
/// "OSD 单选菜单进不去"的已知缺口。给 true 之后框架会把焦点交给菜单这一层，
/// 行自己接住：
///
/// - **当前值那一项带 `autofocus`**，所以打开菜单时预选框就停在当前值上
///   （直播页那颗画质菜单今天能用手柄，靠的是 `TvRouteFocusObserver` 的
///   "这一层第一个可聚焦项"——打开的永远是**第一项**，当前值在下面几行时
///   还得自己找）；
/// - 行自带预选框（[FocusRing]），半径和描边跟兜底环一致，所以"选中的那项"
///   和"手柄停的那项"是同一套形状；
/// - 菜单关掉时框架把焦点还给它自己记着的那颗按钮。
///
/// ## 菜单压着的时候 OSD 不收
///
/// 打开时按住播放器那条 OSD、关掉时放开（[PlPlayerController.holdControls]）：
/// 自动隐藏到点会把 OSD 收掉，菜单关掉时框架想把焦点还给那颗按钮却已经还不了
/// （`PlayerTvOsd` 的 `ExcludeFocus`），表现就是"关掉菜单焦点没了"。
///
/// 关掉「手柄/遥控器模式」时这套焦点行为整条不生效（`requestFocus: false`、
/// 不按住、环也不画，见 [FocusRing.highlightEnabled]），只剩外观那一部分是新的
/// ——外观本来就是这次要改的东西，不分模式。

/// 单选菜单的规格。
///
/// 几个数字之间**有牵连**（容器圆角 = 行圆角 + 行外边距），要么一起改，要么别动。
abstract final class TvOsdMenuSpec {
  /// 行高。和 OSD 上栏那些按钮差不多（42×34 那档），比下栏图标按钮（30）高一点：
  /// 菜单是"一列可以停的项"，行矮了预选框会挤成一条。
  static const double itemHeight = 35;

  /// 行的圆角 = **预选框的圆角**（[TvFocusSpec.radius]）。两者必须是同一个值：
  /// 当前值那道底纹和手柄停上去的预选框是同一个形状，只有描边不一样。
  static const BorderRadius itemRadius = TvFocusSpec.radius;

  /// 行和菜单边之间留的缝：底纹和预选框浮在菜单里，不贴边。
  static const double itemMargin = 6;

  /// 菜单容器的圆角：**同心圆角**——行圆角 + 行外边距，两圈圆角共圆心。
  /// 比主题默认的 4 大得多，正好包住行上那个 12。
  static const BorderRadius menuRadius = BorderRadius.all(
    Radius.circular(12 + itemMargin),
  );

  /// 菜单容器的内边距：上下留 [itemMargin]（左右那圈由行自己的外边距给）。
  static const EdgeInsets menuPadding = EdgeInsets.symmetric(
    vertical: itemMargin,
  );

  /// 行内容离行左右边的距离（框架 M3 默认是 12，这里给宽一点，
  /// 和 12 的圆角配着看着才不挤）。
  static const EdgeInsets itemPadding = EdgeInsets.symmetric(horizontal: 16);

  /// 当前值那一项的底纹：低不透明度的白。
  ///
  /// 用白而不是主题的 `highlightColor`：菜单底是半透明黑（[menuColor]）压在
  /// 视频上，白字配白底纹才是"这一行亮起来了"；主题的 highlight 在浅色主题下
  /// 是浅色，压在这块黑底上会显出一块脏灰。
  static const Color itemColor = Color(0x1FFFFFFF);

  /// 菜单底色：半透明黑，压在视频上还能看见画面（= `Colors.black.withValues(alpha: 0.8)`）。
  static const Color menuColor = Color(0xCC000000);
}

/// 建一颗 OSD 单选菜单（[PopupMenuButton] 的壳子 + 统一的外观和焦点行为）。
///
/// ```dart
/// TvOsdPopupButton.capsule(
///   debugLabel: '倍速',
///   child: tvOsdSelectMenu<double>(
///     tooltip: '倍速',
///     controller: plPlayerController,
///     itemBuilder: (context) => [
///       for (final speed in plPlayerController.speedList)
///         TvOsdMenuItem<double>(
///           value: speed,
///           selected: speed == plPlayerController.playbackSpeed,
///           onTap: () => plPlayerController.setPlaybackSpeed(speed),
///           child: Text('${speed}X', style: _labelStyle),
///         ),
///     ],
///     child: Padding(padding: ..., child: Text(...)),
///   ),
/// )
/// ```
///
/// [controller] 只用来"菜单压着的时候把 OSD 按住"（见 [TvOsdMenuSpec] 上面那段）。
///
/// [onSelected] 是 `PopupMenuButton` 那个（选中后回调），[TvOsdMenuItem.onTap]
/// 是每一行自己的——两个都会调到，用哪个都行（视频页的画质/字幕/倍速在
/// `onTap` 里干活，翻译在 `onSelected` 里干）。
PopupMenuButton<T> tvOsdSelectMenu<T>({
  required String tooltip,
  required PlPlayerController controller,
  required List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder,
  required Widget child,
  ValueChanged<T>? onSelected,
}) {
  return PopupMenuButton<T>(
    tooltip: tooltip,
    // 菜单自己接焦点（手柄模式之外保持原样，准则 6「默认零侵入」）
    requestFocus: Pref.tvFocus,
    // 不用框架的 `initialValue`：它干的就两件事——给当前值那一项刷上**直角**
    // 底纹、以及滚到那一项。底纹由 [TvOsdMenuItem.selected] 自己画，滚动由那一项
    // 自己 `ensureVisible`（见 `_TvOsdMenuItemState`）。菜单的位置不受影响：
    // `_PopupMenuRouteLayout` 的 y 一直是 `position.top`，跟这个参数没关系。
    initialValue: null,
    color: TvOsdMenuSpec.menuColor,
    shape: const RoundedRectangleBorder(
      borderRadius: TvOsdMenuSpec.menuRadius,
    ),
    menuPadding: TvOsdMenuSpec.menuPadding,
    // 菜单压着的时候 OSD 不收（见类注释），关掉时放开
    onOpened: controller.holdControls,
    onCanceled: controller.releaseControlsHold,
    onSelected: (value) {
      controller.releaseControlsHold();
      onSelected?.call(value);
    },
    itemBuilder: itemBuilder,
    child: child,
  );
}

/// 单选菜单里的一行。
///
/// 和 `PopupMenuItem` 的差别只有三处（其余照抄它：`MergeSemantics` + `InkWell` +
/// 定高 + 内边距 + 左对齐 + 回调顺序）：
///
/// 1. 底纹是**圆角**的，半径和预选框一样（[TvOsdMenuSpec.itemRadius]）；
/// 2. 当前值那一项自带底纹（[selected]），不靠框架的 `initialValue`；
/// 3. 当前值那一项 `autofocus`，打开菜单时预选框直接停在它身上。
class TvOsdMenuItem<T> extends PopupMenuEntry<T> {
  const TvOsdMenuItem({
    super.key,
    required this.value,
    required this.child,
    this.enabled = true,
    this.selected = false,
    this.onTap,
  });

  /// 选中这一项时 `Navigator.pop` 回去的值（`PopupMenuButton.onSelected` 收到它）。
  ///
  /// 可空，和 `PopupMenuItem.value` 一样：画质菜单里 `FormatItem.quality` 是
  /// `int?`，原本就是直接塞进去的。空值那一路在框架里等于"取消"
  /// （`showButtonMenu` 拿到 `null` 就调 `onCanceled`、不调 `onSelected`），
  /// 干活的是 [onTap]，所以照旧。
  final T? value;

  /// 这一行的内容（一般是 `Text`）。文字样式由调用方给——菜单里那几种字号
  /// 各有各的场合（画质的禁用项还得换个颜色）。
  final Widget child;

  /// 能不能选。画质里"这一集没有这个清晰度"就是这么标的（禁用项手柄也停不上去，
  /// 和 `PopupMenuItem` 一致）。
  final bool enabled;

  /// 这一项是不是**当前值**：刷上和预选框同一套形状的底纹，并且拿起打开时的焦点。
  ///
  /// 由调用方算好传进来（`itemBuilder` 每次开菜单都会跑，值总是新的）。
  final bool selected;

  /// 选中之后干的事（`onSelected` 之外的那一份，见 [tvOsdSelectMenu]）。
  final VoidCallback? onTap;

  @override
  double get height => TvOsdMenuSpec.itemHeight;

  @override
  bool represents(T? value) => value == this.value;

  @override
  State<TvOsdMenuItem<T>> createState() => _TvOsdMenuItemState<T>();
}

class _TvOsdMenuItemState<T> extends State<TvOsdMenuItem<T>> {
  /// 这一行是不是已经滚过了（滚只做一次，别跟用户手动滚 / 方向键打架）。
  bool _revealed = false;

  /// 先 pop 再 `onTap`：`onTap` 里可能又 push 一层
  /// （对齐 `PopupMenuItemState.handleTap`）。
  void _handleTap() {
    Navigator.pop<T>(context, widget.value);
    widget.onTap?.call();
  }

  @override
  void initState() {
    super.initState();
    if (widget.selected) _scheduleReveal();
  }

  /// 帧末把"当前值"那一项滚进视野。
  ///
  /// 两个理由：
  ///
  /// - 框架的那次滚动是跟着 `initialValue` 走的，我们没用那个参数
  ///   （见 [tvOsdSelectMenu]），得自己来；
  /// - `autofocus` 只把**焦点**送过去、自己不管滚动（方向键那条路会滚，是因为
  ///   `FocusTraversalPolicy.defaultTraversalRequestFocusCallback` 顺手调了
  ///   `Scrollable.ensureVisible`）。十几项的画质菜单里，当前值常常在视口外，
  ///   不滚就看不见那道底纹——"现在用的是哪个"得自己一行行找。
  ///
  /// 对齐方式照抄上面那个回调（`keepVisibleAtEnd`），
  /// 所以"打开菜单停在当前值"和"方向键走到这一项"看到的滚动位置一致。
  void _scheduleReveal() {
    if (_revealed) return;
    _revealed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = this.context;
      if (!context.mounted || Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: TvFocusSpec.scrollAnimation,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 行和菜单边之间留缝：底纹和预选框都画在这一圈**里面**
      // （`FocusRing` 的环画在自己的矩形上，所以外边距必须在它外面，
      // 否则环会和底纹错开 6 像素）
      padding: const EdgeInsets.symmetric(
        horizontal: TvOsdMenuSpec.itemMargin,
      ),
      child: FocusRing(
        debugLabel: 'TvOsdMenuItem',
        radius: TvOsdMenuSpec.itemRadius,
        // 和兜底环（`TvFocusOverlay`）一样的描边：直播页那颗画质菜单里
        // 手柄停上去一直看到的就是它，别的 OSD 按钮也是这个宽度
        borderWidth: TvFocusSpec.borderWidth,
        // 菜单行不放大：一行文字放大 1.04 倍只是让字糊一点，而且
        // `FocusRing` 的缩放只在控件自己的矩形里（顶出去的部分被 12 的圆角裁掉），
        // 看着就是"字动了、框没动"
        scale: 1.0,
        canRequestFocus: widget.enabled,
        builder: (context, focusNode, focused) => MergeSemantics(
          child: Semantics(
            role: SemanticsRole.menuItem,
            enabled: widget.enabled,
            button: true,
            child: Ink(
              decoration: BoxDecoration(
                color: widget.selected ? TvOsdMenuSpec.itemColor : null,
                borderRadius: TvOsdMenuSpec.itemRadius,
              ),
              child: InkWell(
                focusNode: focusNode,
                // 当前值那一项自己接焦点：框架的 `autofocus` 只在"这个 scope
                // 里还没人拿到焦点"时生效——菜单刚打开正是那一下
                autofocus: widget.selected,
                canRequestFocus: widget.enabled,
                onTap: widget.enabled ? _handleTap : null,
                borderRadius: TvOsdMenuSpec.itemRadius,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: TvOsdMenuSpec.itemHeight,
                  ),
                  child: Padding(
                    padding: TvOsdMenuSpec.itemPadding,
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
