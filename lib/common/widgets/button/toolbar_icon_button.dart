import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:material_ui/material_ui.dart';

class ToolbarIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Icon icon;
  final bool selected;
  final String? tooltip;

  const ToolbarIconButton({
    super.key,
    this.onPressed,
    required this.icon,
    required this.selected,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    // 见 `iconButton`：只是加描边，焦点节点还是 `IconButton` 自己的
    return FocusRing(
      debugLabel: tooltip ?? 'ToolbarIconButton',
      builder: (context, focusNode, focused) => SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          focusNode: focusNode,
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          highlightColor: colorScheme.secondaryContainer,
          color: selected
              ? colorScheme.onSecondaryContainer
              : colorScheme.outline,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            backgroundColor: WidgetStatePropertyAll(
              selected ? colorScheme.secondaryContainer : null,
            ),
          ),
        ),
      ),
    );
  }
}
