import 'package:PiliPlus/common/widgets/focus/tv_section_switcher.dart';
import 'package:PiliPlus/utils/app_back.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart' show KeyEvent, KeyDownEvent;
import 'package:material_ui/material_ui.dart';

/// 全局键位层：只处理"跟焦点在哪无关"的手柄键。
///
/// 挂在 `GetMaterialApp.builder` 里、`Navigator` 外面，
/// 于是它在焦点树上比 `WidgetsApp` 自带的 `Shortcuts` **更深**，
/// 按键会先经过这里（`FocusManager` 从 `primaryFocus` 沿祖先链向上派发），
/// 没吃掉的键继续往上走，方向键/确定键这些默认行为完全不受影响。
///
/// 放在这里的只有三类：
/// - 返回（手柄 B / 遥控器 Select）：复用 [appBack]，和 Esc、鼠标侧键同一套语义；
/// - 切换分栏（L1/R1、`[` `]`）：交给当前页面声明的
///   [TvSectionSwitcher]，页面没声明就放行；
/// - 媒体键：交给 [TvMediaKeys] 里注册的当前播放器。
///
/// 卡片级的长按确定在 `TvCard` 里，比这里更靠近焦点，先于这里生效。
class TvShortcuts extends StatelessWidget {
  const TvShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return child;
    return Focus(
      // 不参与焦点与遍历，只是挂在树上收按键（和 Shortcuts 内部一样）
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      debugLabel: 'TvShortcuts',
      onKeyEvent: handleTvKey,
      child: child,
    );
  }
}

/// 供测试和其它层复用的按键处理：返回 true 表示这个键已消费。
KeyEventResult handleTvKey(FocusNode node, KeyEvent event) {
  if (!Pref.tvFocus) return KeyEventResult.ignored;

  if (TvKeys.isBack(event)) {
    if (TvKeys.isFirstPress(event)) {
      appBack();
    }
    // 按下/重复/抬起都吃掉：B 键不做"按住连退"，
    // 也避免抬起时再触发一次别的行为
    return KeyEventResult.handled;
  }

  final isPrev = TvKeys.isPrevSection(event);
  if (isPrev || TvKeys.isNextSection(event)) {
    if (TvKeys.isFirstPress(event)) {
      _switchSection(isPrev);
    }
    return KeyEventResult.handled;
  }

  final media = TvMediaKeys.active;
  if (media == null) return KeyEventResult.ignored;
  if (TvKeys.playPause.contains(event.logicalKey)) {
    if (event is KeyDownEvent) media.onPlayPause?.call();
    return KeyEventResult.handled;
  }
  if (TvKeys.fastBackward.contains(event.logicalKey)) {
    if (event is KeyDownEvent) media.onSeekBackward?.call();
    return KeyEventResult.handled;
  }
  if (TvKeys.fastForward.contains(event.logicalKey)) {
    if (event is KeyDownEvent) media.onSeekForward?.call();
    return KeyEventResult.handled;
  }
  if (TvKeys.prevMedia.contains(event.logicalKey)) {
    if (event is KeyDownEvent) media.onPrev?.call();
    return KeyEventResult.handled;
  }
  if (TvKeys.nextMedia.contains(event.logicalKey)) {
    if (event is KeyDownEvent) media.onNext?.call();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}

void _switchSection(bool prev) {
  // 用 getInheritedWidgetOfExactType：按键回调不在 build 阶段，
  // 不该登记依赖关系
  final context = FocusManager.instance.primaryFocus?.context;
  final switcher = context?.getInheritedWidgetOfExactType<TvSectionSwitcher>();
  (prev ? switcher?.onPrev : switcher?.onNext)?.call();
}

/// 媒体键的接收端。
///
/// 播放器（视频 / 直播）活着的时候把自己压进来，销毁时移除；
/// 没有播放器时媒体键放行，不抢键。
abstract final class TvMediaKeys {
  static final List<TvMediaKeyTarget> _targets = <TvMediaKeyTarget>[];

  /// 当前生效的接收端（最后压进来的那个）。
  static TvMediaKeyTarget? get active =>
      _targets.isEmpty ? null : _targets.last;

  static void push(TvMediaKeyTarget target) => _targets.add(target);

  static void remove(TvMediaKeyTarget target) => _targets.remove(target);
}

/// 播放器能响应的媒体键，用不到的回调留空即可。
class TvMediaKeyTarget {
  const TvMediaKeyTarget({
    this.onPlayPause,
    this.onSeekBackward,
    this.onSeekForward,
    this.onPrev,
    this.onNext,
  });

  final VoidCallback? onPlayPause;
  final VoidCallback? onSeekBackward;
  final VoidCallback? onSeekForward;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
}
