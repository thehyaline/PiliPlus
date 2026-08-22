import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/models/common/badge_type.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/history/widgets/actions.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

/// “我的”页观看记录板块的横向卡片
class MineHistoryItem extends StatelessWidget {
  final HistoryItemModel item;
  final VoidCallback onDelete;

  const MineHistoryItem({super.key, required this.item, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorName = item.authorName;
    final timeText = DateFormatUtils.chatFormat(item.viewAt, isHistory: true);
    final hasDuration = item.duration != null && item.duration != 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openHistoryItem(item),
      onLongPressStart: (details) {
        Feedback.forLongPress(context);
        _showMenu(context, details.globalPosition);
      },
      onSecondaryTapDown: PlatformUtils.isMobile
          ? null
          : (details) => _showMenu(context, details.globalPosition),
      child: SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                NetworkImgLayer(
                  src: item.cover?.isNotEmpty == true
                      ? item.cover
                      : item.covers?.firstOrNull ?? '',
                  width: 180,
                  height: 110,
                ),
                if (hasDuration)
                  PBadge(
                    text: item.progress == -1
                        ? '已看完'
                        : '${DurationUtils.formatDuration(item.progress)}/${DurationUtils.formatDuration(item.duration)}',
                    right: 6.0,
                    bottom: 8.0,
                    type: PBadgeType.gray,
                  ),
                if (item.history.business == 'live' && item.liveStatus == 1)
                  const PBadge(
                    text: '直播中',
                    top: 6.0,
                    right: 6.0,
                    type: PBadgeType.primary,
                  )
                else if (item.history.business == 'live')
                  PBadge(
                    text: item.badge?.isNotEmpty == true
                        ? item.badge!
                        : '未开播',
                    top: 6.0,
                    right: 6.0,
                    type: PBadgeType.gray,
                  )
                else if (item.isFav == 1)
                  const PBadge(
                    text: '已收藏',
                    top: 6.0,
                    right: 6.0,
                    type: PBadgeType.gray,
                  )
                else if (item.badge?.isNotEmpty == true)
                  PBadge(
                    text: item.badge!,
                    top: 6.0,
                    right: 6.0,
                    type: PBadgeType.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              ' ${item.title}',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              authorName?.isNotEmpty == true
                  ? '$authorName · $timeText'
                  : timeText,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.labelSmall!.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, Offset offset) {
    showMenu<void>(
      context: context,
      position: PageUtils.menuPosition(offset),
      items: buildHistoryItemMenu(item, onDelete),
    );
  }
}
