import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/draggable_sheet/dyn.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/marquee.dart';
import 'package:PiliPlus/models/common/video/live_quality.dart';
import 'package:PiliPlus/pages/live_room/controller.dart';
import 'package:PiliPlus/pages/setting/models/play_settings.dart'
    show showPlayerVolumeDialog;
import 'package:PiliPlus/pages/video/widgets/header_control.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/video_fit_type.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/common_btn.dart';
import 'package:PiliPlus/services/shutdown_timer_service.dart'
    show shutdownTimerService;
import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/string_ext.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:collection/collection.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class LiveHeaderControl extends StatefulWidget {
  const LiveHeaderControl({
    super.key,
    required this.title,
    required this.upName,
    required this.plPlayerController,
    required this.onSendDanmaku,
    required this.onPlayAudio,
    required this.isPortrait,
    required this.liveController,
    required this.onlineWidget,
  });

  final String? title;
  final String? upName;
  final PlPlayerController plPlayerController;
  final VoidCallback onSendDanmaku;
  final VoidCallback onPlayAudio;
  final bool isPortrait;
  final LiveRoomController liveController;
  final Widget onlineWidget;

  @override
  State<LiveHeaderControl> createState() => _LiveHeaderControlState();
}

class _LiveHeaderControlState extends State<LiveHeaderControl>
    with TimeBatteryMixin {
  @override
  late final plPlayerController = widget.plPlayerController;

  @override
  bool get horizontalScreen => true;

  @override
  bool get isFullScreen => plPlayerController.isFullScreen.value;

  @override
  bool get isPortrait => widget.isPortrait;

  /// 返回键的焦点节点。
  ///
  /// 它同时是 [TvLabels.playerBack] 锚点：手柄模式下焦点**进到上栏**时落点锁在
  /// 返回键上（`TvEntryLock`），那个判断发生在播放器那一层，拿不到这个 State。
  late final FocusNode _backNode = FocusNode(debugLabel: 'PlayerBack');

  @override
  void dispose() {
    TvRegions.unregisterAnchor(TvLabels.playerBack, _backNode);
    _backNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = this.isFullScreen;
    final showBack = isFullScreen || plPlayerController.isDesktopPip;
    // 上栏入口锚点：手柄模式下焦点进到上栏里时落点锁在返回键上（`TvEntryLock`）。
    // 直播页的返回键只有全屏 / 桌面画中画才有，所以锚点跟着它走：不在树上时
    // 撤销登记，进栏锁退化成几何寻焦（否则会锁到一个已经离树的节点上，
    // `focusAnchor` 检查出 `context` 为空、什么都不做，方向键反而卡住）。
    if (Pref.tvFocus && showBack) {
      TvRegions.registerAnchor(TvLabels.playerBack, _backNode);
    } else {
      TvRegions.unregisterAnchor(TvLabels.playerBack, _backNode);
    }
    showCurrTimeIfNeeded(isFullScreen);
    final liveController = widget.liveController;
    Widget child;
    child = Obx(
      key: titleKey,
      () => MarqueeText(
        liveController.title.value,
        spacing: 30,
        velocity: 30,
        strutStyle: const StrutStyle(fontSize: 15, leading: 0),
        style: const TextStyle(fontSize: 15, height: 1, color: Colors.white),
      ),
    );
    if (isFullScreen) {
      child = Column(
        spacing: 5,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          Row(
            spacing: 10,
            children: [
              if (widget.upName case final upName?)
                Text(
                  upName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              liveController.watchedWidget,
              widget.onlineWidget,
              liveController.timeWidget,
            ],
          ),
        ],
      );
    }
    child = Expanded(child: child);

    const btnHeight = 30.0;

    return Padding(
      padding: const .only(
        left: 14,
        right: 14,
        top: (kToolbarHeight - btnHeight) / 2,
      ),
      child: Row(
        children: [
          if (showBack)
            ComBtn(
              height: btnHeight,
              tooltip: '返回',
              focusNode: _backNode,
              icon: const Icon(FontAwesomeIcons.arrowLeft, size: 15),
              // 和视频页同一颗按钮：直接走"退出"那一步（锁屏 → 画中画 →
              // 全屏 → 退页面），不吃"控制条亮着先收控制条"那条规则
              onTap: plPlayerController.onBackButton,
            ),
          child,
          ...?timeBatteryWidgets,
          const SizedBox(width: 10),
          if (PlatformUtils.isDesktop && !plPlayerController.isDesktopPip)
            Obx(() {
              final isAlwaysOnTop = plPlayerController.isAlwaysOnTop.value;
              return ComBtn(
                height: btnHeight,
                tooltip: '${isAlwaysOnTop ? '取消' : ''}置顶',
                icon: isAlwaysOnTop
                    ? const Icon(
                        size: 18,
                        Icons.push_pin,
                        color: Colors.white,
                      )
                    : const Icon(
                        size: 18,
                        Icons.push_pin_outlined,
                        color: Colors.white,
                      ),
                onTap: () => plPlayerController.setAlwaysOnTop(!isAlwaysOnTop),
              );
            }),
          if (isFullScreen || PlatformUtils.isDesktop)
            ComBtn(
              height: btnHeight,
              tooltip: '发弹幕',
              icon: const Icon(
                size: 18,
                Icons.comment_outlined,
                color: Colors.white,
              ),
              onTap: widget.onSendDanmaku,
            ),
          if (Platform.isAndroid || (PlatformUtils.isDesktop && !isFullScreen))
            ComBtn(
              height: btnHeight,
              tooltip: '画中画',
              onTap: () {
                if (PlatformUtils.isDesktop) {
                  plPlayerController.toggleDesktopPip();
                  return;
                }
                if (AndroidHelper.isPipAvailable) {
                  plPlayerController.enterPip();
                }
              },
              icon: const Icon(
                size: 18,
                Icons.picture_in_picture_outlined,
                color: Colors.white,
              ),
            ),
          Obx(
            () => ComBtn(
              height: btnHeight,
              tooltip: '仅播放音频',
              onTap: () {
                plPlayerController.onlyPlayAudio.toggle();
                widget.onPlayAudio();
              },
              icon: plPlayerController.onlyPlayAudio.value
                  ? const Icon(
                      size: 18,
                      MdiIcons.musicCircle,
                      color: Colors.white,
                    )
                  : const Icon(
                      size: 18,
                      MdiIcons.musicCircleOutline,
                      color: Colors.white,
                    ),
            ),
          ),
          if (PlatformUtils.isMobile)
            Obx(() {
              final continuePlayInBackground =
                  plPlayerController.continuePlayInBackground.value;
              return ComBtn(
                height: btnHeight,
                tooltip: '${continuePlayInBackground ? '关闭' : ''}后台播放',
                onTap: plPlayerController.setContinuePlayInBackground,
                icon: continuePlayInBackground
                    ? const Icon(
                        size: 18,
                        Icons.play_circle,
                        color: Colors.white,
                      )
                    : const Icon(
                        size: 18,
                        Icons.play_circle_outline,
                        color: Colors.white,
                      ),
              );
            }),
          ComBtn(
            height: btnHeight,
            tooltip: '定时关闭',
            onTap: () => shutdownTimerService.showScheduleExitDialog(
              context,
              isFullScreen: isFullScreen,
              isLive: true,
            ),
            icon: const Icon(
              size: 18,
              Icons.schedule,
              color: Colors.white,
            ),
          ),
          if (plPlayerController.videoPlayerController case final player?)
            SizedBox.square(
              dimension: 30,
              child: PopupMenuButton(
                iconSize: 18,
                padding: .zero,
                iconColor: Colors.white,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    height: 35,
                    onTap: _showLiveStreamDialog,
                    child: const Row(
                      spacing: 8,
                      children: [
                        Icon(Icons.alt_route, size: 17),
                        Text('切换路线', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: showSetVideoFit,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Row(
                          spacing: 8,
                          children: [
                            Icon(Icons.aspect_ratio, size: 17),
                            Text('画面比例', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                        Obx(
                          () => Padding(
                            padding: const EdgeInsets.only(left: 25),
                            child: Text(
                              '当前比例 ${plPlayerController.videoFit.value.desc}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    height: 35,
                    child: const Row(
                      spacing: 8,
                      children: [
                        Icon(Icons.info_outline, size: 17),
                        Text('播放信息', style: TextStyle(fontSize: 14)),
                      ],
                    ),
                    onTap: () => HeaderControlState.showPlayerInfo(
                      context,
                      player: player,
                    ),
                  ),
                  if (PlatformUtils.isMobile)
                    PopupMenuItem(
                      height: 35,
                      child: Row(
                        spacing: 8,
                        children: [
                          const Icon(Icons.volume_up, size: 17),
                          Text(
                            '播放器音量: ${player.getProperty('volume').subLength(3)}%',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      onTap: () => showPlayerVolumeDialog(
                        context,
                        () {},
                        onChanged: player.setVolume,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 选择画面比例
  void showSetVideoFit() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(640, context.mediaQueryShortestSide),
      ),
      builder: (context) {
        final colorScheme = ColorScheme.of(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            clipBehavior: Clip.hardEdge,
            color: colorScheme.surface,
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  height: 45,
                  child: Center(
                    child: Text('选择画面比例', style: TextStyle(fontSize: 14)),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: VideoFitType.values.map((item) {
                      final isCurr = plPlayerController.videoFit.value == item;
                      return ListTile(
                        dense: true,
                        onTap: () {
                          if (isCurr) return;
                          Get.back();
                          plPlayerController.toggleVideoFit(item);
                          SmartDialog.showToast("画面比例已变为：${item.desc}");
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        title: Text(item.desc),
                        trailing: isCurr
                            ? Icon(Icons.done, color: colorScheme.primary)
                            : null,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLiveStreamDialog() {
    final controller = widget.liveController;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxWidth: math.min(640, context.mediaQueryShortestSide),
      ),
      builder: (context) {
        final maxChildSize =
            PlatformUtils.isMobile && !context.mediaQuerySize.isPortrait
            ? 1.0
            : 0.7;
        return DynDraggableScrollableSheet(
          minChildSize: 0,
          maxChildSize: maxChildSize,
          snap: true,
          expand: false,
          snapSizes: [maxChildSize],
          initialChildSize: maxChildSize,
          builder: (context, scrollController) {
            final colorScheme = ColorScheme.of(context);
            final secondary = colorScheme.secondary;
            final onSurfaceVariant = colorScheme.onSurfaceVariant;
            final currStyle = TextStyle(fontSize: 14, color: secondary);
            return Column(
              children: [
                InkWell(
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
                          borderRadius: const .all(.circular(1.5)),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: .only(
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
                    ),
                    children: controller.stream.mapIndexed((si, stream) {
                      final isCurrStream = si == controller.streamIndex;
                      final streamColor = isCurrStream
                          ? secondary
                          : onSurfaceVariant;
                      return _ExpansionTile(
                        initiallyExpanded: isCurrStream,
                        iconColor: streamColor,
                        collapsedIconColor: streamColor,
                        title: Text(
                          stream.protocolName ?? si.toString(),
                          style: isCurrStream
                              ? currStyle
                              : const TextStyle(fontSize: 14),
                        ),
                        children: stream.format.mapIndexed((fi, format) {
                          final isCurrFormat =
                              isCurrStream && fi == controller.formatIndex;
                          final formatColor = isCurrFormat
                              ? secondary
                              : onSurfaceVariant;
                          return _ExpansionTile(
                            initiallyExpanded: isCurrFormat,
                            iconColor: formatColor,
                            collapsedIconColor: formatColor,
                            title: Text(
                              format.formatName ?? fi.toString(),
                              style: isCurrFormat
                                  ? currStyle
                                  : const TextStyle(fontSize: 14),
                            ),
                            children: format.codec.mapIndexed((ci, codec) {
                              final isCurrCodec =
                                  isCurrFormat && ci == controller.codecIndex;
                              final codecColor = isCurrCodec
                                  ? secondary
                                  : onSurfaceVariant;
                              return _ExpansionTile(
                                initiallyExpanded: isCurrCodec,
                                iconColor: codecColor,
                                collapsedIconColor: codecColor,
                                title: Text(
                                  '${codec.codecName ?? ci.toString()} (${LiveQuality.fromCode(codec.currentQn)?.desc ?? codec.currentQn})',
                                  style: isCurrCodec
                                      ? currStyle
                                      : const TextStyle(fontSize: 14),
                                ),
                                children: codec.urlInfo.mapIndexed((ui, url) {
                                  final isCurrUrl =
                                      isCurrCodec &&
                                      ui == controller.liveUrlIndex;
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      '${url.host}...',
                                      style: isCurrUrl
                                          ? const TextStyle(fontSize: 14)
                                          : TextStyle(
                                              fontSize: 14,
                                              color: onSurfaceVariant,
                                            ),
                                    ),
                                    selected: isCurrUrl,
                                    onTap: isCurrUrl
                                        ? null
                                        : () {
                                            Get.back();
                                            controller.initLiveUrl(
                                              streamIndex: si,
                                              formatIndex: fi,
                                              codecIndex: ci,
                                              liveUrlIndex: ui,
                                            );
                                            GStorage.setting.put(
                                              SettingBoxKey.liveStream,
                                              [
                                                stream.protocolName!,
                                                format.formatName!,
                                                codec.codecName!,
                                              ],
                                            );
                                          },
                                  );
                                }).toList(),
                              );
                            }).toList(),
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ExpansionTile extends ExpansionTile {
  const _ExpansionTile({
    required super.title,
    super.initiallyExpanded,
    super.iconColor,
    super.collapsedIconColor,
    super.children,
  }) : super(
         dense: true,
         childrenPadding: const .only(left: 20),
       );
}
