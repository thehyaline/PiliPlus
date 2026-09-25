import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

final EdgeInsets _padding = PlatformUtils.isMobile
    ? const .symmetric(horizontal: 16, vertical: 14)
    : const .symmetric(horizontal: 16, vertical: 10);

class DialogOption extends StatelessWidget {
  const DialogOption({
    super.key,
    this.onPressed,
    this.child,
  });

  final VoidCallback? onPressed;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: _padding,
      child: child,
    );
    // 没有 onPressed 的选项点了也没动作，不进焦点树
    if (!Pref.tvFocus || onPressed == null) {
      return InkWell(onTap: onPressed, child: content);
    }
    return FocusRing(
      debugLabel: '对话框选项',
      builder: (context, node, _) => InkWell(
        focusNode: node,
        // 焦点视觉由 FocusRing 负责
        focusColor: Colors.transparent,
        onTap: onPressed,
        child: content,
      ),
    );
  }
}
