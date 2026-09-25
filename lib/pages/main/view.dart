import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/common/assets.dart';
import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/common/widgets/floating_navigation_bar.dart';
import 'package:PiliPlus/common/widgets/flutter/pop_scope.dart';
import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/common/widgets/focus/tv_input_mode.dart';
import 'package:PiliPlus/common/widgets/focus/tv_region.dart';
import 'package:PiliPlus/common/widgets/image/network_img_layer.dart';
import 'package:PiliPlus/common/widgets/main_layout.dart';
import 'package:PiliPlus/common/widgets/route_aware_mixin.dart';
import 'package:PiliPlus/models/common/dynamic/dynamics_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/dynamics_tab/view.dart';
import 'package:PiliPlus/pages/home/view.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:PiliPlus/pages/main/widgets/tablet_nav_item.dart';
import 'package:PiliPlus/pages/main/widgets/tv_nav_destination.dart';
import 'package:PiliPlus/pages/mine/view.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:PiliPlus/utils/android/android_helper.dart';
import 'package:PiliPlus/utils/app_scheme.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/extension/theme_ext.dart';
import 'package:PiliPlus/utils/mobile_observer.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart' as kernel32;
import 'package:window_manager/window_manager.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends PopScopeState<MainApp>
    with
        RouteAware,
        RouteAwareMixin,
        WidgetsBindingObserver,
        WindowListener,
        TrayListener {
  final _mainController = Get.put(MainController());
  late final _setting = GStorage.setting;
  Timer? _windowBoundsDebounce;
  late EdgeInsets _padding;
  late ColorScheme _colorScheme;
  Brightness? _brightness;

  /// 切页交接的代数：切一栏加一，让上一次还没跑完的重试自动作废。
  int _navHandOffId = 0;
  int _navHandOffFrames = 0;

  @override
  bool get initCanPop => false;

  @override
  void initState() {
    super.initState();
    addObserverMobile(this);
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      windowManager
        ..addListener(this)
        ..setPreventClose(true);
      if (_mainController.showTrayIcon) {
        trayManager.addListener(this);
        _handleTray();
      }
    } else {
      // FlutterSmartDialog throws
      PiliScheme.init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _padding = MediaQuery.viewPaddingOf(context);
    _colorScheme = ColorScheme.of(context);
    final brightness = _colorScheme.brightness;
    NetworkImgLayer.reduce =
        NetworkImgLayer.reduceLuxColor != null && brightness.isDark;
    if (PlatformUtils.isDesktop) {
      if (_brightness != brightness) {
        _brightness = brightness;
        windowManager.setBrightness(brightness);
      }
    }
    if (!_mainController.useSideBar) {
      _mainController.useBottomNav = MediaQuery.sizeOf(context).isPortrait;
    }
  }

  @override
  void didPopNext() {
    addObserverMobile(this);
    _mainController
      ..checkUnreadDynamic()
      ..checkDefaultSearch(true)
      ..checkUnread(_mainController.useBottomNav);
    super.didPopNext();
  }

  @override
  void didPushNext() {
    removeObserverMobile(this);
    super.didPushNext();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _mainController
        ..checkUnreadDynamic()
        ..checkDefaultSearch(true)
        ..checkUnread(_mainController.useBottomNav);
    }
  }

  @override
  void dispose() {
    _windowBoundsDebounce?.cancel();
    if (Platform.isMacOS) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    if (PlatformUtils.isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
    removeObserverMobile(this);
    PiliScheme.listener?.cancel();
    GStorage.close();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyR &&
        HardwareKeyboard.instance.isMetaPressed &&
        _mainController.refreshRecommendations();
  }

  @override
  void onWindowMaximize() {
    _setting.put(SettingBoxKey.isWindowMaximized, true);
  }

  @override
  void onWindowUnmaximize() {
    _setting.put(SettingBoxKey.isWindowMaximized, false);
  }

  void _saveWindowBoundsDebounced() {
    _windowBoundsDebounce?.cancel();
    _windowBoundsDebounce = Timer(const Duration(milliseconds: 300), () async {
      _windowBoundsDebounce = null;
      // 窗口全屏期间窗口铺满显示器，此时的尺寸/位置不是用户想要的窗口
      // 大小（关闭窗口全屏后启动要靠这份记录），不保存。
      if (Pref.windowFullScreen) {
        return;
      }
      if (PlPlayerController.instance?.isDesktopPip ?? false) {
        return;
      }
      final Rect bounds = await windowManager.getBounds();
      _setting.putAll({
        SettingBoxKey.windowSize: [bounds.width, bounds.height],
        SettingBoxKey.windowPosition: [bounds.left, bounds.top],
      });
    });
  }

  @override
  void onWindowMoved() {
    _saveWindowBoundsDebounced();
  }

  @override
  void onWindowResized() {
    _saveWindowBoundsDebounced();
  }

  @override
  void onWindowClose() {
    if (_mainController.showTrayIcon && _mainController.minimizeOnExit) {
      _hide();
      _onHideWindow();
    } else {
      _onClose();
    }
  }

  Future<void> _onClose() async {
    await GStorage.compact();
    await GStorage.close();
    await trayManager.destroy();
    if (Platform.isWindows) {
      // 全屏状态下直接关闭窗口时退出流程不走 exitDesktopFullScreen，
      // 先恢复任务栏再结束进程。
      restoreAllTaskbars();
      // flutter_inappwebview
      // 6.2.0-beta.2+ https://github.com/pichillilorenzo/flutter_inappwebview/issues/2482
      // 6.1.5 https://github.com/pichillilorenzo/flutter_inappwebview/issues/2512#issuecomment-3031039587
      final hProcess = kernel32.GetCurrentProcess();
      kernel32.TerminateProcess(hProcess, 0);
    } else {
      exit(0);
    }
  }

  @override
  void onWindowMinimize() {
    _onHideWindow();
  }

  @override
  void onWindowRestore() {
    _onShowWindow();
  }

  void _onHideWindow() {
    if (Pref.windowFullScreen) {
      // 窗口全屏期间任务栏是隐藏的，窗口不可见时不该继续占着它；
      // 重新显示时由 _onShowWindow 再隐藏回去。
      restoreAllTaskbars();
    }
    if (_mainController.pauseOnMinimize) {
      if (PlPlayerController.instance case final player?) {
        if (_mainController.isPlaying = player.playerStatus.isPlaying) {
          player.pause();
        }
      } else {
        _mainController.isPlaying = false;
      }
    }
  }

  void _onShowWindow() {
    if (Pref.windowFullScreen) {
      unawaited(enterWindowFullScreen());
    }
    if (_mainController.pauseOnMinimize && _mainController.isPlaying) {
      PlPlayerController.instance?.play();
    }
  }

  double? _opacity;

  Future<void>? _setOpacity(double opacity) {
    if (Platform.isWindows && _opacity != opacity) {
      _opacity = opacity;
      return windowManager.setOpacity(opacity);
    }
    return null;
  }

  @override
  Future<void>? onWindowFocus() {
    return _setOpacity(1.0);
  }

  /// https://github.com/leanflutter/window_manager/issues/571
  ///
  /// 先隐藏再置透明：若任一步失败，都不会留下"可见但透明"的窗口
  /// （失败时要么窗口仍可见不透明，要么已隐藏）。
  Future<void> _hide() async {
    await windowManager.hide();
    if (Platform.isWindows) {
      await windowManager.setOpacity(0.0);
    }
  }

  Future<void> _show() {
    return windowManager.show();
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      _onHideWindow();
      _hide();
    } else {
      _onShowWindow();
      _show();
    }
  }

  @override
  Future<void> onTrayIconRightMouseDown() async {
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _show();
      case 'exit':
        _onClose();
    }
  }

  Future<void> _handleTray() async {
    if (Platform.isWindows) {
      await trayManager.setIcon(Assets.logoIco);
    } else {
      await trayManager.setIcon(Assets.logoLarge);
    }
    if (!Platform.isLinux) {
      await trayManager.setToolTip(Constants.appName);
    }

    Menu trayMenu = Menu(
      items: [
        MenuItem(key: 'show', label: '显示窗口'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: '退出 ${Constants.appName}'),
      ],
    );
    await trayManager.setContextMenu(trayMenu);
  }

  @pragma('vm:prefer-inline')
  static void _onBack() {
    if (Platform.isAndroid) {
      PiliAndroidHelper.back();
    }
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (_mainController.directExitOnBack) {
      _onBack();
    } else {
      if (_mainController.selectedIndex.value != 0) {
        // 走 [_selectNav] 而不是直接 `setIndex`：返回键（遥控器/手柄 B）切回首页
        // 之后，焦点要跟着从"看不见的那一栏"回到首页入口，否则预选框留在
        // 动态/我的页的卡片上——那一栏已经不在屏幕上了。
        _selectNav(0);
        _mainController
          ..barOffset?.value = 0.0
          ..showBottomBar?.value = true
          ..setSearchBar();
      } else {
        _onBack();
      }
    }
  }

  /// 切页——底栏三支、平板抽屉、侧栏的导航项都走这里（`onDestinationSelected`
  /// / `onTap` 原本直接指向 `_mainController.setIndex`）。
  ///
  /// 除了切页本身，它还负责**按键切页之后把焦点送进新页面**：手柄停在底栏上
  /// 按确定切到「动态」，焦点要是留在底栏那一格上，用户还得再按一次 →
  /// 才进得了内容区。所以这里判定"这一下是按键/手柄"
  /// （[TvInputMode.fromKeys]）就把焦点送进去；**鼠标/触摸点一下不抢**——
  /// 鼠标用户点哪儿焦点就在哪儿（`TvInputMode.focusAt`），再替他跳一下反而奇怪。
  void _selectNav(int index) {
    _mainController.setIndex(index);
    if (!TvInputMode.fromKeys) return;
    final navigationBars = _mainController.navigationBars;
    if (index < 0 || index >= navigationBars.length) return;
    _handOffNavFocus(_tvRegionOf(navigationBars[index]));
  }

  /// 这个导航项对应的**当前**内容区标签，没有就返回 null（焦点留在原地）。
  ///
  /// 主界面这一层问不出"目标页注册了哪些区域"：三个页面共用一条路由，
  /// `TvRegions.entryNodeFor` 只认**最先登记**的那一块区域（也就是首页那块，
  /// 因为首页最先建出来），用它来交接等于把焦点送进看不见的页面。
  /// 所以按标签约定反查——各页面的 `tvRegion` 常量是唯一出处：
  ///
  /// - 首页：看当前选中的子栏（推荐 / 热门 / 直播各有一块区域；分区 / 番剧 /
  ///   影视还没接手柄适配，[HomeTabType.tvRegion] 返回 null）；
  /// - 动态：看当前选中的分类（`dynamics-<分类名>`）；
  /// - 我的：整页一块区域。
  String? _tvRegionOf(NavigationBarType nav) {
    switch (nav) {
      case NavigationBarType.home:
        final homeController = _mainController.homeController;
        return homeController.tabs[homeController.tabController.index].tvRegion;
      case NavigationBarType.dynamics:
        final tabController = _mainController.dynamicController.tabController;
        return DynamicsTabPage.tvRegionOf(
          DynamicsTabType.visibleValues[tabController.index],
        );
      case NavigationBarType.mine:
        return MinePage.tvRegion;
    }
  }

  /// 把焦点送进新页面的第一项。
  ///
  /// 目标区域可能还没建出来（懒加载的网络列表，切栏那一帧还是空的），所以按帧
  /// 重试几帧（同 `TvFocusOnOpen`）；一直等不到就把焦点留在导航项上——看得见，
  /// 按一下方向键也进得去，比送去一个不存在的落点强。
  ///
  /// 重试期间用户自己动了（按了方向键、又切了一栏）就收手，不抢焦点。
  void _handOffNavFocus(String? label) {
    if (label == null || !Pref.tvFocus) return;
    final id = ++_navHandOffId;
    // 起点是这一下按确定时的焦点（就是导航项自己）
    final from = FocusManager.instance.primaryFocus;
    void tryFocus(Duration _) {
      if (!mounted || id != _navHandOffId) return;
      if (TvRegions.focusFirst(label)) return;
      if (!identical(FocusManager.instance.primaryFocus, from)) return;
      if (++_navHandOffFrames < _navHandOffMaxFrames) {
        WidgetsBinding.instance.addPostFrameCallback(tryFocus);
      }
    }

    _navHandOffFrames = 0;
    WidgetsBinding.instance.addPostFrameCallback(tryFocus);
  }

  /// 最多重试几帧（≈330ms）：够 `TabBarView` 切过去 + 列表第一屏建出来。
  static const int _navHandOffMaxFrames = 20;

  Widget? get _bottomNav {
    Widget? bottomNav;
    if (_mainController.navigationBars.length > 1) {
      if (_mainController.floatingNavBar) {
        bottomNav = Obx(
          () => FloatingNavigationBar(
            onDestinationSelected: _selectNav,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => FloatingNavigationDestination(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    selectedIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      } else if (_mainController.enableMYBar) {
        bottomNav = Obx(
          () => NavigationBar(
            maintainBottomViewPadding: true,
            onDestinationSelected: _selectNav,
            selectedIndex: _mainController.selectedIndex.value,
            destinations: _mainController.navigationBars
                .map(
                  (e) => TvNavDestination(
                    debugLabel: 'nav-${e.name}',
                    // 这一格上下都贴着栏边，放大 4% 会把环顶到栏外面（见该类）
                    scale: 1.0,
                    child: NavigationDestination(
                      label: e.label,
                      icon: _buildIcon(type: e),
                      selectedIcon: _buildIcon(type: e, selected: true),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      } else {
        bottomNav = Obx(
          () => BottomNavigationBar(
            currentIndex: _mainController.selectedIndex.value,
            onTap: _selectNav,
            iconSize: 16,
            selectedFontSize: 12,
            unselectedFontSize: 12,
            type: .fixed,
            items: _mainController.navigationBars
                .map(
                  (e) => BottomNavigationBarItem(
                    label: e.label,
                    icon: _buildIcon(type: e),
                    activeIcon: _buildIcon(type: e, selected: true),
                  ),
                )
                .toList(),
          ),
        );
      }

      if (_mainController.hideBottomBar) {
        return Obx(() {
          switch (_mainController.barHideType.value) {
            case .instant:
              final showBottomBar =
                  _mainController.showBottomBar?.value ?? true;
              return AnimatedSlide(
                curve: Curves.easeInOutCubicEmphasized,
                duration: const Duration(milliseconds: 500),
                offset: Offset(0, showBottomBar ? 0 : 1),
                child: bottomNav,
              );
            case .sync:
              final barOffset = _mainController.barOffset?.value ?? 0.0;
              return FractionalTranslation(
                translation: Offset(0.0, barOffset / Style.topBarHeight),
                child: bottomNav,
              );
          }
        });
      }
    }

    return bottomNav;
  }

  Widget _sideBar() {
    if (_mainController.navigationBars.length > 1) {
      if (context.isTablet && _mainController.optTabletNav) {
        return Padding(
          padding: const .only(top: 25),
          child: MediaQuery.removePadding(
            context: context,
            removeRight: true,
            child: DrawerTheme(
              data: DrawerThemeData(width: 96 + _padding.left),
              child: NavigationDrawerTheme(
                data: NavigationDrawerThemeData(
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    return IconThemeData(
                      size: 28,
                      color: states.contains(WidgetState.selected)
                          ? _colorScheme.onSecondaryContainer
                          : _colorScheme.onSurfaceVariant,
                    );
                  }),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    return Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: states.contains(WidgetState.selected)
                              ? _colorScheme.onSecondaryContainer
                              : _colorScheme.onSurfaceVariant,
                        );
                  }),
                  // 焦点环和这条选中指示条共用同一个圆角（见 TabletNavItem）
                  indicatorShape: const RoundedRectangleBorder(
                    borderRadius: tabletNavTileRadius,
                  ),
                ),
                child: Obx(
                  () {
                    final selectedIndex = _mainController.selectedIndex.value;
                    return NavigationDrawer(
                      /// apply `lib/scripts/navigation_drawer.patch`
                      flex: 5,
                      backgroundColor: Colors.transparent,
                      header: Expanded(
                        flex: 4,
                        child: Padding(
                          // 头像紧贴在抽屉最上沿，而抽屉（`Drawer`）默认
                          // `clipBehavior: Clip.hardEdge`、裁剪线就是它自己的框：
                          // 焦点框放大 4% 往外顶的那不到 1dp（头像 34 / 未登录 38dp）
                          // 正好落在裁剪线外，环的顶上会被削平一条。这 4dp 和导航项
                          // 那圈 `tilePadding` 是同一个用途——给预选框的缩放让位
                          // （余量必须在抽屉**里面**，套在外面等于连裁剪线一起挪）
                          padding: const .only(top: 4),
                          child: userAndSearchVertical(),
                        ),
                      ),
                      // 导航项是自己搭的，不是 NavigationDrawerDestination：
                      // 后者内部那个 `InkWell` 自己建焦点节点、外面拿不到，
                      // 焦点预选框就画不出来（见 TabletNavItem）
                      children: [
                        for (final (index, e)
                            in _mainController.navigationBars.indexed)
                          TabletNavItem(
                            label: e.label,
                            icon: _buildIcon(type: e),
                            selectedIcon: _buildIcon(type: e, selected: true),
                            selected: index == selectedIndex,
                            debugLabel: 'tablet-nav-${e.name}',
                            onTap: () => _selectNav(index),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }
      // 窄侧栏（手机横屏走这支；电视/平板是上面那支抽屉）：导航项仍然是框架的
      // `NavigationRailDestination`，而它**不是 widget**（和
      // `BottomNavigationBarItem` 一样是个数据类），套不了 [TvNavDestination]。
      // 所以这里只有"焦点停上去有框架自带的底纹"，没有预选框——要补得上
      // 是自己搭一列导航项（照 `TabletNavItem` 抄），见 `docs/tv_focus.md`。
      // 切页交接不受影响：`onDestinationSelected` 一样走 [_selectNav]。
      return Obx(
        () => NavigationRail(
          groupAlignment: 0.5,
          labelType: .selected,
          leading: userAndSearchVertical(),
          backgroundColor: Colors.transparent,
          onDestinationSelected: _selectNav,
          selectedIndex: _mainController.selectedIndex.value,
          destinations: _mainController.navigationBars
              .map(
                (e) => NavigationRailDestination(
                  label: Text(e.label),
                  icon: _buildIcon(type: e),
                  selectedIcon: _buildIcon(type: e, selected: true),
                ),
              )
              .toList(),
        ),
      );
    }
    return Container(
      width: 80,
      margin: .only(top: 12 + _padding.top, left: _padding.left),
      child: userAndSearchVertical(),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (_mainController.mainTabBarView) {
      child = TabBarView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: _mainController.useBottomNav ? .horizontal : .vertical,
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    } else {
      child = PageView(
        controller: _mainController.controller,
        physics: const NeverScrollableScrollPhysics(),
        children: _mainController.navigationBars.map((i) => i.page).toList(),
      );
    }

    Widget? sideBar;
    Widget? bottomNav;
    final EdgeInsets padding;
    if (_mainController.useBottomNav) {
      bottomNav = _bottomNav;
      if (bottomNav != null) {
        bottomNav = MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: bottomNav,
        );
      }
      padding = .only(
        top: _padding.top,
        left: _padding.left,
        right: _padding.right,
      );
    } else {
      sideBar = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: _colorScheme.outline.withValues(alpha: 0.06),
            ),
          ),
        ),
        child: _sideBar(),
      );
      padding = .only(top: _padding.top, right: _padding.right);
    }

    child = Material(
      child: MainLayout(
        sideBar: sideBar,
        bottomNav: bottomNav,
        body: Padding(padding: padding, child: child),
      ),
    );

    if (PlatformUtils.isMobile) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: _colorScheme.brightness,
          statusBarIconBrightness: _colorScheme.brightness.reverse,
          systemStatusBarContrastEnforced: false,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: _colorScheme.brightness.reverse,
        ),
        child: child,
      );
    }

    return child;
  }

  Widget _buildIcon({required NavigationBarType type, bool selected = false}) {
    final icon = selected ? type.selectIcon : type.icon;
    return type == .dynamics
        ? Obx(
            () {
              final dynCount = _mainController.dynCount.value;
              return Badge(
                isLabelVisible: dynCount > 0,
                label: _mainController.dynamicBadgeMode == .number
                    ? Text(dynCount.toString())
                    : null,
                padding: const .symmetric(horizontal: 6),
                child: icon,
              );
            },
          )
        : icon;
  }

  Widget userAndSearchVertical() {
    return Column(
      children: [
        userAvatar(colorScheme: _colorScheme, mainController: _mainController),
        const SizedBox(height: 8),
        msgBadge(_mainController),
        _searchButton(),
      ],
    );
  }

  /// 搜索按钮（形状和上面那两颗一样：圆形预选框）。
  ///
  /// 手机竖屏顶栏那份 `searchBar` 是整条输入框，不走这里。
  Widget _searchButton() {
    /// [focusNode] 是 [circularFocusRing] 递进来的那一个；手柄模式关掉时
    /// 它是 null，`IconButton` 自己建节点（和改动前一样）。
    Widget build(FocusNode? focusNode) {
      return IconButton(
        focusNode: focusNode,
        tooltip: '搜索',
        icon: const Icon(
          Icons.search_outlined,
          semanticLabel: '搜索',
        ),
        onPressed: () => Get.toNamed(
          '/search',
          parameters: _mainController.homeController.searchParams,
        ),
      );
    }

    return circularFocusRing(debugLabel: '搜索', builder: build);
  }
}
