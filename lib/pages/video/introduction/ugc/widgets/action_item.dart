import 'package:PiliPlus/common/widgets/custom_arc.dart';
import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart' show KeyDownEvent, KeyEvent, KeyUpEvent;
import 'package:material_ui/material_ui.dart';

/// 点赞 / 投币 / 收藏 / 分享……一颗 28 见方的小图标按钮。
///
/// 手柄适配两点：
/// - 统一的焦点环（原来只有 Material 自带的一点点 focus 高亮，手柄上看不出来）；
/// - 点赞那颗的按键补丁，见 [_handleKey]。
class ActionItem extends StatefulWidget {
  const ActionItem({
    super.key,
    required this.icon,
    this.selectIcon,
    this.onTap,
    this.onLongPress,
    this.text,
    this.selectStatus = false,
    required this.semanticsLabel,
    this.expand = true,
    this.animation,
    this.onStartTriple,
    this.onCancelTriple,
  }) : assert(!selectStatus || selectIcon != null),
       _isThumbsUp = onStartTriple != null;

  final Icon icon;
  final Icon? selectIcon;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? text;
  final bool selectStatus;
  final String semanticsLabel;
  final bool expand;
  final Animation<double>? animation;
  final VoidCallback? onStartTriple;
  final void Function([bool])? onCancelTriple;
  final bool _isThumbsUp;

  @override
  State<ActionItem> createState() => _ActionItemState();
}

class _ActionItemState extends State<ActionItem> {
  /// 确定键是否按着（手柄 A / 遥控器确定 / 回车）。
  bool _holdingOk = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isThumbsUp = widget._isThumbsUp;
    late final primary = !widget.expand && colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    Widget child = Icon(
      widget.selectStatus ? widget.selectIcon!.icon! : widget.icon.icon,
      size: 18,
      color: widget.selectStatus
          ? primary
          : widget.icon.color ?? colorScheme.outline,
      semanticLabel: widget.semanticsLabel,
    );

    if (widget.animation != null) {
      child = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: widget.animation!,
            builder: (context, child) => Arc(
              size: 28,
              color: primary,
              progress: -widget.animation!.value,
            ),
          ),
          child,
        ],
      );
    } else {
      child = SizedBox.square(dimension: 28, child: child);
    }

    if (widget.expand) {
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [child, _buildText(theme)],
      );
    }

    Widget result;
    if (Pref.tvFocus) {
      result = FocusRing(
        // 环贴着按钮自己的 6dp 圆角走，别用卡片那套 12dp
        radius: const .all(.circular(6)),
        debugLabel: widget.semanticsLabel,
        onKeyEvent: isThumbsUp ? _handleKey : null,
        onFocusChange: isThumbsUp ? _handleFocusChange : null,
        builder: (context, node, _) => _buildInk(isThumbsUp, child, node),
      );
    } else {
      result = _buildInk(isThumbsUp, child);
    }
    return widget.expand ? Expanded(child: result) : result;
  }

  Widget _buildInk(bool isThumbsUp, Widget child, [FocusNode? focusNode]) {
    return Material(
      type: .transparency,
      child: InkWell(
        focusNode: focusNode,
        // 焦点视觉由 FocusRing 负责
        focusColor: focusNode == null ? null : Colors.transparent,
        borderRadius: const .all(.circular(6)),
        onTap: isThumbsUp ? null : widget.onTap,
        onLongPress: isThumbsUp ? null : widget.onLongPress,
        onSecondaryTap: PlatformUtils.isMobile || isThumbsUp
            ? null
            : widget.onLongPress,
        onTapDown: isThumbsUp ? (_) => widget.onStartTriple!() : null,
        onTapUp: isThumbsUp ? (_) => widget.onCancelTriple!(true) : null,
        onTapCancel: isThumbsUp ? widget.onCancelTriple : null,
        child: child,
      ),
    );
  }

  /// 点赞键的按键补丁：确定键**按一下 = 点赞，按住不放 = 三连**。
  ///
  /// 这颗按钮的点击语义全在 `onTapDown` / `onTapUp` 上（按下开始计时，
  /// 抬起时按计时长短判定点赞还是三连），它没有 `onTap`；而框架里确定键走的是
  /// `ActivateIntent` → `InkWell.activateOnIntent`，那个回调只在有 `onTap`
  /// 时才真的触发——于是手柄上这颗按钮"能聚焦、按确定没反应"。
  ///
  /// 这里在焦点节点上直接接管，把按下/抬起这一对原样补给 `TripleMixin`，
  /// 手感和触摸完全一致（三连的进度弧会绕着图标转，全屏里还会铺一层动画）。
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!TvKeys.isOk(event)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      // 系统按键重复不算新的一次按下
      if (!_holdingOk) {
        _holdingOk = true;
        widget.onStartTriple!();
      }
    } else if (event is KeyUpEvent) {
      _holdingOk = false;
      widget.onCancelTriple!(true);
    }
    return KeyEventResult.handled;
  }

  void _handleFocusChange(bool focused) {
    if (focused || !_holdingOk) return;
    // 焦点被抢走就作废这次按下（对齐 TvCard），免得松手后莫名其妙三连
    _holdingOk = false;
    widget.onCancelTriple?.call();
  }

  Widget _buildText(ThemeData theme) {
    final hasText = widget.text != null;
    final child = Text(
      hasText ? widget.text! : '-',
      key: hasText ? ValueKey(widget.text!) : null,
      style: TextStyle(
        color: widget.selectStatus
            ? theme.colorScheme.primary
            : theme.colorScheme.outline,
        fontSize: theme.textTheme.labelSmall!.fontSize,
      ),
    );
    if (hasText) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) =>
            ScaleTransition(scale: animation, child: child),
        child: child,
      );
    }
    return child;
  }
}
