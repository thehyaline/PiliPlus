import 'dart:math';

import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/dynamic/live_panel_position.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/live_panel_section.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/pages/dynamics_create/view.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/waterfall.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart' hide DraggableScrollableSheet;

class DynamicsPage extends StatefulWidget {
  const DynamicsPage({super.key});

  @override
  State<DynamicsPage> createState() => _DynamicsPageState();
}

class _DynamicsPageState extends CommonPageState<DynamicsPage>
    with AutomaticKeepAliveClientMixin {
  final _dynamicsController = Get.putOrFind(DynamicsController.new);
  UpPanelPosition get upPanelPosition => _dynamicsController.upPanelPosition;
  late final MainController _mainController = Get.find<MainController>();

  @override
  bool get wantKeepAlive => true;

  Widget _createDynamicBtn(ThemeData theme, {bool isRight = true}) => Container(
    width: 34,
    height: 34,
    margin: isRight ? const .only(right: 16) : const .only(left: 16),
    child: IconButton(
      tooltip: '发布动态',
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(
          theme.colorScheme.secondaryContainer,
        ),
      ),
      onPressed: () => CreateDynPanel.onCreateDyn(context),
      icon: Icon(
        Icons.add,
        size: 18,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    ),
  );

  Widget upPanelPart(ThemeData theme) {
    final isTop = upPanelPosition == .top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? .canvas : .transparency,
      color: needBg ? theme.colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 64,
        height: isTop ? 76 : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              _dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(() {
            final showLive =
                _dynamicsController.livePanelPosition.value !=
                        LivePanelPosition.hidden &&
                    context.showNavbar;
            return _buildUpPanel(
              _dynamicsController.loadingState.value,
              showLiveSection: !showLive,
            );
          }),
        ),
      ),
    );
  }

  Widget _buildUpPanel(
    LoadingState<FollowUpModel> upState, {
    bool showLiveSection = true,
  }) {
    return switch (upState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
          upData: response,
          dynamicsController: _dynamicsController,
          showLiveSection: showLiveSection,
        ),
      Error() => Center(
          child: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _dynamicsController.onReload,
          ),
        ),
    };
  }

  Widget livePanelPart(LivePanelPosition position) => Obx(
        () => switch (_dynamicsController.loadingState.value) {
          Success(:final response) =>
            LivePanelSection(upData: response, position: position),
          _ => const SizedBox.shrink(),
        },
      );

  bool get checkPage =>
      _mainController.navigationBars[0] != .dynamics &&
      _mainController.selectedIndex.value == 0;

  @override
  bool onNotificationType1(UserScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType1(notification);
  }

  @override
  bool onNotificationType2(ScrollNotification notification) {
    if (checkPage) {
      return false;
    }
    return super.onNotificationType2(notification);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    Widget? drawer;
    Widget? endDrawer;

    Widget? leading;
    Widget actions;

    Widget child = tabBarView(
      controller: _dynamicsController.tabController,
      children: DynamicsTabType.values
          .map((e) => DynamicsTabPage(dynamicsType: e))
          .toList(),
    );

    Widget? upPanelTop;
    Widget? upPanelLeft;
    Widget? upPanelRight;

    switch (upPanelPosition) {
      case .top:
        upPanelTop = upPanelPart(theme);
        actions = _createDynamicBtn(theme);
      case .leftFixed:
        upPanelLeft = upPanelPart(theme);
        actions = _createDynamicBtn(theme);
      case .rightFixed:
        upPanelRight = upPanelPart(theme);
        actions = _createDynamicBtn(theme);
      case .leftDrawer:
        drawer = upPanelPart(theme);
        actions = _createDynamicBtn(theme);
        leading = const DrawerButton();
      case .rightDrawer:
        endDrawer = upPanelPart(theme);
        leading = _createDynamicBtn(theme, isRight: false);
        actions = const EndDrawerButton();
    }

    if (upPanelTop case final upPanel?) {
      child = Column(
        children: [
          upPanel,
          Expanded(child: child),
        ],
      );
    }

    final baseChild = child;
    child = Obx(() {
      final livePanelPosition = _dynamicsController.livePanelPosition.value;
      final showLive =
          livePanelPosition != LivePanelPosition.hidden && context.showNavbar;
      final livePanel = showLive ? livePanelPart(livePanelPosition) : null;
      // 板块优先：列表可用宽度先减去板块宽度+间距（让位，见 dynamics_tab）。
      // 列数受限且空间充足时卡片保持最大宽度居中留白，板块叠放于留白内贴卡片；
      // 空间不足时卡片收缩铺满，板块贴列表区域边缘。板块高度随内容自适应（顶部对齐）
      final content = showLive
          ? LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                const gap = Style.waterfallMargin;
                final extent = width - Style.livePanelWidth - 3 * gap;
                final metrics = dynGridMetrics(extent);
                final offset = max(0.0, (extent - metrics.gridWidth) / 2);
                final panel = SizedBox(
                  width: Style.livePanelWidth,
                  child: livePanel,
                );
                return Stack(
                  children: [
                    baseChild,
                    if (livePanelPosition == LivePanelPosition.left)
                      Positioned(left: gap + offset, top: 0, child: panel),
                    if (livePanelPosition == LivePanelPosition.right)
                      Positioned(
                        left: width - gap - offset - Style.livePanelWidth,
                        top: 0,
                        child: panel,
                      ),
                  ],
                );
              },
            )
          : baseChild;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?upPanelLeft,
          Expanded(child: content),
          ?upPanelRight,
        ],
      );
    });

    return Scaffold(
      primary: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const .fromHeight(50),
        child: Row(
          children: [
            ?leading,
            Expanded(
              child: TabBar(
                dividerHeight: 0,
                isScrollable: true,
                tabAlignment: .start,
                dividerColor: Colors.transparent,
                labelColor: theme.colorScheme.primary,
                indicatorColor: theme.colorScheme.primary,
                controller: _dynamicsController.tabController,
                unselectedLabelColor: theme.colorScheme.onSurface,
                labelStyle:
                    TabBarTheme.of(
                      context,
                    ).labelStyle?.copyWith(fontSize: 13) ??
                    const TextStyle(fontSize: 13),
                tabs: DynamicsTabType.values
                    .map((e) => Tab(text: e.label))
                    .toList(),
                onTap: (index) {
                  if (!_dynamicsController.tabController.indexIsChanging) {
                    _dynamicsController.animateToTop();
                  }
                },
              ),
            ),
            actions,
          ],
        ),
      ),
      drawer: drawer,
      endDrawer: endDrawer,
      body: onBuild(child),
    );
  }
}
