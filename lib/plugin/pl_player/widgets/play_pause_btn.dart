import 'dart:async';

import 'package:PiliPlus/common/widgets/focus/tv_button.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  /// 焦点节点自己拿着（[TvButton] 支持外部节点）：它同时是
  /// [TvLabels.playerPlayPause] 锚点——进下栏时把焦点锁过来、全屏下按方向键
  /// 回到这里，这两个动作都发生在别的地方，拿不到这个 State。
  late final FocusNode _focusNode = FocusNode(debugLabel: 'PlayOrPause');

  late final AnimationController controller;
  late final StreamSubscription<bool> subscription;
  late Player player;

  @override
  void initState() {
    super.initState();
    player = widget.plPlayerController.videoPlayerController!;
    controller = AnimationController(
      vsync: this,
      value: player.state.playing ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    subscription = player.stream.playing.listen((playing) {
      if (playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    TvRegions.unregisterAnchor(TvLabels.playerPlayPause, _focusNode);
    _focusNode.dispose();
    subscription.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 登记写在 build 里，跟 `TvPlayerSurface` 那套一样：重复登记直接跳过，
    // 手柄模式关掉时没人会用这个锚点（`TvButton` 那时根本不建节点）
    if (Pref.tvFocus) {
      TvRegions.registerAnchor(TvLabels.playerPlayPause, _focusNode);
    }
    return TvButton(
      focusNode: _focusNode,
      debugLabel: 'PlayOrPause',
      onTap: widget.plPlayerController.onDoubleTapCenter,
      child: SizedBox(
        width: 42,
        height: 34,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.plPlayerController.onDoubleTapCenter,
          child: Center(
            child: AnimatedIcon(
              semanticLabel: player.state.playing ? '暂停' : '播放',
              progress: controller,
              icon: AnimatedIcons.play_pause,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
