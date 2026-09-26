import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 只读文本的选区（`SelectionArea`），手柄模式下**从方向键遍历里摘出去**。
///
/// `SelectionArea` 里面那层是 `SelectableRegion`，它给
/// `DefaultTextEditingShortcuts` 里"方向键 = 移动光标 / 扩展选区"那四个意图
/// （`ExtendSelectionByCharacterIntent`、`ExtendSelectionVerticallyToAdjacentLineIntent`）
/// 都注册了动作——而 `Shortcuts` 在按键派发链上**先于**焦点遍历：
/// 焦点只要停在它身上，↑/↓/←/→ 在那一层就被 Consumed，
/// 承载"方向键换焦点"的 `DirectionalFocusIntent` 根本没机会发出来。
///
/// 表现就是手柄上最难受的那一种"卡死"：从视频标签按 ↑ 进到简介正文，
/// 焦点停在 `SelectableRegion` 上不动了，接着怎么按方向键都只是在文本里
/// 挪光标（`docs/tv_focus.md` 的「只读选区」）。
///
/// 这里给它一个 `skipTraversal: true` 的节点：`FocusTraversalPolicy` 挑候选时
/// 会跳过它（`_canRequestTraversalFocus` = `canRequestFocus && !skipTraversal`），
/// 方向键于是照常"路过"这一格去简介里的下一张卡。
///
/// 其余输入方式一律不变：
///
/// - **触摸 / 鼠标**：点一下照样划线、照样弹复制菜单——`requestFocus()`
///   不看 `skipTraversal`（`FocusNode.requestFocus` 的文档原文），
///   只是它不再是方向键的落点。
/// - **键盘选字**：`Shift` + 方向键那几条映射还是它自己的，鼠标点进来之后
///   照常能用；纯方向键的"扩展选区"在只读文本上本来也没有意义。
/// - 关掉「手柄/遥控器模式」时连节点都不建，退回原样的 `SelectionArea`
///   （准则 6「默认零侵入」）。
///
/// 和 `TvTextField` 里 `_editNode.skipTraversal = true` 是同一个做法：
/// 那一格也是"方向键该路过、不该进去"。
class TvSelectionArea extends StatefulWidget {
  const TvSelectionArea({
    super.key,
    required this.child,
    this.contextMenuBuilder,
  });

  /// 选区里的内容。
  final Widget child;

  /// 长按/右键弹出的菜单；不传则和 `SelectionArea` 自带的那份一致。
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;

  /// `SelectionArea` 的默认菜单（`material_ui` 里那份是私有的，这里复刻一份，
  /// 行为逐字一致）。
  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    return AdaptiveTextSelectionToolbar.selectableRegion(
      selectableRegionState: selectableRegionState,
    );
  }

  @override
  State<TvSelectionArea> createState() => _TvSelectionAreaState();
}

class _TvSelectionAreaState extends State<TvSelectionArea> {
  /// 手柄模式下的节点，懒建：关着的时候一个节点都不多。
  FocusNode? _node;

  @override
  void dispose() {
    // 节点是我们自己的（`SelectableRegion` 只借外部传进来的节点，不 dispose 它）
    final node = _node;
    if (node != null) {
      TvFocusRings.unmarkLanding(node);
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    FocusNode? node;
    if (Pref.tvFocus) {
      if (_node case final node0?) {
        node = node0;
      } else {
        node = _node = (FocusNode(debugLabel: 'TvSelectionArea')
          ..skipTraversal = true);
        // 落脚点登记：这块文本只借节点把方向键摘出遍历，自己不出预选框，
        // 兜底层也别照着它画（整块简介/面板那么大的一圈就是"页面级预选框"）
        TvFocusRings.markLanding(node);
      }
    }
    return SelectionArea(
      focusNode: node,
      contextMenuBuilder:
          widget.contextMenuBuilder ?? TvSelectionArea._defaultContextMenuBuilder,
      child: widget.child,
    );
  }
}
