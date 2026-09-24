import 'dart:math' as math;

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show Offset, Rect, Size;
import 'package:screen_retriever/screen_retriever.dart';

/// 计算窗口的初始位置与大小：
/// - 优先使用上次记录的位置（需落在任一显示器的可见区域内且该显示器
///   与主屏 DPI 一致，避免窗口大部分落在屏外或跨 DPI 迁移）；
/// - 否则以鼠标所在显示器为中心（其 DPI 与主屏不一致时回退主屏）；
/// - 尺寸钳制到目标显示器的可见区域，防止记录了大尺寸时窗口超出屏幕。
Future<Rect> calcWindowBounds(Size windowSize) async {
  final displays = await screenRetriever.getAllDisplays();
  final primaryDisplay = await screenRetriever.getPrimaryDisplay();
  // 启动期窗口创建在主屏（runner 固定 origin(10,10)），其 DPI 即主屏
  // DPI。首帧渲染前跨 DPI 迁移会连锁触发 WM_DPICHANGED 缩放，引擎
  // surface 重建等不到光栅帧而超时损坏（窗口透明只剩边框），因此启动
  // 位置只选与主屏 DPI 相同的显示器（native 侧启动期也会拦截此类迁移）。
  final cursorScreenPoint = await screenRetriever.getCursorScreenPoint();
  final currentDisplay =
      displays.firstWhereOrNull(
        (display) => _visibleBoundsOf(display).contains(cursorScreenPoint),
      ) ??
      primaryDisplay;
  final currentBounds = _visibleBoundsOf(
    _sameDpi(currentDisplay, primaryDisplay) ? currentDisplay : primaryDisplay,
  );

  Offset? position;
  final saved = Pref.windowPosition;
  if (saved != null) {
    try {
      final dx = saved[0];
      final dy = saved[1];
      // 整个窗口矩形必须完整落在单个显示器的可见区域内，且该显示器与
      // 主屏 DPI 一致，否则拒绝使用。记录的位置来自 getBounds（虚拟化
      // 坐标），而 setBounds 按物理坐标解释；跨 DPI 显示器（如 200%
      // 副屏）上两者差一倍，直接使用会让窗口横跨不同 DPI 的显示器。
      final rect = Rect.fromLTWH(dx, dy, windowSize.width, windowSize.height);
      if (displays.any((display) {
        final bounds = _visibleBoundsOf(display);
        return _sameDpi(display, primaryDisplay) &&
            rect.left >= bounds.left &&
            rect.top >= bounds.top &&
            rect.right <= bounds.right &&
            rect.bottom <= bounds.bottom;
      })) {
        position = Offset(dx, dy);
      }
    } catch (_) {}
  }

  final Rect targetBounds;
  if (position case final pos?) {
    final containing = displays.firstWhereOrNull(
      (display) => _visibleBoundsOf(display).contains(pos),
    );
    targetBounds = _visibleBoundsOf(
      containing != null && _sameDpi(containing, primaryDisplay)
          ? containing
          : primaryDisplay,
    );
  } else {
    targetBounds = currentBounds;
  }

  final width = math.min(windowSize.width, targetBounds.width);
  final height = math.min(windowSize.height, targetBounds.height);

  final Rect result;
  if (position case final pos?) {
    result = Rect.fromLTWH(pos.dx, pos.dy, width, height);
  } else {
    result = Rect.fromLTWH(
      currentBounds.left + (currentBounds.width - width) / 2,
      currentBounds.top + (currentBounds.height - height) / 2,
      width,
      height,
    );
  }
  return result;
}

Rect _visibleBoundsOf(Display display) {
  final double startX;
  final double startY;
  final double width;
  final double height;
  if (display.visiblePosition case final offset?) {
    startX = offset.dx;
    startY = offset.dy;
  } else {
    startX = startY = 0;
  }
  if (display.visibleSize case final size?) {
    width = size.width;
    height = size.height;
  } else {
    width = display.size.width;
    height = display.size.height;
  }
  return Rect.fromLTWH(startX, startY, width, height);
}

/// 两个显示器的 DPI 是否一致（scaleFactor 比较，容差 0.01）。
bool _sameDpi(Display a, Display b) {
  final sa = a.scaleFactor;
  final sb = b.scaleFactor;
  if (sa == null || sb == null) return false;
  return (sa - sb).abs() < 0.01;
}
