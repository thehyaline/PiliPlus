import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/sliver_single_child_delegate.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/focus/tv_card.dart';
import 'package:PiliPlus/common/widgets/focus/tv_focus_memory.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_v.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/pages/rcmd/controller.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  /// TV 焦点区域的标签（`TvRegion.debugLabel`）：切栏之后靠它把焦点送回这个网格
  /// 的落点（见 `TvRegions.focusEntry`），所以要和首页 tab 那边的映射对上。
  static const tvRegion = 'home-rcmd-grid';

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final controller = Get.put(RcmdController());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);
    return Container(
      clipBehavior: .hardEdge,
      margin: const .symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(borderRadius: Style.mdRadius),
      child: TvRegion(
        debugLabel: RcmdPage.tvRegion,
        child: refreshIndicator(
          onRefresh: () async {
            // 刷新会把整张列表换掉，焦点先寄存在网格里
            TvFocusMemory.park();
            await controller.onRefresh();
            TvFocusMemory.restore();
          },
          child: CustomScrollView(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            // 让下一行留在焦点树里，方向键才能走到下一行
            scrollCacheExtent: TvFocusSpec.cacheExtent,
            slivers: [
              SliverPadding(
                padding: const .only(top: Style.cardSpace, bottom: 100),
                sliver: Obx(
                  () => _buildBody(colorScheme, controller.loadingState.value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SliverGridDelegateWithExtentAndRatio get gridDelegate =>
      Grid.videoCardVDelegate(
        mainAxisExtent: MediaQuery.textScalerOf(
          context,
        ).scale(Style.videoCardContentHeight),
      );

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
    return switch (loadingState) {
      Loading() => _buildSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  if (index == response.length - 1) {
                    // 加载更多不改动已有项，只是代码里顺手把焦点行为写清楚
                    TvFocusMemory.park();
                    controller.onLoadMore();
                    TvFocusMemory.restore();
                  }
                  if (controller.lastRefreshAt != null) {
                    if (controller.lastRefreshAt == index) {
                      return TvCard(
                        onTap: _refreshFromTip,
                        surface: tvCardSurface,
                        radius: Style.mdRadius,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const .symmetric(horizontal: 10),
                          child: Text(
                            '上次看到这里\n点击刷新',
                            textAlign: .center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    }
                    final actualIndex = index > controller.lastRefreshAt!
                        ? index - 1
                        : index;
                    return VideoCardV(
                      videoItem: response[actualIndex],
                      autofocus: index == 0,
                      onRemove: () {
                        if (controller.lastRefreshAt != null &&
                            actualIndex < controller.lastRefreshAt!) {
                          controller.lastRefreshAt =
                              controller.lastRefreshAt! - 1;
                        }
                        // 删掉的可能正是聚焦的那张卡，删完把焦点交给接替它位置的卡
                        TvFocusMemory.park();
                        controller.loadingState
                          ..value.data!.removeAt(actualIndex)
                          ..refresh();
                        TvFocusMemory.restore(preferIndex: actualIndex);
                      },
                    );
                  } else {
                    return VideoCardV(
                      videoItem: response[index],
                      autofocus: index == 0,
                      onRemove: () {
                        TvFocusMemory.park();
                        controller.loadingState
                          ..value.data!.removeAt(index)
                          ..refresh();
                        TvFocusMemory.restore(preferIndex: index);
                      },
                    );
                  }
                },
                itemCount: controller.lastRefreshAt != null
                    ? response.length + 1
                    : response.length,
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget get _buildSkeleton => SliverGrid(
    gridDelegate: gridDelegate,
    delegate: const SliverSingleChildDelegate(
      count: 10,
      child: VideoCardVSkeleton(),
    ),
  );

  /// 「上次看到这里」那张提示卡：回顶 + 刷新，焦点跟着回到第一张卡。
  ///
  /// 为什么不能只靠 `TvFocusMemory`：这张卡刷新前后占的是**同一个序号**
  /// （`lastRefreshAt` 是这批新数据的条数，一般没变），列表换新之后它还活着，
  /// 焦点根本不会"丢"——那套"只接丢了"的规则接不到它。而页面这时已经滚回顶上，
  /// 它留在原地就等于待在屏幕外，预选框看着就没了（见方法后半段的落项）。
  ///
  /// 落项要等列表**真的**回到顶上：回顶是 500ms 动画（离得远时是直接跳），落早了
  /// 树里的第一项还在半路、甚至还没建出来（视口外又在缓存范围外的卡根本不在焦点
  /// 树上），焦点会停在一张屏幕外的卡上。等的这几帧里用户自己挪了焦点就收手——
  /// 不跟用户抢（同 `main/view.dart` 的 `_handOffNavFocus`）。
  void _refreshFromTip() {
    controller
      ..animateToTop()
      ..onRefresh();
    // 起点是这一下按确定/点击时的焦点，用来分辨"用户自己挪走了"
    final from = FocusManager.instance.primaryFocus;
    var frames = 0;
    void land(Duration _) {
      if (!mounted) return;
      if (!identical(FocusManager.instance.primaryFocus, from)) return;
      final scroll = controller.scrollController;
      // 拿不到 position 就是列表还没建出来，按"已经在顶上"处理
      if (!scroll.hasClients || scroll.position.pixels == 0) {
        // 明确按序号落项：这时候树里的第一项就是第一张卡
        TvRegions.focusFirst(RcmdPage.tvRegion);
        return;
      }
      if (++frames < _landMaxFrames) {
        WidgetsBinding.instance.addPostFrameCallback(land);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(land);
  }

  /// 回顶 + 刷新之后等落点的上限（≈1 秒）：回顶动画 500ms，剩下留给列表换新
  /// 那一帧。等不到就收手——焦点还在提示卡上的话，用户按方向键时
  /// `TvRouteFocusObserver` 会把它接回来。
  static const int _landMaxFrames = 60;
}
