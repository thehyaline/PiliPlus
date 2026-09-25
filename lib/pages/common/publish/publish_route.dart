import 'package:PiliPlus/common/widgets/focus/tv_focus_on_open.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class PublishRoute<T> extends PopupRoute<T> {
  PublishRoute({
    required this.pageBuilder,
    this.barrierDismissible = true,
    this.barrierLabel,
    this.barrierColor = const Color(0x80000000),
    Duration? transitionDuration,
    this._transitionBuilder,
    super.settings,
  }) : transitionDuration =
           transitionDuration ??
           (PlatformUtils.isDesktop
               ? const Duration(milliseconds: 400)
               : const Duration(milliseconds: 500));

  final RoutePageBuilder pageBuilder;

  @override
  final bool barrierDismissible;

  @override
  final String? barrierLabel;

  @override
  final Color barrierColor;

  @override
  final Duration transitionDuration;

  final RouteTransitionsBuilder? _transitionBuilder;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      // 打开时把焦点送进去：这些面板（弹幕发送、回复、投币、保存、笔记…）
      // 多半是从播放器控制条 / 顶栏按钮上打开的，不主动送的话焦点还停在底下
      // 那个按钮上，手柄"点开了却选不了"。`Pref.tvFocus` 关掉时它是空操作。
      child: TvFocusOnOpen(
        child: pageBuilder(context, animation, secondaryAnimation),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_transitionBuilder != null) {
      return _transitionBuilder(context, animation, secondaryAnimation, child);
    }
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ),
      ),
      child: child,
    );
  }
}
