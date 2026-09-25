import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/dialog/report.dart';
import 'package:PiliPlus/common/widgets/focus/tv_focus_on_open.dart';
import 'package:PiliPlus/common/widgets/pendant_avatar.dart';
import 'package:PiliPlus/common/widgets/translucent_row.dart';
import 'package:PiliPlus/http/constants.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/save_panel/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/color_utils.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/request_utils.dart';
import 'package:PiliPlus/utils/share_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class AuthorPanel extends StatelessWidget {
  final DynamicItemModel item;
  final bool isSave;
  final bool isDetail;
  final ValueChanged<Object>? onRemove;
  final void Function(bool isTop, Object dynId)? onSetTop;
  final VoidCallback? onBlock;
  final Future<LoadingState> Function(bool isPrivate, Object dynId)?
  onSetPubSetting;
  final VoidCallback? onEdit;
  final ValueChanged<int>? onSetReplySubject;

  const AuthorPanel({
    super.key,
    required this.item,
    this.isDetail = false,
    this.onRemove,
    this.isSave = false,
    this.onSetTop,
    this.onBlock,
    this.onSetPubSetting,
    this.onEdit,
    this.onSetReplySubject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moduleAuthor = item.modules.moduleAuthor!;
    final pubTime = moduleAuthor.pubTs != null
        ? isSave
              ? DateFormatUtils.format(
                  moduleAuthor.pubTs,
                  format: DateFormatUtils.longFormatDs,
                )
              : DateFormatUtils.dateFormat(moduleAuthor.pubTs)
        : moduleAuthor.pubTime;
    Widget? pubTs;
    if (pubTime != null) {
      pubTs = Text(
        '$pubTime${moduleAuthor.pubAction != null ? ' ${moduleAuthor.pubAction}' : ''}',
        style: TextStyle(
          color: theme.colorScheme.outline,
          fontSize: theme.textTheme.labelSmall!.fontSize,
        ),
      );
      if (moduleAuthor.badgeText case final badgeText?) {
        pubTs = Row(
          mainAxisSize: .min,
          spacing: 5,
          children: [
            pubTs,
            Text(
              badgeText,
              style: TextStyle(
                color: theme.colorScheme.secondary,
                fontSize: theme.textTheme.labelSmall!.fontSize,
              ),
            ),
          ],
        );
      }
    }
    final children = [
      PendantAvatar(
        size: 40,
        moduleAuthor.face,
        pendantImage: moduleAuthor.pendant?.image,
      ),
      Flexible(
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Text(
              moduleAuthor.name!,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(
                color:
                    moduleAuthor.vip != null &&
                        moduleAuthor.vip!.status > 0 &&
                        moduleAuthor.vip!.type == 2
                    ? theme.colorScheme.vipColor
                    : theme.colorScheme.onSurface,
                fontSize: theme.textTheme.titleSmall!.fontSize,
              ),
            ),
            ?pubTs,
          ],
        ),
      ),
    ];
    Widget header;
    if (moduleAuthor.type == 'AUTHOR_TYPE_NORMAL') {
      header = GestureDetector(
        onTap: () => {
          feedBack(),
          Get.toNamed('/member?mid=${moduleAuthor.mid}'),
        },
        child: TranslucentRow(
          spacing: 10,
          extraWidth: 50,
          children: children,
        ),
      );
    } else {
      header = Row(spacing: 10, children: children);
    }
    // 「遥控器适配」下外部动态卡片不显示「更多」：卡片只要一个焦点
    // （菜单本身还在，长按确定仍然打得开）
    Widget? moreBtn = isSave || (!isDetail && Pref.remoteAdaptation)
        ? null
        : SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              tooltip: '更多',
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
              ),
              onPressed: () => morePanel(context),
              icon: const Icon(Icons.more_vert_outlined, size: 18),
            ),
          );
    final moduleTagText = !isDetail ? item.modules.moduleTag?.text : null;
    if (moduleTagText != null) {
      header = Row(
        children: [
          Expanded(child: header),
          Container(
            padding: const .symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: const .all(.circular(4)),
              border: .all(width: 1.25, color: theme.colorScheme.primary),
            ),
            child: Text(
              moduleTagText,
              style: TextStyle(
                height: 1,
                fontSize: 12,
                color: theme.colorScheme.primary,
              ),
              strutStyle: const StrutStyle(height: 1, leading: 0, fontSize: 12),
            ),
          ),
          ?moreBtn,
        ],
      );
    } else if (moduleAuthor.decorate != null) {
      const height = 32.0;
      header = Stack(
        clipBehavior: .none,
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: CachedNetworkImage(
                height: height,
                memCacheHeight: height.cacheSize(context),
                imageUrl: ImageUtils.safeThumbnailUrl(
                  moduleAuthor.decorate!.cardUrl,
                ),
                placeholder: (_, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          if (moduleAuthor.decorate!.fan?.numStr?.isNotEmpty == true)
            Positioned(
              top: 0,
              bottom: 0,
              right: height,
              child: Center(
                child: Text(
                  moduleAuthor.decorate!.fan!.numStr!.toString(),
                  style: TextStyle(
                    height: 1,
                    fontSize: 11,
                    fontFamily: Assets.digitalNum,
                    color: ColourUtils.parseColor(
                      moduleAuthor.decorate!.fan!.color!,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const .only(right: 80),
            child: header,
          ),
        ],
      );
      if (moreBtn != null) {
        header = Row(
          children: [
            Expanded(child: header),
            moreBtn,
          ],
        );
      }
    } else if (moreBtn != null) {
      header = Row(
        children: [
          Expanded(child: header),
          moreBtn,
        ],
      );
    }
    return header;
  }

  /// 卡片的「更多」菜单。
  ///
  /// 和视频卡的「更多」（`VideoPopupMenu.show`）同一个样式：`showMenu` 的浮层
  /// 菜单，锚在作者栏（那颗「更多」按钮所在的那一行）的中心上——传进来的
  /// `context` 就是本控件的 build context，它的渲染盒即作者栏。手柄 / 遥控器
  /// 没有指针位置，锚点只能这么算。`requestFocus` 必须给：不给的话菜单弹出来了、
  /// 焦点还留在列表上，方向键和确定键全被列表吃掉（看得见、按不着）。
  ///
  /// 面板项都是 `PopupMenuItem`：它的 `handleTap` 会**先关菜单再执行 onTap**，
  /// 所以每一项里不用再写 `Get.back()`——那关掉的是整个页面。
  /// 项里再 `showDialog` 是安全的（弹出时菜单已经关了）。
  void morePanel(BuildContext context) {
    String? bvid;
    try {
      String? getBvid(String? type, DynamicMajorModel? major) => switch (type) {
        'DYNAMIC_TYPE_AV' => major?.archive?.bvid,
        'DYNAMIC_TYPE_UGC_SEASON' => major?.ugcSeason?.bvid,
        _ => null,
      };
      bvid = getBvid(item.type, item.modules.moduleDynamic?.major);
      if (bvid == null && item.orig != null) {
        bvid = getBvid(
          item.orig!.type,
          item.orig!.modules.moduleDynamic?.major,
        );
      }
    } catch (_) {}

    final theme = Theme.of(context);
    final moduleAuthor = item.modules.moduleAuthor!;
    final error = theme.colorScheme.error;
    final box = context.findRenderObject();
    final offset = box is RenderBox && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset.zero;

    PopupMenuItem<void> action(
      String title,
      IconData icon,
      VoidCallback onTap, {
      Color? color,
    }) => PopupMenuItem<void>(
      height: 45,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );

    showMenu<void>(
      context: context,
      position: PageUtils.menuPosition(offset),
      requestFocus: Pref.tvFocus,
      items: [
        if (bvid != null)
          action(
            '稍后再看',
            Icons.watch_later_outlined,
            () => UserHttp.toViewLater(bvid: bvid),
          ),
        action(
          '保存动态',
          Icons.save_alt,
          () => SavePanel.toSavePanel(item: item),
        ),
        action(
          '分享动态',
          Icons.share_outlined,
          () => ShareUtils.shareText('${HttpString.opusBaseUrl}/${item.idStr}'),
        ),
        if ((item.basic!.commentType == 17 || item.basic!.commentType == 11) &&
            item.modules.moduleDynamic?.major?.blocked == null)
          action('分享至消息', Icons.forward_to_inbox, () {
            try {
              bool isDyn = item.basic!.commentType == 17;
              String id = isDyn ? item.idStr : item.basic!.ridStr!;
              int source = isDyn ? 11 : 2;
              final moduleDynamic = item.modules.moduleDynamic!;
              final title =
                  moduleDynamic.desc?.text ??
                  moduleDynamic.major!.opus!.summary!.text!;
              String? thumb = isDyn
                  ? moduleAuthor.face
                  : moduleDynamic.major?.opus?.pics?.firstOrNull?.url;
              PageUtils.pmShare(
                context,
                content: {
                  "id": id,
                  "title": title,
                  "headline": "",
                  "source": source,
                  if (thumb?.isNotEmpty == true) "thumb": thumb,
                  "author": moduleAuthor.name,
                  "author_id": moduleAuthor.mid.toString(),
                },
              );
            } catch (e) {
              SmartDialog.showToast(e.toString());
            }
          }),
        action('临时屏蔽：${moduleAuthor.name}', Icons.visibility_off_outlined, () {
          onBlock?.call();
          try {
            Get.find<DynamicsController>().tempBannedList.add(
              moduleAuthor.mid!,
            );
            SmartDialog.showToast(
              '已临时屏蔽${moduleAuthor.name}(${moduleAuthor.mid!})，重启恢复',
            );
          } catch (_) {}
        }),
        if (kDebugMode || moduleAuthor.mid == Accounts.main.mid) ...[
          action(
            '检查动态',
            CustomIcons.shield_published,
            () => RequestUtils.checkCreatedDyn(id: item.idStr, isManual: true),
          ),
          if (onSetTop != null)
            action(
              '${moduleAuthor.isTop == true ? '取消' : ''}置顶',
              Icons.vertical_align_top,
              () => onSetTop!(moduleAuthor.isTop ?? false, item.idStr),
            ),
          if (onSetReplySubject != null)
            action('互动设置', Icons.mark_unread_chat_alt_outlined, () async {
              final res = await ReplyHttp.replyInteraction(
                oid: item.basic!.commentIdStr!,
                type: item.basic!.commentType!,
              );
              if (res case Success(:final response)) {
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (context) {
                      final selection = response.upReplySelection;
                      final enableSelection = selection.status == 1;

                      final reply = response.upReply;
                      final enableReply = reply.status == 1;

                      return TvFocusOnOpen(
                        child: SimpleDialog(
                          clipBehavior: .hardEdge,
                          contentPadding: const .symmetric(vertical: 12),
                          children: [
                            ListTile(
                              dense: true,
                              enabled: selection.canModify,
                              title: Text(
                                '${enableSelection ? '停止' : '开启'}评论精选',
                                style: const TextStyle(fontSize: 14),
                              ),
                              onTap: () {
                                Get.back();
                                onSetReplySubject!(enableSelection ? 2 : 1);
                              },
                            ),
                            ListTile(
                              dense: true,
                              enabled: reply.canModify,
                              title: Text(
                                '${enableReply ? '关闭' : '恢复'}评论',
                                style: const TextStyle(fontSize: 14),
                              ),
                              onTap: () {
                                Get.back();
                                onSetReplySubject!(enableReply ? 3 : 4);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }
              } else {
                res.toast();
              }
            }),
          if (onSetPubSetting != null)
            action('可见范围', Icons.visibility, () {
              final isPrivate = moduleAuthor.badgeText != null;
              Future<void> onTap() async {
                Get.back();
                if ((await onSetPubSetting!(
                  isPrivate,
                  item.idStr,
                )).isSuccess) {
                  if (context.mounted) {
                    (context as Element).markNeedsBuild();
                  }
                }
              }

              showDialog(
                context: context,
                builder: (context) => TvFocusOnOpen(
                  child: SimpleDialog(
                    clipBehavior: Clip.hardEdge,
                    contentPadding: const .symmetric(vertical: 12),
                    children: [
                      ListTile(
                        dense: true,
                        enabled: isPrivate,
                        title: const Text(
                          '所有用户可见',
                          style: TextStyle(fontSize: 14),
                        ),
                        onTap: onTap,
                      ),
                      ListTile(
                        dense: true,
                        enabled: !isPrivate,
                        title: const Text(
                          '仅自己可见',
                          style: TextStyle(fontSize: 14),
                        ),
                        onTap: onTap,
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (onEdit != null) action('编辑动态', Icons.edit_note, () => onEdit!()),
          if (onRemove != null)
            action('删除', Icons.delete_outline, () {
              showDialog(
                context: context,
                builder: (context) => TvFocusOnOpen(
                  child: AlertDialog(
                    title: const Text('确定删除该动态?'),
                    actions: [
                      TextButton(
                        onPressed: Get.back,
                        child: Text(
                          '取消',
                          style: TextStyle(color: error),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Get.back();
                          onRemove!(item.idStr);
                        },
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ),
              );
            }, color: error),
        ],
        if (Accounts.main.isLogin)
          action('举报', Icons.error_outline_outlined, () {
            autoWrapReportDialog(
              context,
              ReportOptions.dynamicReport,
              (reasonType, reasonDesc, banUid) {
                if (banUid) {
                  VideoHttp.relationMod(
                    mid: moduleAuthor.mid!,
                    act: 5,
                    reSrc: 11,
                  );
                }
                return UserHttp.dynamicReport(
                  mid: moduleAuthor.mid!,
                  dynId: item.idStr,
                  reasonType: reasonType,
                  reasonDesc: reasonDesc,
                );
              },
            );
          }, color: error),
      ],
    );
  }
}
