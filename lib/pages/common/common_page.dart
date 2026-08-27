import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/models/common/bar_hide_type.dart';
import 'package:PiliPlus/pages/home/controller.dart';
import 'package:PiliPlus/pages/main/controller.dart';
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract class CommonPageState<T extends StatefulWidget> extends State<T> {
  RxDouble? get _barOffset => _mainController.barOffset;
  RxBool? get _showBottomBar => _mainController.showBottomBar;
  RxBool? get _showTopBar => Get.isRegistered<HomeController>()
      ? Get.find<HomeController>().showTopBar
      : null;
  final _mainController = Get.find<MainController>();

  bool get needsCorrection => false;

  Widget onBuild(Widget child) {
    return Obx(() {
      // 无条件读取 barHideType，保证收起功能全部关闭时 Obx 也有订阅
      final hideType = _mainController.barHideType.value;
      if (_barOffset != null && hideType == BarHideType.sync) {
        return NotificationListener<ScrollNotification>(
          onNotification: onNotificationType2,
          child: child,
        );
      }
      if (_showTopBar != null || _showBottomBar != null) {
        return NotificationListener<UserScrollNotification>(
          onNotification: onNotificationType1,
          child: child,
        );
      }
      return child;
    });
  }

  bool onNotificationType1(UserScrollNotification notification) {
    if (!_mainController.useBottomNav) return false;
    if (notification.metrics.axis == .horizontal) return false;
    switch (notification.direction) {
      case .forward:
        _showTopBar?.value = true;
        _showBottomBar?.value = true;
      case .reverse:
        _showTopBar?.value = false;
        _showBottomBar?.value = false;
      case _:
    }
    return false;
  }

  void _updateOffset(double scrollDelta) {
    _barOffset!.value = clampDouble(
      _barOffset!.value + scrollDelta,
      0.0,
      Style.topBarHeight,
    );
  }

  bool onNotificationType2(ScrollNotification notification) {
    if (!_mainController.useBottomNav) return false;

    final metrics = notification.metrics;
    if (metrics.axis == .horizontal) return false;

    if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails == null) return false;
      final pixel = metrics.pixels;
      final scrollDelta = notification.scrollDelta ?? 0;
      if (pixel < 0.0 && scrollDelta > 0) return false;
      if (needsCorrection) {
        final value = _barOffset!.value;
        final newValue = clampDouble(
          value + scrollDelta,
          0.0,
          Style.topBarHeight,
        );
        final offset = value - newValue;
        if (offset != 0) {
          _barOffset!.value = newValue;
          if (pixel < 0.0 && scrollDelta < 0.0 && value > 0.0) {
            return false;
          }
          Scrollable.of(notification.context!).position.correctBy(offset);
        }
      } else {
        _updateOffset(scrollDelta);
      }
      return false;
    }

    if (notification is OverscrollNotification) {
      _updateOffset(notification.overscroll);
      return false;
    }

    return false;
  }
}
