import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/focus/tv_card.dart';
import 'package:PiliPlus/common/widgets/focus/tv_focus_memory.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/hot/controller.dart';
import 'package:PiliPlus/pages/rank/view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class HotPage extends StatefulWidget {
  const HotPage({super.key});

  /// TV 焦点区域的标签（`TvRegion.debugLabel`）：切栏之后靠它把焦点送回这个列表
  /// （见 `TvRegions.focusFirst`），所以要和首页 tab 那边的映射对上。
  static const tvRegion = 'home-hot-list';

  @override
  State<HotPage> createState() => _HotPageState();
}

class _HotPageState extends State<HotPage>
    with AutomaticKeepAliveClientMixin, GridMixin {
  final HotController controller = Get.put(HotController());

  @override
  bool get wantKeepAlive => true;

  Widget _buildEntranceItem({
    required String iconUrl,
    required String title,
    required VoidCallback onTap,
  }) {
    // 这三个入口原本是纯 GestureDetector，手柄选不中；包成 TvCard 就进焦点树了
    return TvCard(
      onTap: onTap,
      surface: tvCardSurface,
      radius: Style.mdRadius,
      child: Padding(
        padding: const .symmetric(horizontal: 10, vertical: 4),
        child: Column(
          spacing: 4,
          mainAxisSize: MainAxisSize.min,
          children: [
            NetworkImgLayer(
              width: 35,
              height: 35,
              type: .emote,
              src: iconUrl,
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      // 焦点缩放（1.04）在左右边沿会被视口裁切，留出安全内边距
      margin: const .symmetric(horizontal: TvFocusSpec.safeSpace),
      child: TvRegion(
        debugLabel: HotPage.tvRegion,
        child: refreshIndicator(
          onRefresh: () async {
            // 刷新会把整张列表换掉，焦点先寄存在列表里
            TvFocusMemory.park();
            await controller.onRefresh();
            TvFocusMemory.restore();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: controller.scrollController,
            // 让下一行留在焦点树里，方向键才能走到下一行
            scrollCacheExtent: TvFocusSpec.cacheExtent,
            slivers: [
              if (Pref.showHotRcmd)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const .only(top: 12, bottom: 4),
                    child: Row(
                      mainAxisAlignment: .spaceEvenly,
                      children: [
                        _buildEntranceItem(
                          iconUrl: 'https://i0.hdslb.com/bfs/archive/a3f11218aaf4521b4967db2ae164ecd3052586b9.png',
                          title: '排行榜',
                          onTap: () {
                            try {
                              final homeController = Get.find<HomeController>();
                              final index = homeController.tabs.indexOf(
                                HomeTabType.rank,
                              );
                              if (index != -1) {
                                homeController.tabController.animateTo(index);
                              } else {
                                Get.to(
                                  SimpleScaffold(
                                    appBar: AppBar(title: const Text('排行榜')),
                                    body: const ViewSafeArea(child: RankPage()),
                                  ),
                                );
                              }
                            } catch (_) {}
                          },
                        ),
                        _buildEntranceItem(
                          iconUrl: 'https://i0.hdslb.com/bfs/archive/552ebe8c4794aeef30ebd1568b59ad35f15e21ad.png',
                          title: '每周必看',
                          onTap: () => Get.toNamed('/popularSeries'),
                        ),
                        _buildEntranceItem(
                          iconUrl: 'https://i0.hdslb.com/bfs/archive/3693ec9335b78ca57353ac0734f36a46f3d179a9.png',
                          title: '入站必刷',
                          onTap: () => Get.toNamed('/popularPrecious'),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.only(top: 7, bottom: 100),
                sliver: Obx(
                  () => _buildBody(controller.loadingState.value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  if (index == response.length - 1) {
                    TvFocusMemory.park();
                    controller.onLoadMore();
                    TvFocusMemory.restore();
                  }
                  return VideoCardH(
                    videoItem: response[index],
                    // 有「排行榜 / 每周必看 / 入站必刷」入口时首项不是页面上的第一个焦点
                    autofocus: index == 0 && !Pref.showHotRcmd,
                    onRemove: () {
                      TvFocusMemory.park();
                      controller.loadingState
                        ..value.data!.removeAt(index)
                        ..refresh();
                      TvFocusMemory.restore(preferIndex: index);
                    },
                  );
                },
                itemCount: response.length,
              )
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }
}
