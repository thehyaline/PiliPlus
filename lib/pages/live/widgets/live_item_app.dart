import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/focus/tv_card.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/video_card/cover_bottom_info.dart';
import 'package:PiliPlus/http/live.dart';
import 'package:PiliPlus/models_new/live/live_feed_index/card_data_list_item.dart';
import 'package:PiliPlus/models_new/live/live_feed_index/feedback.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

// 视频卡片 - 垂直布局
class LiveCardVApp extends StatefulWidget {
  final CardLiveItem item;
  final bool showFirstFrame;

  /// 首项自动拿焦点：进页面时焦点框要有地方落
  final bool autofocus;

  const LiveCardVApp({
    super.key,
    required this.item,
    this.showFirstFrame = false,
    this.autofocus = false,
  });

  @override
  State<LiveCardVApp> createState() => _LiveCardVAppState();
}

class _LiveCardVAppState extends State<LiveCardVApp> {
  CardLiveItem get item => widget.item;

  bool get _hasFeedback => !item.feedback.isNullOrEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 封面上的 ⋮ 已经拿掉：触摸长按、桌面右键、手柄 Y / 遥控器菜单键
    // 都从这儿进反馈菜单
    final VoidCallback? menuAction = _hasFeedback
        ? () => _showFeedback(context)
        : null;
    return Stack(
      children: [
        TvCard(
          autofocus: widget.autofocus,
          onTap: () => PageUtils.toLiveRoom(item.roomid),
          onLongPress: menuAction,
          onSecondaryTap: PlatformUtils.isMobile ? null : menuAction,
          onMore: menuAction,
          surface: tvCardSurface,
          child: Column(
            crossAxisAlignment: .start,
            children: [
              AspectRatio(
                aspectRatio: Style.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, boxConstraints) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      NetworkImgLayer(
                        src: widget.showFirstFrame
                            ? item.systemCover
                            : item.cover,
                        width: boxConstraints.maxWidth,
                        height: boxConstraints.maxHeight,
                        borderRadius: const .vertical(top: .circular(12)),
                      ),
                      videoStat(),
                    ],
                  ),
                ),
              ),
              liveContent(theme),
            ],
          ),
        ),
      ],
    );
  }

  void _showFeedback(BuildContext context) {
    final theme = Theme.of(context);
    Widget actionButton(Reason r) => SearchText(
      text: r.name!,
      onTap: (_) async {
        Get.back();
        SmartDialog.showLoading(msg: '正在提交');
        final res = await LiveHttp.liveFeedback(item.roomid!, r.id!, r.idType!);
        SmartDialog.dismiss();
        if (res.isSuccess) {
          SmartDialog.showToast('提交成功');
        } else {
          res.toast();
        }
      },
    );

    final feedback = item.feedback!;
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          contentPadding: const .fromLTRB(24, 16, 24, 19),
          children: [
            for (var i in feedback) ...[
              const SizedBox(height: 5),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: i.title,
                      style: theme.textTheme.titleMedium,
                    ),
                    TextSpan(
                      text: '\n${i.subtitle}',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: i.reasons!.map(actionButton).toList(),
              ),
            ],
            const Divider(),
            Center(
              child: FilledButton.tonal(
                onPressed: Get.back,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('取消'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget liveContent(ThemeData theme) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 8, 5, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              item.title.toString(),
              textAlign: TextAlign.start,
              style: const TextStyle(letterSpacing: 0.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              item.uname.toString(),
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: theme.textTheme.labelMedium!.fontSize,
                color: theme.colorScheme.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget videoStat() {
    final textLarge = item.watchedShow?.textLarge;
    return CoverBottomInfo(
      left: Text(
        item.areaName.toString(),
        style: CoverBottomInfo.textStyle(),
      ),
      right: textLarge != null
          ? Text(textLarge, style: CoverBottomInfo.textStyle())
          : null,
    );
  }
}
