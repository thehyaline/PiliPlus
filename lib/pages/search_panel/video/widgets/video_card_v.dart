import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/progress_bar/video_progress_indicator.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/cover_bottom_info.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/horizontal_video_model.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

// 搜索视频卡片 - 垂直布局（桌面端搜索结果页沿用主页推荐流样式）
class SearchVideoCardV extends StatelessWidget {
  final HorizontalVideoModel videoItem;
  final VoidCallback? onRemove;

  const SearchVideoCardV({
    super.key,
    required this.videoItem,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      bvid: videoItem.bvid,
      title: videoItem.title,
      cover: videoItem.cover,
    );
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          child: InkWell(
            onLongPress: onLongPress,
            onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
            onTap: onTap,
            borderRadius: const .all(.circular(12)),
            child: Column(
              crossAxisAlignment: .start,
              children: [
                AspectRatio(
                  aspectRatio: Style.aspectRatio,
                  child: LayoutBuilder(
                    builder: (context, boxConstraints) {
                      final double maxWidth = boxConstraints.maxWidth;
                      final double maxHeight = boxConstraints.maxHeight;
                      final progress = videoItem.progress;
                      final bool showProgress = progress != null && progress != 0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          NetworkImgLayer(
                            src: videoItem.cover,
                            width: maxWidth,
                            height: maxHeight,
                            borderRadius: const .vertical(top: .circular(12)),
                          ),
                          if (videoItem.badge case final badge?)
                            PBadge(
                              text: badge,
                              top: 6.0,
                              right: 6.0,
                              type: switch (badge) {
                                '充电专属' => .error,
                                _ => .primary,
                              },
                            ),
                          CoverBottomInfo(
                            left: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StatWidget(
                                  type: .play,
                                  value: videoItem.stat.view,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                StatWidget(
                                  type: .danmaku,
                                  value: videoItem.stat.danmu,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                            right: showProgress || videoItem.duration > 0
                                ? Text(
                                    showProgress
                                        ? progress == -1
                                              ? '已看完'
                                              : '${DurationUtils.formatDuration(progress)}/${DurationUtils.formatDuration(videoItem.duration)}'
                                        : DurationUtils.formatDuration(
                                            videoItem.duration,
                                          ),
                                    style: CoverBottomInfo.textStyle(),
                                  )
                                : null,
                          ),
                          if (showProgress)
                            Positioned(
                              left: 0,
                              bottom: 0,
                              right: 0,
                              child: VideoProgressIndicator(
                                color: theme.colorScheme.primary,
                                backgroundColor:
                                    theme.colorScheme.secondaryContainer,
                                progress: progress == -1
                                    ? 1
                                    : progress / videoItem.duration,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                content(theme),
              ],
            ),
          ),
        ),
        Positioned(
          right: -5,
          bottom: -2,
          width: 29,
          height: 29,
          child: VideoPopupMenu(
            iconSize: 17,
            videoItem: videoItem,
            onRemove: onRemove,
          ),
        ),
      ],
    );
  }

  Future<void> onTap() async {
    if (videoItem.isPugv ?? false) {
      PageUtils.viewPugv(seasonId: videoItem.seasonId);
      return;
    }

    if (videoItem.isLive ?? false) {
      if (videoItem.roomId case final roomId?) {
        PageUtils.toLiveRoom(roomId);
      }
      return;
    }

    if (videoItem.redirectUrl?.isNotEmpty == true &&
        PageUtils.viewPgcFromUri(videoItem.redirectUrl!)) {
      return;
    }

    int? cid = videoItem.cid;
    Dimension? dimension = videoItem.dimension;
    if (cid == null) {
      if (await SearchHttp.ab2cWithDimension(
            aid: videoItem.aid,
            bvid: videoItem.bvid,
          )
          case final res?) {
        cid = res.cid;
        dimension = res.dimension;
      }
    }
    if (cid != null) {
      PageUtils.toVideoPage(
        bvid: videoItem.bvid,
        cid: cid,
        cover: videoItem.cover,
        title: videoItem.title,
        dimension: dimension,
      );
    }
  }

  Widget content(ThemeData theme) {
    String pubdate = DateFormatUtils.dateFormat(videoItem.pubdate!);
    if (pubdate != '') pubdate += '  ';
    return Expanded(
      child: Padding(
        padding: const .fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            if (videoItem.titleList?.isNotEmpty == true)
              Expanded(
                child: Text.rich(
                  overflow: .ellipsis,
                  maxLines: 2,
                  TextSpan(
                    children: videoItem.titleList!
                        .map(
                          (e) => TextSpan(
                            text: e.text,
                            style: TextStyle(
                              fontSize: theme.textTheme.bodyMedium!.fontSize,
                              height: 1.42,
                              letterSpacing: 0.3,
                              color: e.isEm
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              )
            else
              Expanded(
                child: Text(
                  videoItem.title,
                  textAlign: .start,
                  style: TextStyle(
                    fontSize: theme.textTheme.bodyMedium!.fontSize,
                    height: 1.42,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
              ),
            Text(
              "$pubdate${videoItem.owner.name}",
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                height: 1,
                color: theme.colorScheme.outline,
                overflow: .clip,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
