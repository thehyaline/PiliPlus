import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/custom_height_widget.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/focus/tv_section_switcher.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/scroll_physics.dart' show tabBarView;
import 'package:PiliPlus/pages/common/common_page.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/mine/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends CommonPageState<HomePage>
    with AutomaticKeepAliveClientMixin {
  /// TabBar 这一条也当成一个焦点区域，方便手柄切栏之后有地方落脚
  static const _tabBarRegion = 'home-tabbar';

  late ColorScheme _colorScheme;
  final _homeController = Get.putOrFind(HomeController.new);
  final _mainController = Get.find<MainController>();

  @override
  bool get needsCorrection => _homeController.hideTopBar;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colorScheme = ColorScheme.of(context);
  }

  /// L1/R1 切栏（[TvSectionSwitcher] 调过来）。
  ///
  /// 切栏之后焦点还留在旧栏：那一页没被销毁，只是看不见了——这时按确定会打开
  /// 旧栏的视频，所以必须把焦点接走。新栏已经接过手柄适配（有 `TvRegion`）就送
  /// 进它的第一张卡；还没有（分区/番剧/影视）或者它还停在很下面、首项没被懒加载
  /// 构建出来时，把焦点放到 TabBar 上：看得见，按 ↓ 还能进新栏的列表。
  void _switchTab(int offset) {
    final tabController = _homeController.tabController;
    if (tabController.indexIsChanging) return;
    final target = tabController.index + offset;
    if (target < 0 || target >= tabController.length) return;
    tabController.animateTo(target);
    // 等这一帧把新栏建出来，下一帧再把焦点送进去
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final region = _homeController.tabs[target].tvRegion;
      if (region != null && TvRegions.focusFirst(region)) return;
      TvRegions.focusFirst(_tabBarRegion, index: target);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget tabBar;
    if (_homeController.tabs.length > 1) {
      tabBar = TvRegion(
        debugLabel: _tabBarRegion,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: SizedBox(
            height: 42,
            width: double.infinity,
            child: TabBar(
              controller: _homeController.tabController,
              tabs: _homeController.tabs
                  .map((e) => Tab(text: e.label))
                  .toList(),
              isScrollable: true,
              dividerColor: Colors.transparent,
              dividerHeight: 0,
              splashBorderRadius: Style.mdRadius,
              tabAlignment: TabAlignment.center,
              onTap: (_) {
                feedBack();
                if (!_homeController.tabController.indexIsChanging) {
                  _homeController.animateToTop();
                }
              },
            ),
          ),
        ),
      );
      if (_homeController.hideTopBar) {
        final baseTabBar = tabBar;
        tabBar = Obx(
          () => _mainController.barHideType.value == .instant
              ? Material(
                  color: _colorScheme.surface,
                  child: baseTabBar,
                )
              : baseTabBar,
        );
      }
    } else {
      tabBar = const SizedBox(height: 6);
    }
    return TvSectionSwitcher(
      // 手柄 L1/R1 切栏；只有一栏时不接键，让 L1/R1 放行给别人
      onPrev: _homeController.tabs.length > 1 ? () => _switchTab(-1) : null,
      onNext: _homeController.tabs.length > 1 ? () => _switchTab(1) : null,
      child: Column(
        children: [
          if (!_mainController.useSideBar &&
              MediaQuery.sizeOf(context).isPortrait)
            customAppBar(),
          tabBar,
          Expanded(
            child: onBuild(
              tabBarView(
                controller: _homeController.tabController,
                children: _homeController.tabs.map((e) => e.page).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget customAppBar() {
    const padding = EdgeInsets.fromLTRB(14, 6, 14, 0);
    final child = Row(
      children: [
        searchBar(),
        const SizedBox(width: 4),
        msgBadge(_mainController),
        const SizedBox(width: 8),
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
      ],
    );
    if (_homeController.hideTopBar) {
      return Obx(() {
        switch (_mainController.barHideType.value) {
          case .instant:
            final showTopBar = _homeController.showTopBar?.value ?? true;
            return AnimatedOpacity(
              opacity: showTopBar ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: AnimatedContainer(
                curve: Curves.easeInOutCubicEmphasized,
                duration: const Duration(milliseconds: 500),
                height: showTopBar ? Style.topBarHeight : 0,
                padding: padding,
                child: child,
              ),
            );
          case .sync:
            final offset = _mainController.barOffset?.value ?? 0.0;
            return CustomHeightWidget(
              offset: Offset(0, -offset),
              height: Style.topBarHeight - offset,
              child: Padding(
                padding: padding,
                child: child,
              ),
            );
        }
      });
    }
    return Container(
      height: Style.topBarHeight,
      padding: padding,
      child: child,
    );
  }

  Widget searchBar() {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    return Expanded(
      child: SizedBox(
        height: 44,
        child: Material(
          borderRadius: borderRadius,
          color: _colorScheme.onSecondaryContainer.withValues(alpha: 0.05),
          child: InkWell(
            borderRadius: borderRadius,
            splashColor: _colorScheme.primaryContainer.withValues(
              alpha: 0.3,
            ),
            onTap: () => Get.toNamed(
              '/search',
              parameters: _homeController.searchParams,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.search_outlined,
                  color: _colorScheme.onSecondaryContainer,
                  semanticLabel: '搜索',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Obx(
                    () => Text(
                      _homeController.defaultSearch.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _colorScheme.outline),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget userAvatar({
  required ColorScheme colorScheme,
  required MainController mainController,
}) {
  return Semantics(
    label: "我的",
    child: Obx(
      () {
        if (mainController.accountService.isLogin.value) {
          return Stack(
            clipBehavior: .none,
            children: [
              NetworkImgLayer(
                type: .avatar,
                width: 34,
                height: 34,
                src: mainController.accountService.face.value,
              ),
              Positioned.fill(
                child: Material(
                  type: .transparency,
                  child: InkWell(
                    onTap: mainController.toMemberPage,
                    splashColor: colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    customBorder: const CircleBorder(),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: Obx(
                  () => MineController.anonymity.value
                      ? IgnorePointer(
                          child: Container(
                            padding: const .all(2),
                            decoration: BoxDecoration(
                              shape: .circle,
                              color: colorScheme.secondaryContainer,
                            ),
                            child: Icon(
                              size: 14,
                              MdiIcons.incognito,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          );
        }
        return SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: '点击登录',
            style: IconButton.styleFrom(
              padding: .zero,
              backgroundColor: colorScheme.onInverseSurface,
            ),
            onPressed: mainController.toMemberPage,
            icon: Icon(
              Icons.person_rounded,
              size: 22,
              color: colorScheme.primary,
            ),
          ),
        );
      },
    ),
  );
}

Widget msgBadge(MainController mainController) {
  return Obx(
    () {
      if (mainController.accountService.isLogin.value) {
        final count = mainController.msgUnReadCount.value;
        final isNumBadge = mainController.msgBadgeMode == .number;
        return IconButton(
          tooltip: '消息',
          onPressed: () {
            mainController
              ..clearUnreadMsg()
              ..lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
            Get.toNamed('/whisper');
          },
          icon: Badge(
            isLabelVisible:
                mainController.msgBadgeMode != .hidden && count != null,
            alignment: isNumBadge
                ? const Alignment(0.0, -0.85)
                : const Alignment(1.0, -0.85),
            label: isNumBadge && count != null ? Text(count) : null,
            child: const Icon(Icons.notifications_none),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );
}
