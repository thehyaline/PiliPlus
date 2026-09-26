import 'package:PiliPlus/common/widgets/focus/tv_selection_area.dart';
import 'package:material_ui/material_ui.dart';

/// 一段**只读**的可选文本。
///
/// 走 [TvSelectionArea] 而不是裸的 `SelectionArea`：后者把方向键绑成了
/// "扩展选区 / 移光标"，手柄的焦点一旦停上去就再也走不掉（视频简介那一块，
/// 见 [TvSelectionArea] 的说明）。
class SelectionText extends StatelessWidget {
  const SelectionText(
    String this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
  }) : textSpan = null;

  const SelectionText.rich(
    InlineSpan this.textSpan, {
    super.key,
    this.style,
    this.textAlign,
    this.contextMenuBuilder = _defaultContextMenuBuilder,
  }) : data = null;

  final String? data;
  final InlineSpan? textSpan;
  final TextStyle? style;
  final TextAlign? textAlign;
  final SelectableRegionContextMenuBuilder? contextMenuBuilder;

  static Widget _defaultContextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    return AdaptiveTextSelectionToolbar.selectableRegion(
      selectableRegionState: selectableRegionState,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TvSelectionArea(
      contextMenuBuilder: contextMenuBuilder,
      child: Text.rich(
        style: style,
        textAlign: textAlign,
        TextSpan(
          text: data,
          children: textSpan != null ? <InlineSpan>[textSpan!] : null,
        ),
      ),
    );
  }
}
