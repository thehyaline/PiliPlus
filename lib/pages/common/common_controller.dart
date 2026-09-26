import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/utils/extension/scroll_controller_ext.dart';
import 'package:easy_debounce/easy_throttle.dart';
import 'package:flutter/widgets.dart' show ScrollController;
import 'package:get/get.dart';

mixin ScrollOrRefreshMixin {
  ScrollController get scrollController;

  void animateToTop() => scrollController.animToTop();

  Future<void> onRefresh();

  /// 「再点一次当前这一项」：不在顶部就先回顶，已经在顶部才刷新。
  ///
  /// 底栏 / 侧栏导航项连按走的就是这条（`MainController._selectNav`）：
  /// 用户那一按可能只是想"回顶"，所以刷新要等他**已经在顶部**再按一下。
  void toTopOrRefresh() {
    if (scrollController.hasClients) {
      if (scrollController.position.pixels == 0) {
        EasyThrottle.throttle(
          'topOrRefresh',
          const Duration(milliseconds: 500),
          onRefresh,
        );
      } else {
        animateToTop();
      }
    }
  }

  /// 「再点一次当前这一**栏**（标签）」：列表回顶 **并且** 刷新数据。
  ///
  /// 和 [toTopOrRefresh] 的区别是那一下的意思很明确——用户在标签栏上按确定 /
  /// 点鼠标，只会是想"重新加载这一栏"（不像底栏那样兼作"回顶"），所以两件事
  /// 一起做，对齐 blbl 的 `onTabReselected` → `handleRefreshKey`（回第一项 +
  /// 重新拉数据）。回顶那一步是给"刷新时列表不重建"的页面补的：列表要是被
  /// 换成了加载态，位置本来就会回到顶部。
  ///
  /// 节流闸和 [toTopOrRefresh] 共用：连着点不会连发请求。
  void toTopAndRefresh() {
    animateToTop();
    EasyThrottle.throttle(
      'topOrRefresh',
      const Duration(milliseconds: 500),
      onRefresh,
    );
  }
}

abstract class CommonController<R, T> extends GetxController
    with ScrollOrRefreshMixin {
  @override
  final ScrollController scrollController = ScrollController();

  bool isLoading = false;
  Rx<LoadingState> get loadingState;

  Future<LoadingState<R>> customGetData();

  Future<void> queryData([bool isRefresh = true]);

  bool customHandleResponse(bool isRefresh, Success<R> response) {
    return false;
  }

  bool handleError(String? errMsg) {
    return false;
  }

  @override
  Future<void> onRefresh() {
    return queryData();
  }

  Future<void> onLoadMore() {
    return queryData(false);
  }

  Future<void> onReload() {
    return onRefresh();
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}
