import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/focus/tv_card.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/stat/stat.dart';
import 'package:PiliPlus/common/widgets/video_card/cover_bottom_info.dart';
import 'package:PiliPlus/common/widgets/video_popup_menu.dart';
import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/models/home/rcmd/result.dart';
import 'package:PiliPlus/models/model_rec_video_item.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/dimension_ext.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

// 视频卡片 - 垂直布局
class VideoCardV extends StatefulWidget {
  final BaseRcmdVideoItemModel videoItem;
  final VoidCallback? onRemove;

  /// 首项自动拿焦点：进页面时焦点框要有地方落
  final bool autofocus;

  const VideoCardV({
    super.key,
    required this.videoItem,
    this.onRemove,
    this.autofocus = false,
  });

  static final shortFormat = DateFormat('M-d');
  static final longFormat = DateFormat('yy-M-d');

  @override
  State<VideoCardV> createState() => _VideoCardVState();
}

class _VideoCardVState extends State<VideoCardV> {
  /// 手柄长按确定 / Y 键要能打开封面右下角那个「更多」按钮的菜单
  final _menuKey = GlobalKey<PopupMenuButtonState<dynamic>>();

  BaseRcmdVideoItemModel get videoItem => widget.videoItem;

  /// 只有 av 卡片带「更多」菜单（动态 / 番剧卡没有）
  bool get _hasMenu => videoItem.goto == 'av';

  Future<void> onPushDetail() async {
    switch (videoItem.goto) {
      case 'bangumi':
        PageUtils.viewPgc(epId: videoItem.param!);
        break;
      case 'av':
        var bvid = videoItem.bvid ?? IdUtils.av2bv(videoItem.aid!);
        var cid = videoItem.cid;
        bool isVertical = false;
        Dimension? dimension;
        if (videoItem is RcmdVideoItemAppModel) {
          if (videoItem.uri case final uri?) {
            isVertical = uri.isVerticalFromUri;
          }
        }
        if (cid == null) {
          if (await SearchHttp.ab2cWithDimension(aid: videoItem.aid, bvid: bvid)
              case final res?) {
            cid = res.cid;
            dimension = res.dimension;
          }
        }
        if (cid != null) {
          PageUtils.toVideoPage(
            aid: videoItem.aid,
            bvid: bvid,
            cid: cid,
            cover: videoItem.cover,
            title: videoItem.title,
            isVertical: isVertical,
            dimension: dimension,
          );
        }
        break;
      // 动态
      case 'picture':
        try {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        } catch (err) {
          SmartDialog.showToast(err.toString());
        }
        break;
      default:
        if (videoItem.uri?.isNotEmpty == true) {
          PiliScheme.routePushFromUrl(videoItem.uri!);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    void onLongPress() => imageSaveDialog(
      title: videoItem.title,
      cover: videoItem.cover,
      bvid: videoItem.bvid,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TvCard(
          autofocus: widget.autofocus,
          onTap: onPushDetail,
          onLongPress: onLongPress,
          onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
          // 长按确定、手柄 Y 键、遥控器菜单键：都进封面右下角那个「更多」
          onMore: _hasMenu
              ? () => _menuKey.currentState?.showButtonMenu()
              : null,
          surface: tvCardSurface,
          child: Column(
            crossAxisAlignment: .start,
            children: [
              AspectRatio(
                aspectRatio: Style.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) {
                    double maxWidth = boxConstraints.maxWidth;
                    double maxHeight = boxConstraints.maxHeight;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        NetworkImgLayer(
                          src: videoItem.cover,
                          width: maxWidth,
                          height: maxHeight,
                          borderRadius: const .vertical(top: .circular(12)),
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
                              if (videoItem.goto != 'picture') ...[
                                const SizedBox(width: 6),
                                StatWidget(
                                  type: .danmaku,
                                  value: videoItem.stat.danmu,
                                  color: Colors.white,
                                ),
                              ],
                            ],
                          ),
                          right: videoItem.duration > 0
                              ? Text(
                                  DurationUtils.formatDuration(
                                    videoItem.duration,
                                  ),
                                  style: CoverBottomInfo.textStyle(),
                                )
                              : null,
                        ),
                      ],
                    );
                  },
                ),
              ),
              content(context),
            ],
          ),
        ),
        if (_hasMenu)
          Positioned(
            right: -5,
            bottom: -2,
            width: 29,
            height: 29,
            child: TvCardSubAction(
              child: VideoPopupMenu(
                buttonKey: _menuKey,
                iconSize: 17,
                videoItem: videoItem,
                onRemove: widget.onRemove,
              ),
            ),
          ),
      ],
    );
  }

  Widget content(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const .fromLTRB(6, 5, 6, 5),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Expanded(
              child: Text(
                videoItem.title,
                maxLines: 2,
                overflow: .ellipsis,
                style: const TextStyle(height: 1.38),
              ),
            ),
            Row(
              spacing: 2,
              children: [
                if (videoItem.goto == 'bangumi')
                  PBadge(
                    text: videoItem.pgcBadge,
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.rcmdReason != null)
                  PBadge(
                    text: videoItem.rcmdReason,
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                if (videoItem.goto == 'picture')
                  const PBadge(
                    text: '动态',
                    isStack: false,
                    size: .small,
                    type: .line_primary,
                    fontSize: 9,
                  ),
                if (videoItem.isFollowed)
                  const PBadge(
                    text: '已关注',
                    isStack: false,
                    size: .small,
                    type: .secondary,
                  ),
                Expanded(
                  flex: 1,
                  child: Text(
                    videoItem.owner.name.toString(),
                    maxLines: 1,
                    overflow: .clip,
                    semanticsLabel: 'UP：${videoItem.owner.name}',
                    style: TextStyle(
                      height: 1.5,
                      fontSize: theme.textTheme.labelMedium!.fontSize,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                if (videoItem is RcmdVideoItemModel) ...[
                  const SizedBox(width: 6),
                  Text.rich(
                    maxLines: 1,
                    TextSpan(
                      style: TextStyle(
                        fontSize: theme.textTheme.labelSmall!.fontSize,
                        color: theme.colorScheme.outline.withValues(alpha: 0.8),
                      ),
                      text: DateFormatUtils.dateFormat(
                        videoItem.pubdate,
                        short: VideoCardV.shortFormat,
                        long: VideoCardV.longFormat,
                      ),
                    ),
                  ),
                ],
                if (videoItem.goto == 'av') const SizedBox(width: 10),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
