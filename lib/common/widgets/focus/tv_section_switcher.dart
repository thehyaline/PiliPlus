import 'package:material_ui/material_ui.dart';

/// 页面声明"我有分栏（Tab），L1/R1 应该切栏"。
///
/// 全局键位层拿到 L1/R1 后，从**当前焦点所在位置**往上找这个控件，
/// 找到了就调用对应的回调。所以：
/// - 页面里有分栏，就在 TabBar 外面套一层 [TvSectionSwitcher]；
/// - 页面里没有分栏，L1/R1 就没人接，按键会被放行（不影响其它逻辑）。
///
/// 这样"切换分栏"这个处理只写在页面里，全局层不需要认识任何页面。
class TvSectionSwitcher extends InheritedWidget {
  const TvSectionSwitcher({
    super.key,
    this.onPrev,
    this.onNext,
    required super.child,
  });

  /// 上一栏；null 表示到头了。
  final VoidCallback? onPrev;

  /// 下一栏；null 表示到头了。
  final VoidCallback? onNext;

  static TvSectionSwitcher? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TvSectionSwitcher>();

  @override
  bool updateShouldNotify(TvSectionSwitcher oldWidget) =>
      onPrev != oldWidget.onPrev || onNext != oldWidget.onNext;
}
