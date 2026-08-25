import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/live_tag.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 顶部模式下与 UP主栏分离的独立直播栏：
/// 横向滚动，格子样式与 UP主栏直播项一致，滚动与 UP主列表互不影响
class TopLiveBar extends StatefulWidget {
  const TopLiveBar({super.key, required this.upData});

  final FollowUpModel upData;

  @override
  State<TopLiveBar> createState() => _TopLiveBarState();
}

class _TopLiveBarState extends State<TopLiveBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveList = widget.upData.liveUsers?.items;
    if (liveList == null || liveList.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: Style.upPanelTopHeight,
      child: CustomScrollView(
        scrollDirection: .horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        controller: _scrollController,
        slivers: [
          SliverList.builder(
            itemCount: liveList.length,
            itemBuilder: (context, index) => _liveItem(theme, liveList[index]),
          ),
        ],
      ),
    );
  }

  Widget _liveItem(ThemeData theme, LiveUserItem item) {
    void toMemberPage() => Get.toNamed('/member?mid=${item.mid}');
    return SizedBox(
      width: 72,
      height: Style.upPanelTopHeight,
      child: InkWell(
        onTap: () {
          feedBack();
          PageUtils.toLiveRoom(item.roomId);
        },
        onLongPress: toMemberPage,
        onSecondaryTap: PlatformUtils.isMobile ? null : toMemberPage,
        child: Padding(
          // 内容贴顶并留出圆环（向外扩展 2px）的余量，与 UP主栏直播项一致
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            spacing: 12,
            mainAxisSize: .min,
            children: [
              Stack(
                clipBehavior: .none,
                children: [
                  LiveAvatarBorder(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: NetworkImgLayer(
                        width: 38,
                        height: 38,
                        src: item.face,
                        type: .avatar,
                      ),
                    ),
                  ),
                  // OverflowBox 解除头像宽度约束，让标签以自然宽度渲染并居中溢出；
                  // deferToChild 使自身尺寸跟随子项，避免无界高度约束下尺寸为无限大
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: OverflowBox(
                      fit: OverflowBoxFit.deferToChild,
                      alignment: .topCenter,
                      maxWidth: double.infinity,
                      child: FractionalTranslation(
                        translation: Offset(0, 0.5),
                        child: LiveTag(
                          fontSize: 9,
                          padding: EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  item.uname ?? '',
                  maxLines: 2,
                  textAlign: .center,
                  style: TextStyle(
                    color: theme.colorScheme.outline,
                    height: 1.1,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
