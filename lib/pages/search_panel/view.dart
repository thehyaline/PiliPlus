import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/flutter/refresh_indicator.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/search/search_type.dart';
import 'package:PiliPlus/models/search/result.dart';
import 'package:PiliPlus/pages/search_panel/controller.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// 桌面端面板内容区（网格与过滤器行）的左右内边距。
///
/// 与视频/直播面板的卡片区同口径：外层 [Style.safeSpace] 加上网格居中留白
/// [Grid.videoGridPadding]，因此各类型面板的内容块宽度和左右外边距与视频
/// 面板完全一致，切换类型时不会忽宽忽窄。移动端沿用卡片自带的内边距，
/// 这里返回 0（各面板保持原样）。
double searchPanelHPad(double crossAxisExtent) => PlatformUtils.isDesktop
    ? Style.safeSpace +
          Grid.videoGridPadding(crossAxisExtent - 2 * Style.safeSpace)
    : 0;

abstract class CommonSearchPanel extends StatefulWidget {
  const CommonSearchPanel({
    super.key,
    required this.keyword,
    required this.searchType,
    required this.tag,
  });

  final String keyword;
  final SearchType searchType;
  final String tag;
}

abstract class CommonSearchPanelState<
  S extends CommonSearchPanel,
  R extends SearchNumData<T>,
  T
>
    extends State<S>
    with AutomaticKeepAliveClientMixin {
  SearchPanelController<R, T> get controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    controller.cancelListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return refreshIndicator(
      onRefresh: controller.onRefresh,
      child: CustomScrollView(
        controller: controller.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ?buildHeader(theme),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewPaddingOf(context).bottom + 100,
            ),
            sliver: Obx(() => _buildBody(theme, controller.loadingState.value)),
          ),
        ],
      ),
    );
  }

  Widget get buildLoading;

  Widget _buildBody(ThemeData theme, LoadingState<List<T>?> loadingState) {
    return switch (loadingState) {
      Loading() => buildLoading,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? buildList(theme, response)
            : HttpError(onReload: controller.onReload),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: controller.onReload,
      ),
    };
  }

  Widget? buildHeader(ThemeData theme) => null;

  Widget buildList(ThemeData theme, List<T> list);
}
