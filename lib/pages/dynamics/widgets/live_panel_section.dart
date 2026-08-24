import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/button/more_btn.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/live_tag.dart';
import 'package:PiliPlus/models/common/dynamic/live_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/live_follow/view.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class LivePanelSection extends StatelessWidget {
  const LivePanelSection({
    super.key,
    required this.upData,
    required this.position,
  });

  final FollowUpModel upData;
  final LivePanelPosition position;

  void toFollowPage() => Get.to(const LiveFollowPage());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveList = upData.liveUsers?.items;
    return Padding(
      padding: EdgeInsets.only(
        left: position == LivePanelPosition.right
            ? 0
            : Style.waterfallMargin,
        top: Style.waterfallMargin,
        right: position == LivePanelPosition.left
            ? 0
            : Style.waterfallMargin,
        // 底部留空隙，避免内容贴底/被底部导航栏遮挡
        bottom: 20,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight),
          child: Material(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: toFollowPage,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    child: Row(
                      children: [
                        Text(
                          '正在直播',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        moreTextButton(
                          text: '更多',
                          onTap: toFollowPage,
                          color: theme.colorScheme.outline,
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: liveList == null || liveList.isEmpty
                      ? SizedBox(
                          height: 56,
                          child: Center(
                            child: Text(
                              '暂无正在直播的UP主',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          itemCount: liveList.length,
                          itemBuilder: (context, index) =>
                              _liveItem(theme, liveList[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _liveItem(ThemeData theme, LiveUserItem item) {
    return InkWell(
      onTap: () {
        feedBack();
        PageUtils.toLiveRoom(item.roomId);
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                LiveAvatarBorder(
                  child: NetworkImgLayer(
                    width: 38,
                    height: 38,
                    src: item.face,
                    type: .avatar,
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: FractionalTranslation(
                      translation: Offset(0, 0.5),
                      child: LiveTag(fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.uname ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
