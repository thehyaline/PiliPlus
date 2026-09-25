import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class NormalItem extends StatefulWidget {
  final String? title;
  final ValueGetter<String>? getTitle;
  final String? subtitle;
  final ValueGetter<String>? getSubtitle;
  final Widget? leading;
  final Widget Function(ThemeData theme)? getTrailing;
  final void Function(BuildContext context, VoidCallback setState)? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;

  const NormalItem({
    this.title,
    this.getTitle,
    this.subtitle,
    this.getSubtitle,
    this.leading,
    this.getTrailing,
    this.onTap,
    this.contentPadding,
    this.titleStyle,
    super.key,
  }) : assert(title != null || getTitle != null);

  @override
  State<NormalItem> createState() => _NormalItemState();
}

class _NormalItemState extends State<NormalItem> {
  @override
  Widget build(BuildContext context) {
    late final theme = Theme.of(context);
    Widget? subtitle;
    if ((widget.subtitle ?? widget.getSubtitle?.call()) case final text?) {
      subtitle = Text(
        text,
        style: theme.textTheme.labelMedium!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    Widget tile(FocusNode? focusNode) => ListTile(
      contentPadding: widget.contentPadding,
      focusNode: focusNode,
      // 焦点视觉由 FocusRing 负责
      focusColor: focusNode == null ? null : Colors.transparent,
      onTap: widget.onTap == null
          ? null
          : () => widget.onTap!(context, refresh),
      title: Text(
        widget.title ?? widget.getTitle!(),
        style: widget.titleStyle ?? theme.textTheme.titleMedium!,
      ),
      subtitle: subtitle,
      leading: widget.leading,
      trailing: widget.getTrailing?.call(theme),
    );

    // 没有 onTap 的行（版本号、状态说明这类）按下去也没动作，不进焦点树，
    // 免得手柄停在上面白按一下。
    if (!Pref.tvFocus || widget.onTap == null) return tile(null);
    return FocusRing(
      debugLabel: '设置项',
      builder: (context, node, _) => tile(node),
    );
  }

  void refresh() {
    if (mounted) {
      setState(() {});
    }
  }
}
