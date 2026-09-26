import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:material_ui/material_ui.dart';

/// 一行单选（`RadioListTile` / `RadioWidget`）在竖排里认哪几个方向键。
///
/// [vertical] 只认上下：一列选项里左右键本来就没有横向邻居，放给框架的
/// `inDirection` 会被 `closedLoop` 兜底绕到列表另一头（看着像"左右键在列表里
/// 乱跳"），所以这一类按键就地吃掉、不移动。
///
/// [all] 四向都走：`Wrap` 排布的单选（举报理由、登录协议那种）横向真有邻居。
enum TvRadioAxis { vertical, all }

/// 给一行单选接上手柄语义：**方向键只移动高亮，确定键才提交**，外加焦点环。
///
/// 必须用它的原因（`docs/tv_focus.md` 的「单选组」）：框架的 `RadioGroup` 自己
/// 挂了一套方向键快捷键，语义是"方向键 = 选中下一项并提交"
/// （`radio_group.dart` 的 `_selectRadioInDirection` → `onChanged`）。这在桌面上
/// 说得通（ARIA 的 radio group 就是这么写的），在弹窗里是灾难——`SelectDialog`
/// 的 `onChanged` 恰好是 `Navigator.pop`，于是"按一下方向键 = 选中相邻项 + 关窗
/// + 改掉设置"，设置页里每个单选框都这样。
///
/// 绕开的办法是**在行自己的焦点节点上接住按键**：`FocusNode.onKeyEvent` 比
/// `RadioGroup` 内部那层 `Shortcuts.manager` **更深**（前者是焦点自己的节点、
/// 后者在祖先链上），先收到键，所以拦得住。接住之后：
///
/// - 方向键（按下和重复都算，长按可以连续移动）：`FocusNode.focusInDirection`，
///   也就是框架默认的"按几何位置找邻居"，顺带白拿 `Scrollable` 的自动滚动；
///   焦点因此**能走出单选组**（走 `_findNextFocusInDirection` 找的是整个 scope
///   的候选，不限于本组），弹窗里的「确定 / 取消」够得到了。
/// - 确定键（[TvKeys.isOk]：enter / 小键盘回车 / 手柄 A / 遥控器确定 / 空格）：
///   按单选本来的语义提交。**停在已选中项上按确定也算**——框架的
///   `RadioListTile` 这时候直接 return（`!toggleable && checked`），弹窗里就成了
///   "停在当前值上按确定没反应"，这里补上（对 `SelectDialog` 而言正好等于
///   "确认当前值并关窗"）。
/// - 没有 `RadioGroup` 祖先（这一行不是单选组里的）时确定键放行，交给下面控件
///   自己的 `ActivateIntent`。
///
/// 触摸 / 鼠标那条路没动过：`onTap` 还是框架/调用方自己那个（准则 6「默认零
/// 侵入」，`Pref.tvFocus` 关掉时连环都不建）。
///
/// 用法就是把它套在 `RadioListTile` 外面，节点照旧递给里面的控件：
/// ```dart
/// tvRadioTile<T>(
///   debugLabel: '选项',
///   value: item.$1,
///   builder: (focusNode) => RadioListTile<T>(
///     value: item.$1,
///     focusNode: focusNode,
///     title: Text(item.$2),
///   ),
/// )
/// ```
Widget tvRadioTile<T>({
  required String debugLabel,
  required T value,
  required Widget Function(FocusNode? focusNode) builder,
  bool toggleable = false,
  TvRadioAxis axis = TvRadioAxis.vertical,
  bool reveal = false,
  FocusNode? focusNode,
}) {
  if (!Pref.tvFocus) return builder(null);
  return _TvRadioTile<T>(
    debugLabel: debugLabel,
    value: value,
    builder: builder,
    toggleable: toggleable,
    axis: axis,
    reveal: reveal,
    focusNode: focusNode,
  );
}

class _TvRadioTile<T> extends StatefulWidget {
  const _TvRadioTile({
    required this.debugLabel,
    required this.value,
    required this.builder,
    required this.toggleable,
    required this.axis,
    required this.reveal,
    this.focusNode,
  });

  final String debugLabel;

  /// 这一行代表的值——提交时用它。
  final T value;

  /// 借用外部焦点节点（`RadioWidget` 拿它当 `RadioClient` 用）。
  final FocusNode? focusNode;

  /// 再按一次确定能不能取消选中（对应 `RadioListTile.toggleable`）。
  final bool toggleable;

  final TvRadioAxis axis;

  /// 建出来之后把这一行滚进视野，配合 `autofocus` 用。
  final bool reveal;

  final Widget Function(FocusNode? focusNode) builder;

  @override
  State<_TvRadioTile<T>> createState() => _TvRadioTileState<T>();
}

class _TvRadioTileState<T> extends State<_TvRadioTile<T>> {
  /// 所在单选组的登记处——提交要走它（组的 `onChanged`）。
  RadioGroupRegistry<T>? _registry;

  /// 这一行是不是已经滚过了（滚只做一次，别跟用户手动滚打架）。
  bool _revealed = false;
  FocusNode? _revealNode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 会登记依赖：组值变了这一行要重建（勾选状态由里面的 `RadioListTile` 读）
    _registry = RadioGroup.maybeOf<T>(context);
  }

  /// 高亮的是不是"已经选中"的那一项。
  bool get _checked => _registry?.groupValue == widget.value;

  /// 帧末把这一行滚进视野。
  ///
  /// `autofocus` 只把焦点送过去、**不管滚动**（方向键那条路会滚，是因为
  /// `FocusTraversalPolicy.defaultTraversalRequestFocusCallback` 顺手调了
  /// `Scrollable.ensureVisible`），所以长列表里"打开停在当前值上"还可能停在
  /// 视口外，看着像什么都没选中。这里补一次，对齐方式和"方向键往下走到这一项"
  /// 一致。
  void _scheduleReveal(FocusNode? node) {
    if (!widget.reveal || _revealed || node == null) return;
    _revealed = true;
    _revealNode = node;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _revealNode?.context;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: TvFocusSpec.scrollAnimation,
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (TvKeys.isDpad(event)) {
      if (TvKeys.isPressOrRepeat(event)) {
        _move(node, TvKeys.directionOf(event)!);
      }
      // 抬起也吃掉：这一层漏出去就会落到 `RadioGroup` 的快捷键上，
      // 那套语义正是我们要挡的
      return KeyEventResult.handled;
    }

    final registry = _registry;
    if (!TvKeys.isOk(event)) return KeyEventResult.ignored;
    // 不是单选组里的行：确定键交给下面控件自己的 `ActivateIntent`
    if (registry == null) return KeyEventResult.ignored;
    if (TvKeys.isFirstPress(event)) {
      // 已选中的话，`toggleable` 才允许取消；否则就是"再确认一次当前值"
      registry.onChanged(
        _checked ? (widget.toggleable ? null : widget.value) : widget.value,
      );
    }
    return KeyEventResult.handled;
  }

  void _move(FocusNode node, TraversalDirection direction) {
    // 一列选项里左右没有横向邻居，见 [TvRadioAxis.vertical]
    if (widget.axis == TvRadioAxis.vertical &&
        (direction == TraversalDirection.left ||
            direction == TraversalDirection.right)) {
      return;
    }
    node.focusInDirection(direction);
  }

  @override
  Widget build(BuildContext context) {
    return listTileFocusRing(
      debugLabel: widget.debugLabel,
      focusNode: widget.focusNode,
      onKeyEvent: _handleKey,
      builder: (focusNode) {
        _scheduleReveal(focusNode);
        return widget.builder(focusNode);
      },
    );
  }
}
