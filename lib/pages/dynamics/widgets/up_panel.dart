import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/live_tag.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/live_follow/view.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

class UpPanel extends StatefulWidget {
  const UpPanel({
    super.key,
    required this.upData,
    required this.dynamicsController,
    this.showLiveSection = true,
  });

  final FollowUpModel upData;
  final DynamicsController dynamicsController;
  final bool showLiveSection;

  @override
  State<UpPanel> createState() => _UpPanelState();
}

class _UpPanelState extends State<UpPanel> {
  late final controller = widget.dynamicsController;
  late final isTop = controller.upPanelPosition == UpPanelPosition.top;

  void toFollowPage() => Get.to(const LiveFollowPage());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upData = widget.upData;
    final upList = upData.upList;
    final liveList = upData.liveUsers?.items;
    return CustomScrollView(
      scrollDirection: isTop ? .horizontal : .vertical,
      physics: const AlwaysScrollableScrollPhysics(),
      controller: controller.scrollController,
      slivers: [
        if (widget.showLiveSection)
          SliverToBoxAdapter(
            child: InkWell(
              onTap: () => setState(() {
                controller.showLiveUp = !controller.showLiveUp;
              }),
              onLongPress: toFollowPage,
              onSecondaryTap: PlatformUtils.isMobile ? null : toFollowPage,
              child: Container(
                alignment: .center,
                height: isTop ? Style.upPanelTopHeight : 60,
                padding: isTop ? const .only(left: 12, right: 6) : null,
                child: Text.rich(
                  textAlign: .center,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                  ),
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Live(${upData.liveUsers?.count ?? 0})',
                      ),
                      if (!isTop) ...[
                        const TextSpan(text: '\n'),
                        WidgetSpan(
                          alignment: .middle,
                          child: Icon(
                            controller.showLiveUp
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ] else
                        WidgetSpan(
                          alignment: .middle,
                          child: Icon(
                            controller.showLiveUp
                                ? Icons.keyboard_arrow_right
                                : Icons.keyboard_arrow_left,
                            color: theme.colorScheme.primary,
                            size: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (widget.showLiveSection &&
            controller.showLiveUp &&
            liveList != null &&
            liveList.isNotEmpty)
          SliverList.builder(
            itemCount: liveList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, liveList[index]);
            },
          ),
        SliverToBoxAdapter(
          child: upItemBuild(theme, UpItem(face: '', uname: '全部动态', mid: -1)),
        ),
        if (upList != null && upList.isNotEmpty)
          SliverList.builder(
            itemCount: upList.length,
            itemBuilder: (context, index) {
              return upItemBuild(theme, upList[index]);
            },
          ),
        if (!isTop) const SliverToBoxAdapter(child: SizedBox(height: 200)),
      ],
    );
  }

  void _onSelect(UpItem item) {
    item.hasUpdate = false;
    controller.onSelectUp(item.mid);
    setState(() {});
  }

  Widget upItemBuild(ThemeData theme, UpItem item) {
    final currentMid = controller.currentMid;
    final isLive = item is LiveUserItem;
    final isCurrent = isLive || currentMid == item.mid || currentMid == -1;

    final isAll = item.mid == -1;
    void toMemberPage() => Get.toNamed('/member?mid=${item.mid}');

    Widget avatar;
    if (isAll) {
      final bg = currentThemeColor();
      avatar = DecoratedBox(
        decoration: BoxDecoration(
          shape: .circle,
          color: bg,
        ),
        child: Image.asset(
          width: 38,
          height: 38,
          cacheWidth: 38.cacheSize(context),
          Assets.logo2,
          // 主题色过浅/近灰时，前景改用加深的主题色保证可读
          color: themeColorNeedsDarkFg(bg) ? bg.darken(0.5) : Colors.white,
        ),
      );
    } else {
      avatar = Padding(
        padding: const .symmetric(horizontal: 4),
        child: NetworkImgLayer(
          width: 38,
          height: 38,
          src: item.face,
          type: .avatar,
        ),
      );
      if (isLive) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            LiveAvatarBorder(child: avatar),
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
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  ),
                ),
              ),
            ),
          ],
        );
      } else if (item.hasUpdate ?? false) {
        avatar = Stack(
          clipBehavior: .none,
          children: [
            avatar,
            Positioned(
              top: 0,
              right: 4,
              child: Badge(
                smallSize: 8,
                backgroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        );
      }
    }

    return SizedBox(
      // 顶部模式 cell 宽高固定；左右模式高度随文字行数变化
      height: isTop ? Style.upPanelTopHeight : null,
      width: isTop ? 72 : null,
      child: InkWell(
        onTap: () {
          feedBack();
          if (isLive) {
            PageUtils.toLiveRoom(item.roomId);
          } else {
            _onSelect(item);
          }
        },
        // onDoubleTap: isLive ? () => _onSelect(data) : null,
        onLongPress: !isAll ? toMemberPage : null,
        onSecondaryTap: !isAll && !PlatformUtils.isMobile ? toMemberPage : null,
        child: Padding(
          // 顶部模式内容贴顶并留出圆环（向外扩展 2px）的余量；
          // 左右模式上下间距固定一致，cell 高度随内容动态变化
          padding: isTop
              ? const EdgeInsets.only(top: 4)
              : const EdgeInsets.symmetric(vertical: 4),
          child: Opacity(
            opacity: isCurrent ? 1 : 0.6,
            child: Column(
              // 顶部模式：所有 cell 间距统一为 12，文字上沿对齐直播项在同一高度；
              // 左右模式：直播项间距 12 使标签下沿到文字为 4px，
              // 非直播项（含全部动态）头像下沿到文字保持同样的 4px
              spacing: isTop || isLive ? 12 : 4,
              mainAxisSize: .min,
              children: [
                avatar,
                Padding(
                  padding: const .symmetric(horizontal: 4),
                  // 文字顶部对齐：单行/双行时距头像的距离一致
                  child: Text(
                    item.uname ?? '',
                    maxLines: 2,
                    textAlign: .center,
                    style: TextStyle(
                      color: currentMid == item.mid
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      height: 1.1,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
