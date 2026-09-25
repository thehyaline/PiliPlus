import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/avatars.dart';
import 'package:PiliPlus/common/widgets/focus/tv_card.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/widgets/action_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/author_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dyn_content.dart';
import 'package:PiliPlus/pages/dynamics/widgets/interaction.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 「遥控器适配」下卡片底部的收尾间距（见 [DynamicPanel._tailBleeds]）。
const double _remoteTailGap = 12;

class DynamicPanel extends StatelessWidget {
  final DynamicItemModel item;
  final bool isDetail;
  final ValueChanged<Object>? onRemove;
  final bool isSave;
  final void Function(bool isTop, Object dynId)? onSetTop;
  final VoidCallback? onBlock;
  final VoidCallback? onUnfold;
  final bool isDetailPortraitW;
  final Future<LoadingState> Function(bool isPrivate, Object dynId)?
  onSetPubSetting;
  final VoidCallback? onEdit;
  final ValueChanged<int>? onSetReplySubject;

  const DynamicPanel({
    super.key,
    required this.item,
    this.isDetail = false,
    this.onRemove,
    this.isSave = false,
    this.onSetTop,
    this.onBlock,
    this.onUnfold,
    this.isDetailPortraitW = true,
    this.onSetPubSetting,
    this.onEdit,
    this.onSetReplySubject,
  });

  @override
  Widget build(BuildContext context) {
    /// 「遥控器适配」：外部动态卡片退回"一条动态一个焦点"——
    /// 卡里的更多 / 转发 / 评论 / 点赞不再显示，卡片内部也没有任何焦点，
    /// 方向键只在卡片之间跳，确定键直接进视频 / 动态详情（`showMore` 还在，
    /// 长按仍然能打开「更多」）。详情页和触摸操作都不受影响。
    final remote = !isDetail && Pref.remoteAdaptation;

    // 折叠进去的同批动态（接口给的 `visible == false` 那几条）：开着「遥控器适配」
    // 时卡里没有「更多」，卡内元素也不在焦点树上，「展开x条相关动态」根本点不到，
    // 于是直接把它们放出来——等价于默认展开。
    if (item.visible == false && !remote) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final authorWidget = AuthorPanel(
      item: item,
      isDetail: isDetail,
      onRemove: onRemove,
      isSave: isSave,
      onSetTop: onSetTop,
      onBlock: onBlock,
      onSetPubSetting: onSetPubSetting,
      onEdit: onEdit,
      onSetReplySubject: onSetReplySubject,
    );

    void showMore() => authorWidget.morePanel(context);

    // 「展开x条相关动态」这一行：开着「遥控器适配」就不展示（折叠的同批动态
    // 已经在上面放出来了），留着也是点不到的装饰。
    final fold = remote ? null : item.modules.moduleFold;

    // 卡片外表交给 TvCard：surface 在 FocusRing **里面**，
    // 聚焦时的缩放才会连背景一起放大（包在 TvCard 外面就只有内容在放大）。
    final cardSurface = isSave || isDetail
        ? null
        : (Widget child) => Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: child,
          );

    final child = TvCard(
      debugLabel: '动态',
      surface: cardSurface,
      onTap:
          isDetail &&
              !const {
                'DYNAMIC_TYPE_AV',
                'DYNAMIC_TYPE_UGC_SEASON',
                'DYNAMIC_TYPE_PGC_UNION',
                'DYNAMIC_TYPE_PGC',
                'DYNAMIC_TYPE_LIVE',
                'DYNAMIC_TYPE_LIVE_RCMD',
                'DYNAMIC_TYPE_MEDIALIST',
                'DYNAMIC_TYPE_COURSES_SEASON',
              }.contains(item.type)
          ? null
          : () => PageUtils.pushDynDetail(item),
      onLongPress: showMore,
      // 手柄：长按确定 = 长按（作者面板里那个「更多」）
      onMore: showMore,
      onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
      child: ExcludeFocus(
        excluding: remote,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: authorWidget,
            ),
            if (item.modules.moduleDispute case final moduleDispute?)
              _buildDispute(theme, moduleDispute),
            ...dynContent(
              context,
              theme: theme,
              isSave: isSave,
              isDetail: isDetail,
              item: item,
              floor: 1,
            ),
            const SizedBox(height: 2),
            if (!isDetail) ...[
              if (item.modules.moduleInteraction case ModuleInteraction(
                :final items,
              ))
                if (items != null && items.isNotEmpty)
                  dynInteraction(
                    theme: theme,
                    items: items,
                  ),
              if (!remote)
                ActionPanel(item: item)
              else if (_tailBleeds)
                const SizedBox(height: _remoteTailGap),
              if (fold case final moduleFold?) ...[
                Divider(
                  height: 1,
                  color: theme.dividerColor.withValues(alpha: 0.1),
                ),
                _buildFoldItem(theme, moduleFold),
              ],
            ] else if (!isSave)
              const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (isSave || (isDetail && !isDetailPortraitW)) {
      return child;
    }
    // 详情页竖屏 / 列表卡片：背景已经在 surface 里，这里只留底部间距
    return Padding(
      padding: const EdgeInsets.only(bottom: Style.waterfallMargin),
      child: child,
    );
  }

  /// 卡片最后一块内容是不是"贴边"的（自己没底色、没下内边距）。
  ///
  /// 「遥控器适配」把 `ActionPanel` 撤掉以后，卡片底边由最后一块内容收尾：
  /// 图文图片、视频封面+标题这类内容直接贴到卡片下边缘，比转发原动态
  /// （灰底 `Container`，`vertical: 8`）、视频预约之类的 additional 面板
  /// （底色 + `vertical: 10`）看着挤，所以给它们补一段 [_remoteTailGap] 找齐。
  bool get _tailBleeds {
    if (item.modules.moduleDynamic?.additional != null) {
      return false;
    }
    return switch (item.type) {
      // 转发：原动态套在灰底 Container 里，自带底色和内边距
      'DYNAMIC_TYPE_FORWARD' ||
      // 音乐 / 活动：整块是带底色的 Material
      'DYNAMIC_TYPE_MUSIC' ||
      'DYNAMIC_TYPE_COMMON_SQUARE' => false,
      _ => true,
    };
  }

  Widget _buildFoldItem(ThemeData theme, ModuleFold moduleFold) {
    Widget child = Text.rich(
      textAlign: TextAlign.center,
      style: TextStyle(
        height: 1,
        fontSize: 13,
        color: theme.colorScheme.outline,
      ),
      strutStyle: const StrutStyle(
        height: 1,
        leading: 0,
        fontSize: 13,
      ),
      TextSpan(
        children: [
          TextSpan(text: moduleFold.statement ?? '展开'),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(
              size: 19,
              Icons.keyboard_arrow_down,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
    final users = moduleFold.users;
    if (users != null && users.isNotEmpty) {
      child = Row(
        spacing: 5,
        mainAxisAlignment: .center,
        children: [
          avatars(colorScheme: theme.colorScheme, users: users),
          child,
        ],
      );
    }
    return InkWell(
      onTap: onUnfold,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: child,
      ),
    );
  }

  Widget _buildDispute(ThemeData theme, ModuleDispute moduleDispute) {
    final child = Container(
      width: .infinity,
      margin: const .fromLTRB(12, 2, 12, 6),
      padding: const .symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(
          alpha: theme.isLight ? 0.5 : 0.7,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Text.rich(
        style: TextStyle(
          height: 1,
          fontSize: 13,
          color: theme.colorScheme.onSecondaryContainer,
        ),
        strutStyle: const StrutStyle(
          leading: 0,
          height: 1,
          fontSize: 13,
        ),
        TextSpan(
          children: [
            WidgetSpan(
              alignment: .middle,
              child: Padding(
                padding: const .only(right: 4),
                child: Icon(
                  size: 15,
                  Icons.warning_rounded,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextSpan(text: moduleDispute.title),
          ],
        ),
      ),
    );
    if (moduleDispute.jumpUrl?.isNotEmpty == true) {
      return GestureDetector(
        onTap: () => PageUtils.handleWebview(moduleDispute.jumpUrl!),
        child: child,
      );
    }
    return child;
  }
}
