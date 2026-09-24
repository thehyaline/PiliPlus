import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

class SearchText extends StatelessWidget {
  final String text;
  final ValueChanged<String>? onTap;
  final ValueChanged<String>? onLongPress;
  final double? fontSize;
  final Color? bgColor;
  final Color? textColor;
  final TextAlign? textAlign;
  final double? height;
  final EdgeInsets padding;
  final BorderRadius borderRadius;

  const SearchText({
    super.key,
    required this.text,
    this.onTap,
    this.onLongPress,
    this.fontSize,
    this.bgColor,
    this.textColor,
    this.textAlign,
    this.height,
    this.padding = const .symmetric(horizontal: 11, vertical: 5),
    this.borderRadius = const .all(.circular(6)),
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    if (!Pref.tvFocus) return _build(colorScheme);
    // 标签也是导航目标（直播页的分区/标签、搜索的历史词与筛选条件……），
    // 套上统一的焦点环：原来只有 Material 自带的一点 focus 高亮，手柄上看不出来
    return FocusRing(
      radius: borderRadius,
      debugLabel: 'SearchText',
      builder: (context, node, _) => _build(colorScheme, node),
    );
  }

  Widget _build(ColorScheme colorScheme, [FocusNode? focusNode]) {
    final hasLongPress = onLongPress != null;
    return Material(
      color: bgColor ?? colorScheme.onInverseSurface,
      borderRadius: borderRadius,
      child: InkWell(
        focusNode: focusNode,
        // 焦点视觉由 FocusRing 负责
        focusColor: focusNode == null ? null : Colors.transparent,
        onTap: () => onTap?.call(text),
        onLongPress: hasLongPress ? () => onLongPress!(text) : null,
        onSecondaryTap: hasLongPress && !PlatformUtils.isMobile
            ? () => onLongPress!(text)
            : null,
        borderRadius: borderRadius,
        child: Padding(
          padding: padding,
          child: Text(
            text,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: fontSize,
              height: height,
              color: textColor ?? colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
