import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/models/common/enum_with_label.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

typedef PopupMenuItemSelected<T> = void Function(
  T value,
  VoidCallback setState,
);

List<PopupMenuEntry<T>> enumItemBuilder<T extends EnumWithLabel>(
  Iterable<T> items,
) => items.map((e) => PopupMenuItem(value: e, child: Text(e.label))).toList();

enum DescPosType { subtitle, title, trailing }

class PopupListTile<T> extends StatefulWidget {
  const PopupListTile({
    super.key,
    this.dense,
    this.safeArea = true,
    this.enabled = true,
    this.leading,
    required this.title,
    this.descPosType = .subtitle,
    required this.value,
    required this.itemBuilder,
    required this.onSelected,
    this.titleStyle,
    this.descStyle,
  });

  final bool? dense;
  final bool safeArea;
  final bool enabled;
  final Widget? leading;
  final Widget title;

  final DescPosType descPosType;
  final ValueGetter<(T, String)> value;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final TextStyle? titleStyle;
  final TextStyle? descStyle;

  @override
  State<PopupListTile<T>> createState() => _PopupListTileState<T>();
}

class _PopupListTileState<T> extends State<PopupListTile<T>> {
  final _key = PlatformUtils.isDesktop ? null : GlobalKey();

  /// [details] 为空表示不是指针触发的（手柄按了确定）——那时菜单锚在这一行自己身上。
  void _showButtonMenu(TapUpDetails? details, T value) {
    final thisBox = context.findRenderObject();
    if (thisBox is! RenderBox || !thisBox.hasSize) return;
    final thisOffset = thisBox.localToGlobal(Offset.zero);
    final localX = details?.localPosition.dx ?? thisBox.size.width / 2;
    final double dx;
    if (PlatformUtils.isDesktop) {
      dx = thisOffset.dx + localX + 1;
    } else {
      final titleBox = _key!.currentContext!.findRenderObject() as RenderBox;
      final titleOffset = titleBox.localToGlobal(.zero, ancestor: thisBox);
      dx = thisOffset.dx + titleOffset.dx;
    }
    showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(dx, thisOffset.dy + 5, dx, 0),
      items: widget.itemBuilder(context),
      initialValue: value,
      // 手柄要把焦点交给菜单，否则方向键和确定键还留在列表上（菜单开着却动不了）
      requestFocus: Pref.tvFocus,
    ).then<void>((newValue) {
      if (!mounted) return;
      if (newValue == null || newValue == value) return;
      widget.onSelected(newValue, _refresh);
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (value, descStr) = widget.value();
    Widget title = KeyedSubtree(key: _key, child: widget.title);
    Widget? subtitle;
    Widget? trailing;
    final desc = Text(
      descStr,
      style: (widget.descStyle ?? theme.textTheme.labelMedium!).copyWith(
        color: widget.enabled
            ? theme.colorScheme.onSurfaceVariant
            : theme.disabledColor,
      ),
    );
    switch (widget.descPosType) {
      case DescPosType.subtitle:
        subtitle = desc;
      case DescPosType.title:
        title = Row(
          spacing: 12,
          mainAxisSize: .min,
          children: [title, desc],
        );
      case DescPosType.trailing:
        trailing = desc;
    }

    Widget tile(FocusNode? focusNode) => ListTile(
      dense: widget.dense,
      safeArea: widget.safeArea,
      enabled: widget.enabled,
      focusNode: focusNode,
      // 焦点视觉由 FocusRing 负责
      focusColor: focusNode == null ? null : Colors.transparent,
      // 只配了 onTapUp 的 InkWell 是"能聚焦但按确定没反应"（框架的
      // ActivateIntent 只认 onTap），所以手柄那条路走下面的 onKeyEvent
      onTapUp: (details) => _showButtonMenu(details, value),
      leading: widget.leading,
      title: title,
      titleTextStyle: widget.titleStyle ?? theme.textTheme.titleMedium,
      subtitle: subtitle,
      trailing: trailing,
    );

    if (!Pref.tvFocus) return tile(null);
    return FocusRing(
      debugLabel: '设置项',
      onKeyEvent: (node, event) {
        if (!TvKeys.isOk(event)) return KeyEventResult.ignored;
        if (TvKeys.isFirstPress(event)) _showButtonMenu(null, value);
        return KeyEventResult.handled;
      },
      builder: (context, node, _) => tile(node),
    );
  }
}
