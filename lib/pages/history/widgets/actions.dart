import 'package:PiliPlus/http/search.dart';
import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/video/video_detail/dimension.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// 打开一条观看记录（与观看记录页点击行为一致）
Future<void> openHistoryItem(HistoryItemModel item) async {
  final business = item.history.business;
  if (business?.contains('article') == true) {
    PageUtils.toDupNamed(
      '/articlePage',
      parameters: {
        'id': business == 'article-list'
            ? '${item.history.cid}'
            : '${item.history.oid}',
        'type': 'read',
      },
    );
  } else if (business == 'live') {
    if (item.liveStatus == 1) {
      PageUtils.toLiveRoom(item.history.oid);
    } else {
      SmartDialog.showToast('直播未开播');
    }
  } else if (business == 'pgc') {
    PageUtils.viewPgc(
      epId: item.history.epid,
      progress: item.playbackProgress,
    );
  } else if (business == 'cheese') {
    if (item.uri?.isNotEmpty == true) {
      PageUtils.viewPgcFromUri(
        item.uri!,
        isPgc: false,
        aid: item.history.oid,
        progress: item.playbackProgress,
      );
    }
  } else {
    final aid = item.history.oid!;
    final bvid = item.history.bvid ?? IdUtils.av2bv(aid);
    int? cid = item.history.cid;
    Dimension? dimension;
    if (cid == null) {
      if (await SearchHttp.ab2cWithDimension(
            aid: aid,
            bvid: bvid,
            part: item.history.page,
          )
          case final res?) {
        cid = res.cid;
        dimension = res.dimension;
      }
    }
    if (cid != null) {
      // TODO: dimension
      PageUtils.toVideoPage(
        aid: aid,
        bvid: bvid,
        cid: cid,
        cover: item.cover,
        title: item.title,
        dimension: dimension,
        progress: item.playbackProgress,
      );
    }
  }
}

/// 观看记录项的功能菜单（与观看记录页三点菜单一致）
List<PopupMenuEntry<void>> buildHistoryItemMenu(
  HistoryItemModel item,
  VoidCallback onDelete,
) {
  final business = item.history.business;
  return [
    if (item.authorMid != null && item.authorName?.isNotEmpty == true)
      PopupMenuItem(
        onTap: () => Get.toNamed('/member?mid=${item.authorMid}'),
        height: 38,
        child: Row(
          children: [
            const Icon(MdiIcons.accountCircleOutline, size: 16),
            const SizedBox(width: 6),
            Text(
              '访问：${item.authorName}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    if (business != 'pgc' &&
        item.badge != '番剧' &&
        item.tagName?.contains('动画') != true &&
        business != 'live' &&
        business?.contains('article') != true)
      PopupMenuItem(
        onTap: () => UserHttp.toViewLater(bvid: item.history.bvid),
        height: 38,
        child: const Row(
          children: [
            Icon(Icons.watch_later_outlined, size: 16),
            SizedBox(width: 6),
            Text('稍后再看', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    PopupMenuItem(
      onTap: onDelete,
      height: 38,
      child: const Row(
        children: [
          Icon(Icons.close_outlined, size: 16),
          SizedBox(width: 6),
          Text('删除记录', style: TextStyle(fontSize: 13)),
        ],
      ),
    ),
  ];
}
