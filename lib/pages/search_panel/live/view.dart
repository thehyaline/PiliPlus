import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search_panel/controller.dart';
import 'package:PiliPlus/pages/search_panel/live/widgets/item.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class SearchLivePanel extends CommonSearchPanel {
  const SearchLivePanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchLivePanel> createState() => _SearchLivePanelState();
}

class _SearchLivePanelState
    extends
        CommonSearchPanelState<
          SearchLivePanel,
          SearchLiveData,
          SearchLiveItemModel
        > {
  @override
  late final SearchPanelController<SearchLiveData, SearchLiveItemModel>
  controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchPanelController<SearchLiveData, SearchLiveItemModel>(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );
  }

  // 桌面端沿用主页推荐流竖版列表样式，移动端保持原样式
  SliverGridDelegate get gridDelegate => PlatformUtils.isDesktop
      ? Grid.videoCardVDelegate(
          mainAxisExtent: MediaQuery.textScalerOf(
            context,
          ).scale(Style.videoCardContentHeight),
        )
      : SliverGridDelegateWithExtentAndRatio(
          maxCrossAxisExtent: Grid.smallCardWidth,
          crossAxisSpacing: Style.cardSpace,
          mainAxisSpacing: Style.cardSpace,
          childAspectRatio: Style.aspectRatio,
          mainAxisExtent: MediaQuery.textScalerOf(context).scale(80),
        );

  @override
  Widget buildList(ThemeData theme, List<SearchLiveItemModel> list) {
    return SliverPadding(
      padding: const EdgeInsets.only(
        left: Style.safeSpace,
        right: Style.safeSpace,
      ),
      sliver: SliverGrid.builder(
        gridDelegate: gridDelegate,
        itemBuilder: (context, index) {
          if (index == list.length - 1) {
            controller.onLoadMore();
          }
          return LiveItem(
            liveItem: list[index],
            useNewStyle: PlatformUtils.isDesktop,
          );
        },
        itemCount: list.length,
      ),
    );
  }

  @override
  Widget get buildLoading => SliverPadding(
    padding: const EdgeInsets.only(
      left: Style.safeSpace,
      right: Style.safeSpace,
    ),
    sliver: SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) => const VideoCardVSkeleton(),
      itemCount: 10,
    ),
  );
}
