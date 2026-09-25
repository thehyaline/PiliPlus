import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/common/widgets/progress_bar/segment_progress_bar.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/tv_seek_bar.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class BottomControl extends StatelessWidget {
  const BottomControl({
    super.key,
    required this.maxWidth,
    required this.isFullScreen,
    required this.controller,
    required this.buildBottomControl,
    required this.videoDetailController,
  });
  final double maxWidth;
  final bool isFullScreen;
  final PlPlayerController controller;
  final ValueGetter<Widget> buildBottomControl;
  final VideoDetailController videoDetailController;

  void onDragStart(ThumbDragDetails duration) {
    feedBack();
    controller.onSeekStart(duration.seconds);
  }

  void onDragUpdate(ThumbDragDetails duration) {
    if (!controller.isFileSource && controller.showSeekPreview) {
      controller.updatePreviewIndex(duration.seconds);
    }
    controller.seekPosition.value = duration.seconds;
  }

  void onSeek(int milliseconds) {
    controller
      ..position.value = milliseconds ~/ 1000
      ..onSeekEnd()
      ..seekTo(Duration(milliseconds: milliseconds), isSeek: false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final primary = colorScheme.isLight
        ? colorScheme.inversePrimary
        : colorScheme.primary;
    final thumbGlowColor = primary.withAlpha(80);
    final bufferedBarColor = primary.withValues(alpha: 0.4);
    // 手柄播放器模型：焦点落在**进度指示器**上，预选框画成 thumb 外面的一圈。
    // 这一栏只有视频页用（直播页自带下栏、也没有进度条），不用再分直播
    final focusOnThumb = isPlayerTvMode();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 7),
            child: Obx(
              () => Offstage(
                offstage: !controller.showControls.value,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    TvSeekBar(
                      host: _ControllerSeekBarHost(controller, onSeek),
                      focusOnThumb: focusOnThumb,
                      // 进度条要等 TvSeekBar 自己的 build 才构造（`builder`），
                      // 所以位置/缓冲/时长必须在这个 Obx **里面**读：读到外面
                      // GetX 会抛 "improper use of a GetX"（进度条也就不再跟着走）
                      builder: (context, focused) => Obx(
                        () => ProgressBar(
                          progress: controller.progress,
                          buffered: controller.buffered.value,
                          total: controller.duration.value,
                          progressBarColor: primary,
                          baseBarColor: const Color(0x33FFFFFF),
                          bufferedBarColor: bufferedBarColor,
                          thumbColor: primary,
                          thumbGlowColor: thumbGlowColor,
                          barHeight: 3.5,
                          thumbRadius: 7,
                          thumbGlowRadius: 25,
                          thumbFocusRing: focused,
                          thumbFocusRingColor: primary,
                          onDragStart: onDragStart,
                          onDragUpdate: onDragUpdate,
                          onSeek: onSeek,
                        ),
                      ),
                    ),
                    if (controller.enableBlock &&
                        videoDetailController.segmentProgressList.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 5.25,
                        child: SegmentProgressBar(
                          segments: videoDetailController.segmentProgressList,
                        ),
                      ),
                    if (controller.showViewPoints &&
                        videoDetailController.viewPointList.isNotEmpty &&
                        videoDetailController.showVP.value)
                      Padding(
                        padding: const .only(bottom: 8.75),
                        child: ViewPointSegmentProgressBar(
                          segments: videoDetailController.viewPointList,
                          onSeek: PlatformUtils.isDesktop
                              ? (position) =>
                                    controller.seekTo(position, isSeek: false)
                              : null,
                        ),
                      ),
                    if (videoDetailController.showDmTrendChart.value)
                      if (videoDetailController.dmTrend.value?.dataOrNull
                          case final list?)
                        buildDmChart(primary, list, videoDetailController, 4.5),
                  ],
                ),
              ),
            ),
          ),
          buildBottomControl(),
        ],
      ),
    );
  }
}

/// 把 [PlPlayerController] 收窄成 [TvSeekBarHost]（手柄在进度条上微调用）。
class _ControllerSeekBarHost implements TvSeekBarHost {
  const _ControllerSeekBarHost(this.controller, this.onSeek);

  final PlPlayerController controller;
  final ValueChanged<int> onSeek;

  @override
  int get position => controller.position.value;

  @override
  int get duration => controller.duration.value;

  @override
  int get seekPosition => controller.seekPosition.value;

  @override
  set seekPosition(int value) => controller.seekPosition.value = value;

  @override
  void beginSeek(int seconds) => controller.onSeekStart(seconds);

  @override
  void commitSeek(int milliseconds) => onSeek(milliseconds);

  @override
  void previewIndex(int seconds) => controller.updatePreviewIndex(seconds);

  @override
  bool get showPreview =>
      !controller.isFileSource && controller.showSeekPreview;

  @override
  void togglePlay() => controller.onDoubleTapCenter();
}
