import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页分组标题，位于项块上方。
class SettingsGroupTitle extends StatelessWidget {
  const SettingsGroupTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: ColorScheme.of(context).primary,
        ),
      ),
    );
  }
}

/// 设置项圆角背景块（M3 Contained List 样式）。
class SettingsGroupItem extends StatelessWidget {
  const SettingsGroupItem({
    super.key,
    required this.borderRadius,
    this.color,
    required this.child,
  });

  final BorderRadius borderRadius;

  /// 背景色，默认 surfaceContainerHighest
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? ColorScheme.of(context).surfaceContainerHighest,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 设置项列：横向留白 16，项间空白间隔 4，按位置计算圆角
/// （组内首项仅顶部圆角、末项仅底部圆角、单项组四角全圆、中间项直角）。
class SettingsGroupColumn extends StatelessWidget {
  const SettingsGroupColumn({super.key, required this.children, this.colorFor});

  final List<Widget> children;

  /// 每项背景色回调（如横屏选中态高亮），返回 null 时使用默认背景色
  final Color? Function(int index)? colorFor;

  static const _gap = 4.0;
  static const _radius = Radius.circular(12);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: _gap),
            SettingsGroupItem(
              borderRadius: itemRadius(i, children.length),
              color: colorFor?.call(i),
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }

  static BorderRadius itemRadius(int index, int length) {
    if (index == 0 && index == length - 1) {
      return const BorderRadius.all(_radius);
    }
    if (index == 0) {
      return const BorderRadius.vertical(top: _radius);
    }
    if (index == length - 1) {
      return const BorderRadius.vertical(bottom: _radius);
    }
    return BorderRadius.zero;
  }
}

/// 设置页分组容器，采用 Material 3 Contained List 样式：
/// 每个设置项为独立圆角背景块，块间以空白间隔分隔；
/// 组内首项仅顶部圆角、末项仅底部圆角，单项组四角全圆。
class SettingsGroupView extends StatelessWidget {
  const SettingsGroupView({super.key, required this.group});

  final SettingsGroup group;

  @override
  Widget build(BuildContext context) {
    final items = group.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroupTitle(title: group.title),
        SettingsGroupColumn(
          children: [for (final item in items) item.widget],
        ),
      ],
    );
  }
}
