import 'dart:async';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/dynamic/live_panel_position.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/result.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/dynamic_panel.dart';
import 'package:PiliPlus/pages/dynamics/widgets/top_live_bar.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel_section.dart';
import 'package:PiliPlus/pages/dynamics_tab/controller.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    hide SliverWaterfallFlowDelegateWithMaxCrossAxisExtent;

class DynamicsTabPage extends StatefulWidget {
  const DynamicsTabPage({super.key, required this.dynamicsType});

  final DynamicsTabType dynamicsType;

  /// 本栏的 TV 焦点区域标签（一块栏 = 一块区域，见 State 的 build）。
  ///
  /// 静态形式给"从外面把焦点送进某一栏"用（主界面底栏切页交接，
  /// `main/view.dart` 的 `_tvRegionOf`）：那边只有 `DynamicsTabType`，
  /// 拿不到本页的 State。标签格式在这里定死一处，两边都引它。
  static String tvRegionOf(DynamicsTabType type) => 'dynamics-${type.name}';

  @override
  State<DynamicsTabPage> createState() => _DynamicsTabPageState();
}

class _DynamicsTabPageState extends State<DynamicsTabPage>
    with AutomaticKeepAliveClientMixin, DynMixin {
  final dynamicsController = Get.putOrFind(DynamicsController.new);
  late final DynamicsTabController controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    controller = Get.putOrFind(
      () => DynamicsTabController(dynamicsType: widget.dynamicsType),
      tag: widget.dynamicsType.name,
    );
    super.initState();
  }

  Future<void> onRefresh() {
    dynamicsController.singleRefresh();
    return controller.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TvRegion(
      // 一块栏 = 一块区域：进页面（[TvRouteFocusObserver] 按
      // `TvRegions.entryNodeFor` 挑入口）或者切栏之后，焦点能落到本栏第一条
      // 动态上；列表还没加载出来时入口是空的，会退到当前选中的那个 tab。
      //
      // 标签必须**一栏一个**：切走的栏被 `TabBarView` 用 KeepAlive 留在树上，
      // 区域也还登记着，标签撞了的话 `TvRegions.focusFirst` 会找错栏。
      debugLabel: DynamicsTabPage.tvRegionOf(widget.dynamicsType),
      child: refreshIndicator(
        onRefresh: onRefresh,
        child: Obx(() {
          final livePanelPosition = dynamicsController.livePanelPosition.value;
          final showLive =
              livePanelPosition != LivePanelPosition.hidden &&
              context.showNavbar;
          // 板块优先：列表让出板块宽度+间距；列数受限且空间充足时
          // 卡片居中留白，板块叠放于留白内，空间不足时卡片收缩铺满
          final panelSpace = showLive
              ? Style.waterfallMargin + Style.livePanelWidth
              : 0.0;
          final leftPadding =
              Style.waterfallMargin +
              (livePanelPosition == LivePanelPosition.left ? panelSpace : 0);
          final rightPadding =
              Style.waterfallMargin +
              (livePanelPosition == LivePanelPosition.right ? panelSpace : 0);
          // UP主栏随页面滚动开启且位于顶部时，
          // UP主栏与直播栏作为列表顶部内容，与列表同宽并一起滚动
          final showTopBars =
              dynamicsController.upPanelPosition.value == UpPanelPosition.top &&
              Pref.upPanelFollowPage;
          final state = dynamicsController.loadingState.value;
          final response = state is Success<FollowUpModel>
              ? state.response
              : null;
          final showLiveBar =
              showTopBars &&
              !showLive &&
              response?.liveUsers?.items?.isNotEmpty == true;
          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: controller.scrollController,
            // 让下一屏留在焦点树里，方向键才能走到下面那些卡片
            scrollCacheExtent: TvFocusSpec.cacheExtent,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  left: leftPadding,
                  right: rightPadding,
                ),
                sliver: showTopBars
                    ? SliverToBoxAdapter(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: Style.waterfallMargin,
                              ),
                              child: UpPanelSection(
                                dynamicsController: dynamicsController,
                              ),
                            ),
                            if (showLiveBar)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Style.waterfallMargin,
                                ),
                                child: TopLiveBar(upData: response!),
                              ),
                          ],
                        ),
                      )
                    : const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  left: leftPadding,
                  top: Style.waterfallMargin,
                  right: rightPadding,
                  bottom: 100,
                ),
                sliver: _buildBody(controller.loadingState.value),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<DynamicItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => dynSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverWaterfallFlow(
                gridDelegate: dynGridDelegate,
                delegate: SliverChildBuilderDelegate(
                  (_, index) => _itemBuilder(response, index),
                  childCount: response.length,
                ),
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget _itemBuilder(List<DynamicItemModel> list, int index) {
    if (index == list.length - 1) {
      controller.onLoadMore();
    }
    final item = list[index];
    return DynamicPanel(
      item: item,
      onRemove: (idStr) => controller.onRemove(index, idStr),
      onBlock: () => controller.onBlock(index),
      onUnfold: () => controller.onUnfold(item, index),
    );
  }
}
