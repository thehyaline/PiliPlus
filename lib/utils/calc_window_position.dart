import 'dart:math' as math;

import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart' show Offset, Rect, Size;
import 'package:screen_retriever/screen_retriever.dart';

/// 计算窗口的初始位置与大小：
/// - 优先使用上次记录的位置（需落在任一显示器可见区域内且离右/下边缘
///   至少 30px，避免窗口大部分落在屏外）；
/// - 否则以鼠标所在显示器为中心；
/// - 尺寸钳制到目标显示器的可见区域，防止记录了大尺寸时窗口超出屏幕。
Future<Rect> calcWindowBounds(Size windowSize) async {
  final displays = await screenRetriever.getAllDisplays();
  final cursorScreenPoint = await screenRetriever.getCursorScreenPoint();
  final currentDisplay =
      displays.firstWhereOrNull(
        (display) => _visibleBoundsOf(display).contains(cursorScreenPoint),
      ) ??
      await screenRetriever.getPrimaryDisplay();
  final currentBounds = _visibleBoundsOf(currentDisplay);

  Offset? position;
  final saved = Pref.windowPosition;
  if (saved != null) {
    try {
      final dx = saved[0];
      final dy = saved[1];
      // 整个窗口矩形必须落在单个显示器的可见区域内，否则拒绝使用。
      // 记录的位置来自 getBounds（虚拟化坐标），而 setBounds 按物理
      // 坐标解释；跨 DPI 显示器（如 200% 副屏）上两者差一倍，直接使用
      // 会让窗口横跨不同 DPI 的显示器，连锁触发 WM_DPICHANGED 缩放，
      // 窗口大半落在屏外（表现为“窗口不见了、任务栏还有任务”）。
      final rect =
          Rect.fromLTWH(dx, dy, windowSize.width, windowSize.height);
      if (displays.any((display) {
        final bounds = _visibleBoundsOf(display);
        return rect.left >= bounds.left &&
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
    targetBounds = _visibleBoundsOf(
      displays.firstWhereOrNull(
            (display) => _visibleBoundsOf(display).contains(pos),
          ) ??
          currentDisplay,
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
