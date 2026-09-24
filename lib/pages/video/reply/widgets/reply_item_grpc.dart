import 'dart:math';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/badge.dart';
import 'package:PiliPlus/common/widgets/custom_icon.dart';
import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/common/widgets/dialog/report.dart';
import 'package:PiliPlus/common/widgets/focus/tv_card.dart';
import 'package:PiliPlus/common/widgets/focus/tv_focus_on_open.dart';
import 'package:PiliPlus/common/widgets/gesture/tap_gesture_recognizer.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/image_grid/image_grid_view.dart';
import 'package:PiliPlus/common/widgets/pendant_avatar.dart';
import 'package:PiliPlus/common/widgets/text_ellipsis/text_ellipsis.dart';
import 'package:PiliPlus/common/widgets/text_more/text_more.dart';
import 'package:PiliPlus/common/widgets/translucent_row.dart';
import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show ReplyInfo, ReplyControl, Content, Url, ReplyControl_VoteOption, Emote;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/reply.dart';
import 'package:PiliPlus/http/video.dart';
import 'package:PiliPlus/models/common/image_type.dart';
import 'package:PiliPlus/pages/dynamics/widgets/vote.dart';
import 'package:PiliPlus/pages/member/widget/medal_widget.dart';
import 'package:PiliPlus/pages/save_panel/view.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/reply/widgets/zan_grpc.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/bili_utils.dart';
import 'package:PiliPlus/utils/color_utils.dart';
import 'package:PiliPlus/utils/danmaku_utils.dart';
import 'package:PiliPlus/utils/date_utils.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:PiliPlus/utils/extension/selectable_region_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/global_data.dart';
import 'package:PiliPlus/utils/image_utils.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/theme_utils.dart';
import 'package:PiliPlus/utils/url_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:protobuf/protobuf.dart';

part 'package:PiliPlus/common/widgets/context_menu/reply_menu_helper.dart';

class ReplyItemGrpc extends StatelessWidget {
  const ReplyItemGrpc({
    super.key,
    required this.replyItem,
    required this.replyLevel,
    this.replyReply,
    this.needDivider = true,
    this.onReply,
    this.onDelete,
    this.upMid,
    this.showDialogue,
    this.getTag,
    this.onViewImage,
    this.onCheckReply,
    this.onToggleTop,
    this.jumpToDialogue,
  });
  final ReplyInfo replyItem;
  final int replyLevel;
  final Function(ReplyInfo replyItem, int? rpid)? replyReply;
  final bool needDivider;
  final ValueChanged<ReplyInfo>? onReply;
  final Function(ReplyInfo replyItem, int? subIndex)? onDelete;
  final Int64? upMid;
  final VoidCallback? showDialogue;
  final Function? getTag;
  final VoidCallback? onViewImage;
  final ValueChanged<ReplyInfo>? onCheckReply;
  final ValueChanged<ReplyInfo>? onToggleTop;
  final VoidCallback? jumpToDialogue;

  static final _voteRegExp = RegExp(r"^\{vote:\d+?\}$");
  static final _timeRegExp = RegExp(r'^(?:\d+[:：])?\d+[:：]\d+$');
  static bool enableWordRe = Pref.enableWordRe;
  static int? replyLengthLimit = Pref.replyLengthLimit;

  /// 一次只翻一条（原来靠按钮 `build` 里的局部 bool，见 [toggleTranslation]）
  static bool _translating = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    void showMore() => _openMorePanel(
      context: context,
      item: replyItem,
      onDelete: () => onDelete?.call(replyItem, null),
      isSubReply: false,
    );

    Widget child = Padding(
      padding: const .fromLTRB(12, 14, 8, 5),
      child: _buildContent(context, colorScheme),
    );
    if (needDivider) {
      child = Column(
        mainAxisSize: .min,
        children: [
          child,
          Divider(
            indent: 55,
            endIndent: 15,
            height: 0.3,
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ],
      );
    }
    // 手柄：一条评论 = 一个焦点节点。回复 / 翻译 / 赞 / 踩 / 查看对话 / 子评论
    // 全在卡片里面，方向键一旦进去就要按七八下才出得来，所以整块移出焦点树，
    // 改由长按确定（或手柄 Y 键）弹出的操作面板提供 —— 触摸行为不变。
    // 确定键短按仍是原来的「回复这条评论」。
    return TvCard(
      debugLabel: '评论',
      onTap: () => replyReply?.call(replyItem, null),
      onLongPress: showMore,
      onMore: showMore,
      onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
      child: TvCardSubAction(child: child),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    final member = replyItem.member;
    Widget header = GestureDetector(
      onTap: () {
        feedBack();
        Get.toNamed('/member?mid=${replyItem.mid}');
      },
      child: TranslucentRow(
        spacing: 12,
        extraWidth: 46,
        children: [
          PendantAvatar(
            member.face,
            size: 34,
            badgeSize: 14,
            vipStatus: member.vipStatus.toInt(),
            officialType: member.officialVerifyType.toInt(),
            pendantImage: member.hasGarbPendantImage()
                ? member.garbPendantImage
                : null,
          ),
          Flexible(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Row(
                  spacing: 6,
                  mainAxisSize: .min,
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(
                          color: (member.vipStatus > 0 && member.vipType == 2)
                              ? colorScheme.vipColor
                              : colorScheme.outline,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    BiliUtils.levelPicture(
                      member.level.toInt(),
                      isSeniorMember: member.isSeniorMember == 1,
                      height: 11,
                    ),
                    if (replyItem.mid == upMid)
                      const PBadge(
                        text: 'UP',
                        size: .small,
                        isStack: false,
                        fontSize: 9,
                      )
                    else if (GlobalData().showMedal &&
                        member.hasFansMedalLevel())
                      MedalWidget(
                        medalName: member.fansMedalName,
                        level: member.fansMedalLevel.toInt(),
                        backgroundColor: DmUtils.decimalToColor(
                          member.fansMedalColor.toInt(),
                        ),
                        nameColor: DmUtils.decimalToColor(
                          member.fansMedalColorName.toInt(),
                        ),
                        padding: const .symmetric(horizontal: 6, vertical: 1.5),
                      ),
                  ],
                ),
                Row(
                  mainAxisSize: .min,
                  children: [
                    Text(
                      replyLevel == 0
                          ? DateFormatUtils.format(
                              replyItem.ctime.toInt(),
                              format: DateFormatUtils.longFormatDs,
                            )
                          : DateFormatUtils.dateFormat(replyItem.ctime.toInt()),
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.outline,
                      ),
                    ),
                    if (replyItem.replyControl.hasLocation())
                      Text(
                        ' • ${replyItem.replyControl.location}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.outline,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (PendantAvatar.showDecorate) {
      final garb = replyItem.memberV2.garb;
      if (garb.hasCardImage()) {
        const double height = 38.0;
        return Stack(
          clipBehavior: .none,
          children: [
            Positioned(
              top: 0,
              right: 0,
              height: height,
              child: CachedNetworkImage(
                height: height,
                memCacheHeight: height.cacheSize(context),
                imageUrl: ImageUtils.safeThumbnailUrl(garb.cardImage),
                placeholder: (_, _) => const SizedBox.shrink(),
              ),
            ),
            if (garb.hasCardNumber())
              Positioned(
                top: 0,
                right: 0,
                height: height,
                child: Center(
                  child: Text(
                    '${garb.fanNumPrefix}\n${garb.cardNumber}',
                    style: TextStyle(
                      fontSize: 8,
                      fontFamily: Assets.digitalNum,
                      color: ColourUtils.parseColor(garb.cardFanColor),
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
      }
    }
    return header;
  }

  Widget _buildVoteOption(
    ColorScheme colorScheme,
    ReplyControl_VoteOption voteOption,
  ) {
    return Text.rich(
      TextSpan(
        children: [
          switch (voteOption.labelKind) {
            .RED => TextSpan(
              text: '红方  ',
              style: TextStyle(color: colorScheme.vipColor),
            ),
            .BLUE => TextSpan(
              text: '蓝方  ',
              style: TextStyle(color: colorScheme.blue),
            ),
            _ => TextSpan(
              text: '投票  ',
              style: TextStyle(color: colorScheme.outline),
            ),
          },
          TextSpan(text: voteOption.desc),
        ],
      ),
      style: TextStyle(
        height: 1.75,
        fontSize: 12,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildContent(BuildContext context, ColorScheme colorScheme) {
    final replyControl = replyItem.replyControl;
    final padding = EdgeInsets.only(left: replyLevel == 0 ? 6 : 45, right: 6);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        _buildHeader(context, colorScheme),
        const SizedBox(height: 10),
        if (replyControl.hasVoteOption())
          Padding(
            padding: padding,
            child: _buildVoteOption(colorScheme, replyControl.voteOption),
          ),
        Padding(
          padding: padding,
          child: TextMore.rich(
            primary: colorScheme.primary,
            style: const TextStyle(height: 1.75, fontSize: 14),
            maxLines: replyLevel == 1 ? replyLengthLimit : null,
            TextSpan(
              children: [
                if (replyControl.isUpTop) ...[
                  const WidgetSpan(
                    alignment: .middle,
                    child: PBadge(
                      text: 'TOP',
                      size: .small,
                      isStack: false,
                      type: .line_primary,
                      fontSize: 9,
                      textScaleFactor: 1,
                    ),
                  ),
                  const TextSpan(text: ' '),
                ],
                _buildMessage(
                  context,
                  colorScheme,
                  replyControl.showTranslation
                      ? replyItem.translatedContent
                      : replyItem.content,
                  replyControl,
                ),
              ],
            ),
          ),
        ),
        if (replyItem.content.pictures.isNotEmpty) ...[
          Padding(
            padding: padding,
            child: ImageGridView(
              picArr: replyItem.content.pictures
                  .map(
                    (item) => ImageModel(
                      width: item.imgWidth,
                      height: item.imgHeight,
                      url: item.imgSrc,
                    ),
                  )
                  .toList(),
              onViewImage: onViewImage,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (replyLevel != 0) ...[
          const SizedBox(height: 4),
          buttonAction(context, colorScheme, replyControl),
        ],
        if (replyLevel == 1 && replyItem.count > Int64.ZERO) ...[
          Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 12),
            child: replyItemRow(context, colorScheme, replyItem.replies),
          ),
        ],
      ],
    );
  }

  /// 翻译 / 显示原文。
  ///
  /// 原来是按钮 `onPressed` 里的一整块，现在卡片上的「翻译」按钮和操作面板
  /// 里的「翻译」共用——手柄模式下卡片上的按钮摸不到，只能从面板翻。
  /// [item] 用的是面板打开时那一条（子评论面板里就是那条子评论）。
  Future<void> toggleTranslation(BuildContext context, ReplyInfo item) async {
    final replyControl = item.replyControl;
    void rebuild() {
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    }

    if (replyControl.showTranslation) {
      replyControl.showTranslation = false;
      rebuild();
      return;
    }
    if (_translating) {
      return;
    }
    if (item.hasTranslatedContent()) {
      replyControl.showTranslation = true;
      rebuild();
      return;
    }
    _translating = true;
    final res = await ReplyGrpc.translateReply(
      type: item.type,
      oid: item.oid,
      rpid: item.id,
    );
    if (res case Success(:final response)) {
      final translated = response.translatedReplies[item.id];
      if (translated != null && translated.hasTranslatedContent()) {
        replyControl.showTranslation = true;
        item.translatedContent = translated.translatedContent;
        rebuild();
      } else {
        SmartDialog.showToast('翻译结果为空');
      }
    } else if (res case Error(:final errMsg)) {
      SmartDialog.showToast('翻译失败: $errMsg');
    }
    _translating = false;
  }

  Widget _buildTranslateBtn(
    BuildContext context,
    ColorScheme colorScheme,
    ReplyControl replyControl,
    TextStyle textStyle,
    ButtonStyle buttonStyle,
  ) {
    final color = replyControl.showTranslation
        ? colorScheme.primary
        : colorScheme.outline.withValues(alpha: 0.8);
    return SizedBox(
      height: 32,
      child: TextButton(
        style: buttonStyle,
        onPressed: () => toggleTranslation(context, replyItem),
        child: Row(
          spacing: 3,
          mainAxisSize: .min,
          children: [
            Icon(Icons.translate, size: 16, color: color),
            Text(
              replyControl.showTranslation ? '原文' : '翻译',
              style: textStyle.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget buttonAction(
    BuildContext context,
    ColorScheme colorScheme,
    ReplyControl replyControl,
  ) {
    final textStyle = TextStyle(
      height: 1,
      fontSize: 12,
      fontWeight: .normal,
      color: colorScheme.outline,
    );
    const buttonStyle = ButtonStyle(
      visualDensity: .compact,
      tapTargetSize: .shrinkWrap,
      padding: WidgetStatePropertyAll(.zero),
    );

    Widget? dialogBtn;
    if (replyLevel == 2 && needDivider && replyItem.id != replyItem.dialog) {
      dialogBtn = SizedBox(
        height: 32,
        child: TextButton(
          onPressed: showDialogue,
          style: buttonStyle,
          child: Text('查看对话', style: textStyle),
        ),
      );
    } else if (replyLevel == 3 && replyItem.parent != replyItem.root) {
      dialogBtn = SizedBox(
        height: 32,
        child: TextButton(
          onPressed: jumpToDialogue,
          style: buttonStyle,
          child: Text('跳转回复', style: textStyle),
        ),
      );
    }
    return Row(
      children: [
        const SizedBox(width: 36),
        SizedBox(
          height: 32,
          child: TextButton(
            style: buttonStyle,
            onPressed: () {
              feedBack();
              onReply?.call(replyItem);
            },
            child: Row(
              spacing: 3,
              mainAxisSize: .min,
              children: [
                Icon(
                  Icons.reply,
                  size: 18,
                  color: colorScheme.outline.withValues(alpha: 0.8),
                ),
                Text('回复', style: textStyle),
              ],
            ),
          ),
        ),
        const SizedBox(width: 2),
        if (replyControl.translationSwitch ==
            .TRANSLATION_SWITCH_SHOW_TRANSLATION) ...[
          _buildTranslateBtn(
            context,
            colorScheme,
            replyControl,
            textStyle,
            buttonStyle,
          ),
          const SizedBox(width: 2),
        ] else if (replyControl.cardLabels.isNotEmpty) ...[
          Text(
            dialogBtn != null
                ? replyControl.cardLabels.first.textContent
                : replyControl.cardLabels.map((e) => e.textContent).join('  '),
            style: textStyle.copyWith(color: colorScheme.secondary),
          ),
          const SizedBox(width: 2),
        ],
        ?dialogBtn,
        const Spacer(),
        ZanButtonGrpc(replyItem: replyItem),
        const SizedBox(width: 5),
      ],
    );
  }

  Widget replyItemRow(
    BuildContext context,
    ColorScheme colorScheme,
    List<ReplyInfo> replies,
  ) {
    final extraRow = replies.length < replyItem.count.toInt();
    final length = replies.length + (extraRow ? 1 : 0);
    return Padding(
      padding: const .only(left: 42, right: 4),
      child: Material(
        animationDuration: .zero,
        color: colorScheme.onInverseSurface,
        borderRadius: const .all(.circular(6)),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (replies.isNotEmpty)
              ...replies.mapIndexed((index, childReply) {
                final EdgeInsets padding;
                BorderRadius? borderRadius;
                if (length == 1) {
                  padding = const .fromLTRB(8, 5, 8, 5);
                  borderRadius = const .all(.circular(6));
                } else {
                  if (index == 0) {
                    padding = const .fromLTRB(8, 8, 8, 4);
                    borderRadius = const .vertical(top: .circular(6));
                  } else if (index == length - 1) {
                    padding = const .fromLTRB(8, 4, 8, 8);
                    borderRadius = const .vertical(bottom: .circular(6));
                  } else {
                    padding = const .fromLTRB(8, 4, 8, 4);
                  }
                }
                void showMore() => _openMorePanel(
                  context: context,
                  item: childReply,
                  onDelete: () => onDelete?.call(replyItem, index),
                  isSubReply: true,
                );
                return InkWell(
                  borderRadius: borderRadius,
                  onTap: () =>
                      replyReply?.call(replyItem, childReply.id.toInt()),
                  onLongPress: showMore,
                  onSecondaryTap: PlatformUtils.isMobile ? null : showMore,
                  child: Padding(
                    padding: padding,
                    child: TextEllipsis.rich(
                      style: TextStyle(
                        height: 1.6,
                        fontSize: 14,
                        color: colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      TextSpan(
                        children: [
                          TextSpan(
                            text: childReply.member.name,
                            style: TextStyle(color: colorScheme.primary),
                            recognizer: NoDeadlineTapGestureRecognizer()
                              ..onTap = () {
                                feedBack();
                                Get.toNamed(
                                  '/member?mid=${childReply.member.mid}',
                                );
                              },
                          ),
                          if (childReply.mid == upMid) ...[
                            const TextSpan(text: ' '),
                            const WidgetSpan(
                              alignment: .middle,
                              child: PBadge(
                                text: 'UP',
                                size: .small,
                                isStack: false,
                                fontSize: 9,
                                textScaleFactor: 1,
                              ),
                            ),
                            const TextSpan(text: ' '),
                          ],
                          TextSpan(
                            text: childReply.root == childReply.parent
                                ? ': '
                                : childReply.mid == upMid
                                ? ''
                                : ' ',
                          ),
                          _buildMessage(
                            context,
                            colorScheme,
                            childReply.content,
                            childReply.replyControl,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            if (extraRow)
              InkWell(
                onTap: () => replyReply?.call(replyItem, null),
                borderRadius: length == 1
                    ? const .all(.circular(6))
                    : const .vertical(bottom: .circular(6)),
                child: Padding(
                  padding: length == 1
                      ? const .fromLTRB(8, 6, 8, 6)
                      : const .fromLTRB(8, 5, 8, 8),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 12),
                      children: [
                        if (replyItem.replyControl.upReply)
                          TextSpan(
                            text: 'UP主等人 ',
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        TextSpan(
                          text: '共${replyItem.count}条回复',
                          style: TextStyle(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InlineSpan _buildMessage(
    BuildContext context,
    ColorScheme colorScheme,
    Content content,
    ReplyControl replyControl,
  ) {
    final List<InlineSpan> spanChildren = <InlineSpan>[];
    bool hasNote = false;

    final urlKeys = content.urls.keys;
    // 构建正则表达式
    final List<String> specialTokens = [
      ...content.emotes.keys,
      ...content.topics.keys.map((e) => '#$e#'),
      ...content.atNameToMid.keys.map((e) => '@$e'),
      ...urlKeys,
    ];
    String patternStr = [
      ...specialTokens.map(RegExp.escape),
      r'(?:\d+[:：])?\d+[:：]\d+',
      r'\{vote:\d+?\}',
      Constants.urlRegex.pattern,
    ].join('|');
    final RegExp pattern = RegExp(patternStr);

    late List<String> matchedUrls = [];

    void addPlainTextSpan(str) {
      spanChildren.add(TextSpan(text: str));
    }

    void addUrl(String matchStr, Url url, {bool addPlainText = false}) {
      if (url.extra.isWordSearch && !enableWordRe) {
        if (addPlainText) {
          addPlainTextSpan(matchStr);
        }
        return;
      }
      final isCv = url.clickReport.startsWith('{"cvid');
      if (isCv) {
        hasNote = true;
      }
      final children = [
        if (!isCv && url.hasPrefixIcon())
          WidgetSpan(
            child: CachedNetworkImage(
              height: 19,
              memCacheHeight: 19.cacheSize(context),
              color: colorScheme.primary,
              imageUrl: ImageUtils.thumbnailUrl(url.prefixIcon),
              placeholder: (_, _) => const SizedBox.shrink(),
            ),
          ),
        TextSpan(
          text: isCv ? '[笔记] ' : url.title,
          style: TextStyle(color: colorScheme.primary),
          recognizer: NoDeadlineTapGestureRecognizer()
            ..onTap = () {
              if (url.appUrlSchema.isEmpty) {
                if (RegExp(
                  r'^(av|bv)',
                  caseSensitive: false,
                ).hasMatch(matchStr)) {
                  UrlUtils.matchUrlPush(matchStr, '');
                } else {
                  RegExpMatch? match = RegExp(
                    r'^cv(\d+)$|/read/cv(\d+)|note-app/view\?cvid=(\d+)',
                    caseSensitive: false,
                  ).firstMatch(matchStr);
                  String? cvid =
                      match?.group(1) ?? match?.group(2) ?? match?.group(3);
                  if (cvid != null) {
                    Get.toNamed(
                      '/articlePage',
                      parameters: {
                        'id': cvid,
                        'type': 'read',
                      },
                    );
                    return;
                  }
                  PageUtils.handleWebview(matchStr);
                }
              } else {
                if (url.extra.isWordSearch) {
                  Get.toNamed(
                    '/searchResult',
                    parameters: {'keyword': url.title},
                  );
                } else {
                  PageUtils.handleWebview(matchStr);
                }
              }
            },
        ),
      ];
      if (isCv) {
        spanChildren.insertAll(0, children);
      } else {
        spanChildren.addAll(children);
      }
    }

    // 分割文本并处理每个部分
    content.message.splitMapJoin(
      pattern,
      onMatch: (Match match) {
        String matchStr = match[0]!;
        late final name = matchStr.substring(1);
        late final topic = matchStr.substring(1, matchStr.length - 1);
        if (content.emotes.containsKey(matchStr)) {
          // 处理表情
          final emote = content.emotes[matchStr]!;
          final size = emote.size.toInt() * 20.0;
          spanChildren.add(
            WidgetSpan(
              child: NetworkImgLayer(
                src: emote.hasWebpUrl()
                    ? emote.webpUrl
                    : emote.hasGifUrl()
                    ? emote.gifUrl
                    : emote.url,
                type: ImageType.emote,
                width: size,
                height: size,
              ),
            ),
          );
        } else if (matchStr.startsWith("@") &&
            content.atNameToMid.containsKey(name)) {
          // 处理@用户
          spanChildren.add(
            TextSpan(
              text: matchStr,
              style: TextStyle(color: colorScheme.primary),
              recognizer: NoDeadlineTapGestureRecognizer()
                ..onTap = () =>
                    Get.toNamed('/member?mid=${content.atNameToMid[name]}'),
            ),
          );
        } else if (_voteRegExp.hasMatch(matchStr)) {
          spanChildren.add(
            TextSpan(
              text: '投票: ${content.vote.title}',
              style: TextStyle(color: colorScheme.primary),
              recognizer: NoDeadlineTapGestureRecognizer()
                ..onTap = () =>
                    showVoteDialog(context, content.vote.id.toInt()),
            ),
          );
        } else if (_timeRegExp.hasMatch(matchStr)) {
          matchStr = matchStr.replaceAll('：', ':');
          bool isValid = false;
          try {
            final ctr = Get.find<VideoDetailController>(
              tag: getTag?.call() ?? Get.arguments['heroTag'],
            );
            isValid =
                DurationUtils.parseDuration(matchStr) * 1000 <=
                ctr.data.timeLength!;
          } catch (e) {
            if (kDebugMode) debugPrint('failed to validate: $e');
          }
          spanChildren.add(
            TextSpan(
              text: isValid ? ' $matchStr ' : matchStr,
              style: isValid ? TextStyle(color: colorScheme.primary) : null,
              recognizer: isValid
                  ? (NoDeadlineTapGestureRecognizer()
                      ..onTap = () {
                        // 跳转到指定位置
                        try {
                          SmartDialog.showToast('跳转至：$matchStr');
                          Get.find<VideoDetailController>(
                            tag: Get.arguments['heroTag'],
                          ).plPlayerController.seekTo(
                            Duration(
                              seconds: DurationUtils.parseDuration(matchStr),
                            ),
                            isSeek: false,
                          );
                        } catch (e) {
                          SmartDialog.showToast('跳转失败: $e');
                        }
                      })
                  : null,
            ),
          );
        } else {
          final url = content.urls[matchStr];
          if (url != null && !matchedUrls.contains(matchStr)) {
            addUrl(matchStr, url, addPlainText: true);
            // 只显示一次
            matchedUrls.add(matchStr);
          } else if (matchStr.length > 1 && content.topics[topic] != null) {
            spanChildren.add(
              TextSpan(
                text: matchStr,
                style: TextStyle(color: colorScheme.primary),
                recognizer: NoDeadlineTapGestureRecognizer()
                  ..onTap = () {
                    Get.toNamed(
                      '/searchResult',
                      parameters: {'keyword': topic},
                    );
                  },
              ),
            );
          } else if (Constants.urlRegex.hasMatch(matchStr)) {
            spanChildren.add(
              TextSpan(
                text: matchStr,
                style: TextStyle(color: colorScheme.primary),
                recognizer: NoDeadlineTapGestureRecognizer()
                  ..onTap = () => PageUtils.handleWebview(matchStr),
              ),
            );
          } else {
            addPlainTextSpan(matchStr);
          }
        }
        return '';
      },
      onNonMatch: (String nonMatchStr) {
        addPlainTextSpan(nonMatchStr);
        return nonMatchStr;
      },
    );

    // if (urlKeys.isNotEmpty) {
    //   List<String> unmatchedItems = urlKeys
    //       .where((url) => !matchedUrls.contains(url))
    //       .toList();
    //   if (unmatchedItems.isNotEmpty) {
    //     for (final patternStr in unmatchedItems) {
    //       addUrl(patternStr, content.urls[patternStr]!);
    //     }
    //   }
    // }

    if (!hasNote && replyControl.isNote && replyControl.isNoteV2) {
      final Color color;
      NoDeadlineTapGestureRecognizer? recognizer;

      final hasClickUrl = content.richText.note.hasClickUrl();
      if (hasClickUrl || content.richText.opus.hasOpusId()) {
        color = colorScheme.primary;
        recognizer = NoDeadlineTapGestureRecognizer()
          ..onTap = () => hasClickUrl
              ? PiliScheme.routePushFromUrl(content.richText.note.clickUrl)
              : Get.toNamed(
                  '/articlePage',
                  parameters: {
                    'id': content.richText.opus.opusId.toString(),
                    'type': 'opus',
                  },
                );
      } else {
        color = colorScheme.secondary;
      }
      spanChildren.insert(
        0,
        TextSpan(
          text: '[笔记] ',
          style: TextStyle(color: color),
          recognizer: recognizer,
        ),
      );
    }

    return TextSpan(children: spanChildren);
  }

  /// 打开评论操作面板：长按确定 / 手柄 Y 键 / 桌面右键都走这里。
  ///
  /// 三件事写在弹出这一层，而不是面板内容里：
  /// - 传的是**卡片自己的 context**（`builder` 里那个是弹层的）：面板里的
  ///   「翻译」要 `markNeedsBuild` 卡片才看得到结果；
  /// - [TvFocusOnOpen]：弹层是独立路由，不主动送一次焦点，用户就面对
  ///   "菜单弹出来了、按确定没反应"；
  /// - 外面再套一层滚动：手柄补齐了卡片上摸不到的操作，条目比触摸时多，
  ///   小屏上会超出屏幕（`Column` 直接溢出）。
  void _openMorePanel({
    required BuildContext context,
    required ReplyInfo item,
    required VoidCallback onDelete,
    required bool isSubReply,
  }) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: min(640, context.mediaQueryShortestSide),
      ),
      builder: (_) => TvFocusOnOpen(
        child: SingleChildScrollView(
          child: morePanel(
            context: context,
            item: item,
            onDelete: onDelete,
            isSubReply: isSubReply,
          ),
        ),
      ),
    );
  }

  /// 面板里的一行：确定键激活 + 焦点环。
  ///
  /// 视觉上就是原来的 `ListTile`。`onTap` 之所以交给 [TvCard]，是因为
  /// `ListTile` 自己只有一层很淡的 focus tint，坐在三米外根本看不出选中了哪一项；
  /// 反过来 `ListTile` 保留 `onTap` 会再插一个焦点节点进来（`enabled: true`
  /// 是为了让它在没有 `onTap` 时仍然是正常配色，而不是变灰的禁用态）。
  Widget _panelItem({
    required VoidCallback onTap,
    required String title,
    TextStyle? style,
    Widget? leading,
  }) {
    return TvCard(
      debugLabel: '评论操作',
      radius: const BorderRadius.all(Radius.circular(8)),
      onTap: onTap,
      child: ListTile(
        enabled: true,
        minLeadingWidth: 0,
        leading: leading,
        title: Text(title, style: style),
      ),
    );
  }

  Widget morePanel({
    required BuildContext context,
    required ReplyInfo item,
    required VoidCallback onDelete,
    required bool isSubReply,
  }) {
    late String message = item.content.message;
    final ownerMid = Int64(Accounts.main.mid);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final errorColor = colorScheme.error;
    final style = theme.textTheme.titleSmall!;
    return Padding(
      padding: .only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TvCardSubAction(
            // 拖拽把手：触摸用的，别让它抢走"面板第一项"的位置
            child: _PanelHandle(),
          ),
          // —— 手柄模式下卡片上摸不到的操作用这里补齐（卡片只占一个焦点节点）——
          if (onReply != null)
            _panelItem(
              onTap: () {
                Get.back();
                onReply!(item);
              },
              leading: const Icon(Icons.reply, size: 19),
              title: '回复',
              style: style,
            ),
          _panelItem(
            onTap: () {
              Get.back();
              ZanActions.like(context, item, isLike: ZanActions.isLiked(item));
            },
            leading: Icon(
              ZanActions.isLiked(item)
                  ? FontAwesomeIcons.solidThumbsUp
                  : FontAwesomeIcons.thumbsUp,
              size: 19,
            ),
            title: ZanActions.isLiked(item) ? '取消赞' : '点赞',
            style: style,
          ),
          _panelItem(
            onTap: () {
              Get.back();
              ZanActions.hate(
                context,
                item,
                isDislike: ZanActions.isDisliked(item),
              );
            },
            leading: Icon(
              ZanActions.isDisliked(item)
                  ? FontAwesomeIcons.solidThumbsDown
                  : FontAwesomeIcons.thumbsDown,
              size: 19,
            ),
            title: ZanActions.isDisliked(item) ? '取消踩' : '点踩',
            style: style,
          ),
          if (item.replyControl.translationSwitch ==
              .TRANSLATION_SWITCH_SHOW_TRANSLATION)
            _panelItem(
              onTap: () {
                Get.back();
                toggleTranslation(context, item);
              },
              leading: const Icon(Icons.translate, size: 19),
              title: item.replyControl.showTranslation ? '显示原文' : '翻译',
              style: style,
            ),
          // 子评论列表页（reply_reply）没有 replyReply，这条就别出现
          if (!isSubReply && replyReply != null && item.count > Int64.ZERO)
            _panelItem(
              onTap: () {
                Get.back();
                replyReply?.call(item, null);
              },
              leading: const Icon(Icons.forum_outlined, size: 19),
              title: '查看${item.count}条回复',
              style: style,
            ),
          if (kDebugMode && GStorage.reply != null) ...[
            _panelItem(
              onTap: () {
                Get.back();
                GStorage.reply!.put(
                  item.id.toString(),
                  (item.deepCopy()
                        ..unknownFields.clear()
                        ..replies.clear()
                        ..clearTrackInfo())
                      .writeToBuffer(),
                );
              },
              title: 'save to local',
              style: style.copyWith(color: colorScheme.primary),
            ),
            _panelItem(
              onTap: () {
                Get.back();
                onDelete();
                GStorage.reply!.delete(item.id.toString());
              },
              title: 'remove from local',
              style: style.copyWith(color: colorScheme.primary),
            ),
            _panelItem(
              onTap: () {
                Get.back();
                final oid = item.oid.toInt();
                final data =
                    (item.deepCopy()
                          ..unknownFields.clear()
                          ..replies.clear()
                          ..clearTrackInfo())
                        .writeToBuffer();
                GStorage.reply!.putAll({
                  for (var i = oid; i < oid + 1000; i++) i.toString(): data,
                });
              },
              title: 'save to local (x1000)',
              style: style.copyWith(color: colorScheme.primary),
            ),
          ],
          if (ownerMid == upMid || ownerMid == item.member.mid)
            _panelItem(
              onTap: () async {
                Get.back();
                bool? isDelete = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    final colorScheme = ColorScheme.of(context);
                    return AlertDialog(
                      title: const Text('删除评论'),
                      content: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: '确定删除这条评论吗？\n\n'),
                            if (ownerMid != item.member.mid.toInt()) ...[
                              TextSpan(
                                text: '@${item.member.name}',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                ),
                              ),
                              const TextSpan(text: ':\n'),
                            ],
                            TextSpan(text: message),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(result: false),
                          child: Text(
                            '取消',
                            style: TextStyle(
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Get.back(result: true),
                          child: const Text('确定'),
                        ),
                      ],
                    );
                  },
                );
                if (isDelete == null || !isDelete) {
                  return;
                }
                SmartDialog.showLoading(msg: '删除中...');
                final res = await VideoHttp.replyDel(
                  type: item.type.toInt(),
                  oid: item.oid.toInt(),
                  rpid: item.id.toInt(),
                );
                SmartDialog.dismiss();
                if (res.isSuccess) {
                  SmartDialog.showToast('删除成功');
                  onDelete();
                } else {
                  SmartDialog.showToast('删除失败, $res');
                }
              },
              leading: Icon(Icons.delete_outlined, color: errorColor, size: 19),
              title: '删除',
              style: style.copyWith(color: errorColor),
            ),
          if (ownerMid != Int64.ZERO)
            _panelItem(
              onTap: () {
                Get.back();

                final oid = item.oid;
                final rpid = item.id;

                autoWrapReportDialog(
                  context,
                  ReportOptions.commentReport,
                  withContent: ReportOptions.withContentReply,
                  contentRequired: ReportOptions.contentRequiredReply,
                  reportUrl:
                      'https://www.bilibili.com/h5/comment/report?oid=$oid&pageType=${item.type}&rpid=$rpid&platform=android&build=8430300&${ThemeUtils.themeUrl(colorScheme.isDark)}',
                  (reasonType, reasonDesc, banUid) async {
                    final res = await ReplyHttp.report(
                      rpid: rpid,
                      oid: oid,
                      reasonType: reasonType,
                      reasonDesc: reasonDesc,
                      banUid: banUid,
                    );
                    if (res.isSuccess) {
                      onDelete();
                    }
                    return res;
                  },
                );
              },
              leading: Icon(Icons.error_outline, color: errorColor, size: 19),
              title: '举报',
              style: style.copyWith(color: errorColor),
            ),
          if (replyLevel == 1 && !isSubReply && ownerMid == upMid)
            _panelItem(
              onTap: () {
                Get.back();
                onToggleTop?.call(item);
              },
              leading: const Icon(Icons.vertical_align_top, size: 19),
              title: '${replyItem.replyControl.isUpTop ? '取消' : ''}置顶',
              style: style,
            ),
          _panelItem(
            onTap: () {
              Get.back();
              Utils.copyText(message);
            },
            leading: const Icon(Icons.copy_all_outlined, size: 19),
            title: '复制全部',
            style: style,
          ),
          _panelItem(
            onTap: () {
              Get.back();
              showReplyCopyDialog(context, message, item.content.emotes);
            },
            leading: const Icon(Icons.copy_outlined, size: 19),
            title: '自由复制',
            style: style,
          ),
          _panelItem(
            onTap: () {
              Get.back();
              SavePanel.toSavePanel(upMid: upMid, item: item);
            },
            leading: const Icon(Icons.save_alt, size: 19),
            title: '保存评论',
            style: style,
          ),
          if (kDebugMode || item.mid == ownerMid)
            _panelItem(
              onTap: () {
                Get.back();
                onCheckReply?.call(item);
              },
              leading: const Icon(CustomIcons.shield_reply, size: 19),
              title: '检查评论',
              style: style,
            ),
        ],
      ),
    );
  }
}

/// 底弹层顶部那根小横条：点一下关掉面板。
///
/// 手柄模式下它被 [TvCardSubAction] 排除在焦点树外——它是触摸用的把手，
/// 排在所有操作前面，[TvFocusOnOpen] 万一选中它，"面板第一项"就成了一个
/// 看不见的东西。
class _PanelHandle extends StatelessWidget {
  const _PanelHandle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return InkWell(
      onTap: Get.back,
      borderRadius: Style.bottomSheetRadius,
      child: SizedBox(
        height: 35,
        child: Center(
          child: Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: colorScheme.outline,
              borderRadius: const BorderRadius.all(Radius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}
