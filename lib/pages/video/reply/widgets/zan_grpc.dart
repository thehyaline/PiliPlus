import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo;
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/num_utils.dart';
import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';

/// 评论的赞 / 踩。
///
/// 从 [ZanButtonGrpc] 里提出来是因为手柄模式下**一条评论只留一个焦点节点**，
/// 卡片上这两个按钮不在焦点树里（见 `reply_item_grpc.dart`），
/// 它们改由「长按确定 / 手柄 Y 键」弹出的操作面板调用——两个入口共用一个实现。
abstract final class ZanActions {
  /// 一次只发一个请求。原来靠按钮 `build` 里的局部 bool 挡住重复点击，
  /// 面板那边没有这个作用域，就挪上来当全局闸门。
  static bool _processing = false;

  static bool isLiked(ReplyInfo replyItem) =>
      replyItem.replyControl.action == $fixnum.Int64.ONE;

  static bool isDisliked(ReplyInfo replyItem) =>
      replyItem.replyControl.action == $fixnum.Int64.TWO;

  // 评论点赞
  static Future<void> like(
    BuildContext context,
    ReplyInfo replyItem, {
    required bool isLike,
  }) async {
    if (_processing) {
      return;
    }
    _processing = true;
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    // 1 已点赞 2 不喜欢 0 未操作
    final int action = isLike ? 0 : 1;
    final res = await ReplyHttp.likeReply(
      type: replyItem.type.toInt(),
      oid: oid,
      rpid: rpid,
      action: action,
    );
    if (res.isSuccess) {
      SmartDialog.showToast(isLike ? '取消赞' : '点赞成功');
      if (action == 1) {
        replyItem
          ..like += $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ONE;
      } else {
        replyItem
          ..like -= $fixnum.Int64.ONE
          ..replyControl.action = $fixnum.Int64.ZERO;
      }
      if (context.mounted) {
        (context as Element?)?.markNeedsBuild();
      }
    } else {
      res.toast();
    }
    _processing = false;
  }

  static Future<void> hate(
    BuildContext context,
    ReplyInfo replyItem, {
    required bool isDislike,
  }) async {
    if (_processing) {
      return;
    }
    _processing = true;
    feedBack();
    final int oid = replyItem.oid.toInt();
    final int rpid = replyItem.id.toInt();
    // 1 已点赞 2 不喜欢 0 未操作
    final int action = isDislike ? 0 : 2;
    final res = await ReplyHttp.hateReply(
      type: replyItem.type.toInt(),
      action: action == 2 ? 1 : 0,
      oid: oid,
      rpid: rpid,
    );
    if (res.isSuccess) {
      SmartDialog.showToast(isDislike ? '取消踩' : '点踩成功');
      if (action == 2) {
        replyItem.replyControl.action = $fixnum.Int64.TWO;
      } else {
        replyItem.replyControl.action = $fixnum.Int64.ZERO;
      }
      if (context.mounted) {
        (context as Element?)?.markNeedsBuild();
      }
    } else {
      res.toast();
    }
    _processing = false;
  }
}

class ZanButtonGrpc extends StatelessWidget {
  const ZanButtonGrpc({
    super.key,
    required this.replyItem,
  });

  final ReplyInfo replyItem;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final isLike = ZanActions.isLiked(replyItem);
    final isDislike = ZanActions.isDisliked(replyItem);
    final outline = theme.colorScheme.outline;
    final primary = theme.colorScheme.primary;
    final ButtonStyle style = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 32,
          child: TextButton(
            style: const ButtonStyle(
              visualDensity: .compact,
              tapTargetSize: .shrinkWrap,
              padding: WidgetStatePropertyAll(.zero),
              minimumSize: WidgetStatePropertyAll(.square(40)),
            ),
            onPressed: () =>
                ZanActions.hate(context, replyItem, isDislike: isDislike),
            child: Icon(
              isDislike
                  ? FontAwesomeIcons.solidThumbsDown
                  : FontAwesomeIcons.thumbsDown,
              size: 16,
              color: isDislike ? primary : outline,
              semanticLabel: isDislike ? '已踩' : '点踩',
            ),
          ),
        ),
        SizedBox(
          height: 32,
          child: TextButton(
            style: style,
            onPressed: () =>
                ZanActions.like(context, replyItem, isLike: isLike),
            child: Row(
              spacing: 4,
              children: [
                Icon(
                  isLike
                      ? FontAwesomeIcons.solidThumbsUp
                      : FontAwesomeIcons.thumbsUp,
                  size: 16,
                  color: isLike ? primary : outline,
                  semanticLabel: isLike ? '已赞' : '点赞',
                ),
                Text(
                  NumUtils.numFormat(replyItem.like.toInt()),
                  style: TextStyle(
                    color: isLike ? primary : outline,
                    fontSize: theme.textTheme.labelSmall!.fontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
