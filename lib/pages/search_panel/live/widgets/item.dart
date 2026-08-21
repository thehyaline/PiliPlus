import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/image_save.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/video_card/cover_bottom_info.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class LiveItem extends StatelessWidget {
  final SearchLiveItemModel liveItem;

  /// 桌面端沿用主页推荐流封面样式（白字 12 号 + 播放器同款渐变）
  final bool useNewStyle;

  const LiveItem({
    super.key,
    required this.liveItem,
    this.useNewStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void onLongPress() => imageSaveDialog(
      title: liveItem.title.map((item) => item.text).join(),
      cover: liveItem.cover,
    );
    return Card(
      child: InkWell(
        onTap: () => PageUtils.toLiveRoom(liveItem.roomid),
        onLongPress: onLongPress,
        onSecondaryTap: PlatformUtils.isMobile ? null : onLongPress,
        borderRadius: const .all(.circular(12)),
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
                        src: liveItem.cover,
                        width: maxWidth,
                        height: maxHeight,
                        borderRadius: const .vertical(top: .circular(12)),
                      ),
                      useNewStyle
                          ? liveStat(liveItem.online, liveItem.cateName)
                          : Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: liveStat(
                                liveItem.online,
                                liveItem.cateName,
                              ),
                            ),
                    ],
                  );
                },
              ),
            ),
            liveContent(theme),
          ],
        ),
      ),
    );
  }

  Widget liveContent(ThemeData theme) => Expanded(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text.rich(
            TextSpan(
              children: liveItem.title
                  .map(
                    (e) => TextSpan(
                      text: e.text,
                      style: TextStyle(
                        color: e.isEm
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Text(
            liveItem.uname!,
            maxLines: 1,
            style: TextStyle(
              fontSize: theme.textTheme.labelMedium!.fontSize,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    ),
  );

  Widget liveStat(int? online, String? cateName) {
    if (useNewStyle) {
      return CoverBottomInfo(
        left: Text(cateName!, style: CoverBottomInfo.textStyle()),
        right: Text(
          '${NumUtils.numFormat(online)}围观',
          style: CoverBottomInfo.textStyle(),
        ),
      );
    }
    return Container(
      height: 45,
      padding: const EdgeInsets.only(top: 22, left: 8, right: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black54,
          ],
          tileMode: TileMode.mirror,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            cateName!,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
          Text(
            '${NumUtils.numFormat(online)}围观',
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
