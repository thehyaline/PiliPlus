import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/grpc/dyn.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/http/msg.dart';
import 'package:PiliPlus/models/common/bar_hide_type.dart';
import 'package:PiliPlus/models/common/dynamic/dynamic_badge_mode.dart';
import 'package:PiliPlus/models/common/home_tab_type.dart';
import 'package:PiliPlus/models/common/msg/msg_unread_type.dart';
import 'package:PiliPlus/models/common/nav_bar_config.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/services/account_service.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/extension/iterable_ext.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/update.dart';
import 'package:collection/collection.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class MainController extends GetxController
    with GetSingleTickerProviderStateMixin, AccountMixin {
  @override
  final AccountService accountService = Get.find<AccountService>();

  List<NavigationBarType> navigationBars = <NavigationBarType>[];

  RxDouble? barOffset;
  RxBool? showBottomBar;
  late final bool hideBottomBar;
  final barHideType = Pref.barHideType.obs;
  /// 主界面这一帧走不走**手机档**（底部导航栏 + 顶栏那一套）。
  ///
  /// [MainApp] 每次依赖变化都按 [useBottomNavOf] 重算一遍存下来：拿得到 context
  /// 的页面直接用那个函数（顺带把 MediaQuery 依赖注册上，const 单例的首页 /
  /// 我的页才跟着窗口缩放重建），拿不到 context 的（滚动收起的命中判定、标签栏
  /// 居中）读这里。
  bool useBottomNav = false;
  late dynamic controller;
  final RxInt selectedIndex = 0.obs;

  final RxInt dynCount = 0.obs;
  late DynamicBadgeMode dynamicBadgeMode;
  late bool checkDynamic = Pref.checkDynamic;
  late int dynamicPeriod = Pref.dynamicPeriod * 60 * 1000;
  late int _lastCheckDynamicAt = 0;
  late bool hasDyn = false;
  late final dynamicController = Get.putOrFind(DynamicsController.new);

  late bool hasHome = false;
  late final homeController = Get.putOrFind(HomeController.new);

  late DynamicBadgeMode msgBadgeMode = Pref.msgBadgeMode;
  late Set<MsgUnReadType> msgUnReadTypes = Pref.msgUnReadTypeV2;
  late final RxnString msgUnReadCount = RxnString(null);
  late int lastCheckUnreadAt = 0;

  final enableMYBar = Pref.enableMYBar;
  final floatingNavBar = Pref.floatingNavBar;
  final useSideBar = Pref.useSideBar;
  final mainTabBarView = Pref.mainTabBarView;

  /// 主界面这一帧该不该走手机档（底部导航栏）：**导航栏档位的唯一口径**。
  ///
  /// - 改用侧边栏（[Pref.useSideBar]）：不走；
  /// - 遥控器模式开着（[Pref.tvFocus]）：只有手机才走——电视 / 平板 / 桌面恒走
  ///   左侧导航栏，窗口怎么变都不落回手机档（遥控器用户手里那条导航栏是一个
  ///   不动的落脚点）。手机照旧按窗口形状切换：总开关默认是开的，左侧栏在竖屏
  ///   手机上要吃掉四分之一宽度（见 [DeviceUtils.isPhone]）；
  /// - 其余情况（遥控器模式关着）按窗口形状切换：竖屏比例 = 手机档，横屏比例 =
  ///   左侧栏（手机横屏也算左侧栏）。
  ///
  /// 顺带把 MediaQuery 依赖注册上：首页 / 我的页是 const 单例，只靠这个依赖
  /// 跟着窗口缩放重建。前两条直接返回时不读 MediaQuery——那两枝的结果与窗口
  /// 无关，本来也不需要跟着窗口重建。
  ///
  /// 最后那句的 `isPortrait` 不是框架的（`Size` 没有这个成员）：是
  /// [SizeExt.isPortrait]——窄屏 / 竖屏形态（`width < 600` 或高 ≥ 宽）算手机档，
  /// 电视恒不算（电视盒子逻辑宽度可能很窄，按宽度会被判成手机）。
  static bool useBottomNavOf(BuildContext context) {
    if (Pref.useSideBar) return false;
    if (Pref.tvFocus && !DeviceUtils.isPhone) return false;
    return MediaQuery.sizeOf(context).isPortrait;
  }

  late bool directExitOnBack = Pref.directExitOnBack;
  late bool showTrayIcon = Pref.showTrayIcon;
  late bool minimizeOnExit = Pref.minimizeOnExit;
  late bool pauseOnMinimize = Pref.pauseOnMinimize;
  late bool isPlaying = false;

  static const _period = 5 * 60 * 1000;
  late int _lastSelectTime = 0;

  @override
  void onInit() {
    super.onInit();
    if (Pref.autoUpdate) {
      Update.checkUpdate();
    }

    setNavBarConfig();

    controller = mainTabBarView
        ? TabController(
            vsync: this,
            initialIndex: selectedIndex.value,
            length: navigationBars.length,
          )
        : PageController(initialPage: selectedIndex.value);

    hideBottomBar =
        !useSideBar && navigationBars.length > 1 && Pref.hideBottomBar;
    if (hideBottomBar) {
      updateBarHideType(barHideType.value);
    }

    dynamicBadgeMode = Pref.dynamicBadgeMode;

    hasDyn = navigationBars.contains(NavigationBarType.dynamics);
    if (dynamicBadgeMode != DynamicBadgeMode.hidden) {
      if (hasDyn && navigationBars[selectedIndex.value] != .dynamics) {
        if (checkDynamic) {
          _lastCheckDynamicAt = DateTime.now().millisecondsSinceEpoch;
        }
        getUnreadDynamic();
      }
    }

    hasHome = navigationBars.contains(NavigationBarType.home);
    if (msgBadgeMode != DynamicBadgeMode.hidden) {
      if (hasHome) {
        lastCheckUnreadAt = DateTime.now().millisecondsSinceEpoch;
        queryUnreadMsg();
      }
    }
  }

  Future<int> _msgUnread() async {
    if (msgUnReadTypes.contains(MsgUnReadType.pm)) {
      final res = await MsgHttp.msgUnread();
      if (res case Success(:final response)) {
        return response.followUnread +
            response.unfollowUnread +
            response.bizMsgFollowUnread +
            response.bizMsgUnfollowUnread +
            response.unfollowPushMsg +
            response.customUnread;
      }
    }
    return 0;
  }

  Future<int> _msgFeedUnread() async {
    int count = 0;
    final remainTypes = Set<MsgUnReadType>.from(msgUnReadTypes)
      ..remove(MsgUnReadType.pm);
    if (remainTypes.isNotEmpty) {
      final res = await MsgHttp.msgFeedUnread();
      if (res case Success(:final response)) {
        for (final item in remainTypes) {
          switch (item) {
            case MsgUnReadType.pm:
              break;
            case MsgUnReadType.reply:
              count += response.reply;
              break;
            case MsgUnReadType.at:
              count += response.at;
              break;
            case MsgUnReadType.like:
              count += response.like;
              break;
            case MsgUnReadType.sysMsg:
              count += response.sysMsg;
              break;
          }
        }
      }
    }
    return count;
  }

  void clearUnreadMsg() {
    msgUnReadCount.value = null;
  }

  Future<void> queryUnreadMsg([bool isChangeType = false]) async {
    if (!accountService.isLogin.value ||
        !hasHome ||
        msgUnReadTypes.isEmpty ||
        msgBadgeMode == DynamicBadgeMode.hidden) {
      clearUnreadMsg();
      return;
    }

    final res = await Future.wait([_msgUnread(), _msgFeedUnread()]);

    final count = res.sum;

    final countStr = count == 0
        ? null
        : count > 99
        ? '99+'
        : count.toString();
    if (msgUnReadCount.value == countStr) {
      if (isChangeType) {
        msgUnReadCount.refresh();
      }
    } else {
      msgUnReadCount.value = countStr;
    }
  }

  void getUnreadDynamic() {
    if (!accountService.isLogin.value || !hasDyn) {
      return;
    }
    DynGrpc.dynRed().then((res) {
      if (res != null) {
        setDynCount(res);
      }
    });
  }

  void setDynCount([int count = 0]) {
    if (!hasDyn) return;
    dynCount.value = count;
  }

  void checkUnreadDynamic() {
    if (!hasDyn ||
        !accountService.isLogin.value ||
        dynamicBadgeMode == DynamicBadgeMode.hidden ||
        !checkDynamic) {
      return;
    }
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastCheckDynamicAt >= dynamicPeriod) {
      _lastCheckDynamicAt = now;
      getUnreadDynamic();
    }
  }

  void setNavBarConfig() {
    List<int>? navBarSort =
        (GStorage.setting.get(SettingBoxKey.navBarSort) as List?)?.fromCast();
    late final List<NavigationBarType> navigationBars;
    if (navBarSort == null || navBarSort.isEmpty) {
      navigationBars = NavigationBarType.values;
    } else {
      navigationBars = navBarSort
          .map(NavigationBarType.values.elementAt)
          .toList();
    }
    this.navigationBars = navigationBars;
    final defPage = Pref.defaultHomePage;
    selectedIndex.value = math.max(0, navigationBars.indexOf(defPage));
  }

  void checkDefaultSearch([bool shouldCheck = false]) {
    if (hasHome && homeController.enableSearchWord) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - homeController.lateCheckSearchAt >= _period) {
        homeController
          ..lateCheckSearchAt = now
          ..querySearchDefault();
      }
    }
  }

  void checkUnread([bool shouldCheck = false]) {
    if (accountService.isLogin.value &&
        hasHome &&
        msgBadgeMode != DynamicBadgeMode.hidden) {
      if (shouldCheck &&
          navigationBars[selectedIndex.value] != NavigationBarType.home) {
        return;
      }
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastCheckUnreadAt >= _period) {
        lastCheckUnreadAt = now;
        queryUnreadMsg();
      }
    }
  }

  void toMemberPage() {
    final mid = Accounts.main.mid;
    if (accountService.isLogin.value && mid > 0) {
      Get.toNamed('/member?mid=$mid');
    } else {
      Get.toNamed('/loginPage');
    }
  }

  void setIndex(int value) {
    feedBack();

    final currentNav = navigationBars[value];
    if (value != selectedIndex.value) {
      selectedIndex.value = value;
      if (mainTabBarView) {
        controller.animateTo(value);
      } else {
        controller.jumpToPage(value);
      }
      if (currentNav == NavigationBarType.home) {
        checkDefaultSearch();
        checkUnread();
      } else if (currentNav == NavigationBarType.dynamics) {
        setDynCount();
      }
    } else {
      int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastSelectTime < 500) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          () {
            if (currentNav == NavigationBarType.home) {
              homeController.onRefresh();
            } else if (currentNav == NavigationBarType.dynamics) {
              dynamicController.onRefresh();
            }
          },
        );
      } else {
        if (currentNav == NavigationBarType.home) {
          homeController.toTopOrRefresh();
        } else if (currentNav == NavigationBarType.dynamics) {
          dynamicController.toTopOrRefresh();
        }
      }
      _lastSelectTime = now;
    }
  }

  void setSearchBar() {
    if (hasHome) {
      homeController.showTopBar?.value = true;
    }
  }

  void updateBarHideType(BarHideType value) {
    // 先建好目标模式的 Rx 再通知 barHideType，保证各处 Obx 重建时即读到新状态
    if (hideBottomBar) {
      switch (value) {
        case .instant:
          showBottomBar ??= RxBool(true);
          showBottomBar?.value = true;
        case .sync:
          barOffset ??= RxDouble(0.0);
          barOffset?.value = 0.0;
      }
    }
    // onInit 阶段本控制器 isInit 未置位，此时创建 HomeController 会使其
    // onInit 反向 Get.find<MainController>() 造成重入（hideBottomBar 二次
    // 赋值报 LateInitializationError）；HomeController 由 HomeView 自行
    // 创建，这里只同步已创建的实例。
    if (Get.isRegistered<HomeController>()) {
      homeController.updateBarHideType(value);
    }
    barHideType.value = value;
  }

  void setDefaultHomePage(NavigationBarType value) {
    final index = math.max(0, navigationBars.indexOf(value));
    if (index != selectedIndex.value) {
      setIndex(index);
    }
  }

  bool refreshRecommendations() {
    if (navigationBars[selectedIndex.value] == NavigationBarType.home &&
        homeController.tabs[homeController.tabController.index] ==
            HomeTabType.rcmd) {
      homeController.onRefresh();
      return true;
    }
    return false;
  }

  @override
  void onClose() {
    barOffset?.close();
    controller.dispose();
    super.onClose();
  }

  @override
  void onChangeAccount(bool isLogin) {
    if (isLogin) {
      queryUnreadMsg();
      getUnreadDynamic();
    } else {
      setDynCount();
    }
  }
}
