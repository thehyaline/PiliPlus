import 'package:PiliPlus/common/skeleton/video_card_h.dart';
import 'package:PiliPlus/common/skeleton/video_card_v.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_floating_header.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/models/common/search/video_search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search/widgets/search_text.dart';
import 'package:PiliPlus/pages/search_panel/video/controller.dart';
import 'package:PiliPlus/pages/search_panel/video/widgets/video_card_v.dart';
import 'package:PiliPlus/pages/search_panel/view.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';

class SearchVideoPanel extends CommonSearchPanel {
  const SearchVideoPanel({
    super.key,
    required super.keyword,
    required super.tag,
    required super.searchType,
  });

  @override
  State<SearchVideoPanel> createState() => _SearchVideoPanelState();
}

class _SearchVideoPanelState
    extends
        CommonSearchPanelState<
          SearchVideoPanel,
          SearchVideoData,
          SearchVideoItemModel
        > {
  @override
  late final SearchVideoController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(
      SearchVideoController(
        keyword: widget.keyword,
        searchType: widget.searchType,
        tag: widget.tag,
      ),
      tag: widget.searchType.name + widget.tag,
    );
  }

  // 桌面端沿用主页推荐流竖版列表样式，移动端保持原横向列表
  late final gridDelegate = PlatformUtils.isDesktop
      ? Grid.videoCardVDelegate(
          mainAxisExtent: MediaQuery.textScalerOf(
            context,
          ).scale(Style.videoCardContentHeight),
        )
      : Grid.videoCardHDelegate();

  @override
  Widget buildHeader(ThemeData theme) {
    return SliverFloatingHeaderWidget(
      backgroundColor: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 桌面端头部与网格卡片区域对齐：外边距 + 网格居中留白
          final hPad = PlatformUtils.isDesktop
              ? Style.safeSpace +
                    Grid.videoGridPadding(
                      constraints.maxWidth - 2 * Style.safeSpace,
                    )
              : Style.safeSpace;
          return Padding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 4),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Wrap(
                      children: [
                        for (final e in ArchiveFilterType.values)
                          Obx(
                            () => SearchText(
                              fontSize: 13,
                              text: e.desc,
                              bgColor: Colors.transparent,
                              textColor: controller.selectedType.value == e
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              onTap: (_) => controller
                                ..order = e.name
                                ..selectedType.value = e
                                ..onSortSearch(getBack: false),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(indent: 7, endIndent: 8),
                const SizedBox(width: 3),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    tooltip: '筛选',
                    style: const ButtonStyle(
                      padding: WidgetStatePropertyAll(EdgeInsets.zero),
                    ),
                    onPressed: () => controller.onShowFilterDialog(context),
                    icon: Icon(
                      Icons.filter_list_outlined,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildList(ThemeData theme, List<SearchVideoItemModel> list) {
    final grid = SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (context, index) {
        if (index == list.length - 1) {
          controller.onLoadMore();
        }
        if (PlatformUtils.isDesktop) {
          return SearchVideoCardV(
            videoItem: list[index],
            onRemove: () => controller.loadingState
              ..value.data!.removeAt(index)
              ..refresh(),
          );
        }
        return VideoCardH(
          videoItem: list[index],
          onRemove: () => controller.loadingState
            ..value.data!.removeAt(index)
            ..refresh(),
        );
      },
      itemCount: list.length,
    );
    // 桌面端与主页推荐流一致留出外边距，移动端保持原样
    return PlatformUtils.isDesktop
        ? SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
            sliver: grid,
          )
        : grid;
  }

  @override
  Widget get buildLoading {
    final grid = SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemBuilder: (_, _) => PlatformUtils.isDesktop
          ? const VideoCardVSkeleton()
          : const VideoCardHSkeleton(),
      itemCount: 10,
    );
    return PlatformUtils.isDesktop
        ? SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
            sliver: grid,
          )
        : grid;
  }
}
