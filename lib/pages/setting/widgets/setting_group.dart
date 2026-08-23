import 'package:PiliPlus/pages/setting/models/model.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页分组容器，采用 Material 3 Contained List 样式：
/// 每个设置项为独立圆角背景块，块间以空白间隔分隔；
/// 组内首项仅顶部圆角、末项仅底部圆角，单项组四角全圆。
class SettingsGroupView extends StatelessWidget {
  const SettingsGroupView({super.key, required this.group});

  final SettingsGroup group;

  static const _gap = 4.0;
  static const _radius = Radius.circular(12);

  @override
  Widget build(BuildContext context) {
    final items = group.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            group.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: ColorScheme.of(context).primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: _gap),
                _ItemContainer(
                  borderRadius: _itemRadius(i, items.length),
                  child: items[i].widget,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static BorderRadius _itemRadius(int index, int length) {
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

class _ItemContainer extends StatelessWidget {
  const _ItemContainer({required this.borderRadius, required this.child});

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorScheme.of(context).surfaceContainerHighest,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
