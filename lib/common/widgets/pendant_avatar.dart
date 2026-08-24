import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/extra_hittest_stack.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/live_tag.dart';
import 'package:PiliPlus/models/common/avatar_badge_type.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_ui/material_ui.dart';

class PendantAvatar extends StatelessWidget {
  const PendantAvatar(
    this.url, {
    super.key,
    required double size,
    double? badgeSize,
    int? vipStatus,
    int? officialType,
    this.pendantImage,
    this.pendentOffset = 6,
    this.roomId,
    this.liveFontSize,
    this.onTap,
  }) : preferredSize = size,
       badgeSize = badgeSize ?? size / 3,
       badgeType = officialType == null || officialType < 0
           ? vipStatus != null && vipStatus > 0
                 ? .vip
                 : .none
           : officialType == 0
           ? .person
           : officialType == 1
           ? .institution
           : .none;

  static bool showDecorate = Pref.showDecorate;

  final BadgeType badgeType;
  final String? url;
  final double preferredSize;
  final double badgeSize;
  final String? pendantImage;
  final double pendentOffset;
  final int? roomId;
  final double? liveFontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showPendant = showDecorate && pendantImage?.isNotEmpty == true;
    final size = showPendant ? preferredSize - pendentOffset : preferredSize;
    Widget? pendant;
    if (showPendant) {
      final pendantSize = size * 1.75;
      pendant = Positioned(
        // -(size * 1.75 - size) / 2
        top: -0.375 * size + pendentOffset / 2,
        child: IgnorePointer(
          child: NetworkImgLayer(
            type: .emote,
            width: pendantSize,
            height: pendantSize,
            src: pendantImage,
            getPlaceHolder: () => const SizedBox.shrink(),
          ),
        ),
      );
    }
    Widget avatar = NetworkImgLayer(
      src: url,
      width: size,
      height: size,
      type: ImageType.avatar,
    );
    if (onTap != null) {
      avatar = GestureDetector(
        behavior: .opaque,
        onTap: onTap,
        child: avatar,
      );
    }
    // 直播中且没有个性头像框时，加一圈与直播标签同主题色的边框
    if (roomId != null && !showPendant) {
      avatar = liveAvatarBorder(color: currentThemeColor(), child: avatar);
    }
    Widget child = ExtraHitTestStack(
      clipBehavior: .none,
      alignment: .center,
      children: [
        avatar,
        ?pendant,
        if (roomId != null)
          _buildLive(showPendant)
        else if (badgeType != .none)
          _buildBadge(context, colorScheme),
      ],
    );
    if (showPendant) {
      return SizedBox.square(
        dimension: preferredSize,
        child: child,
      );
    }
    return child;
  }

  Widget _buildLive(bool showPendant) {
    return Positioned(
      left: 0,
      right: 0,
      // 头像底部的中心点与标签中心点重叠；
      // 有头像框时头像相对容器整体上移了 pendentOffset/2，需同步抬高
      bottom: showPendant ? pendentOffset / 2 : 0,
      child: Center(
        child: FractionalTranslation(
          translation: const Offset(0, 0.5),
          child: GestureDetector(
            onTap: () => PageUtils.toLiveRoom(roomId),
            child: LiveTag(fontSize: liveFontSize ?? 13),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, ColorScheme colorScheme) {
    final child = switch (badgeType) {
      .vip => SvgPicture.asset(
        Assets.vipIcon,
        width: badgeSize,
        height: badgeSize,
        semanticsLabel: badgeType.desc,
      ),
      _ => Icon(
        Icons.offline_bolt,
        color: badgeType.color,
        size: badgeSize,
        semanticLabel: badgeType.desc,
      ),
    };
    return Positioned(
      right: 0.0,
      bottom: 0.0,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.surface,
          ),
          child: child,
        ),
      ),
    );
  }
}
