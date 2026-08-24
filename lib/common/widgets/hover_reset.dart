import 'dart:async' show scheduleMicrotask;

import 'package:PiliPlus/common/widgets/scale_app.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerRemovedEvent;
import 'package:flutter/widgets.dart';

/// 全局悬停状态复位，用于消除"幽灵悬浮"。
///
/// [MouseTracker] 每帧都会在"设备最后已知位置"重新命中测试并维持高亮
/// （见 mouse_tracker.dart 的 updateAllDevices），因此当某个鼠标/触控笔
/// 设备的最后位置不再更新（窗口隐藏到托盘、最小化、被遮挡时鼠标在窗内、
/// 触控笔悬停残留、存在第二指针设备等）时，对应位置的悬浮高亮会被无限
/// 确认，鼠标怎么移动都不会消失。
///
/// 修复方式：向 [MouseTracker] 派发合成 [PointerRemovedEvent]，清空所有
/// 已记录鼠标类设备的跟踪状态，所有悬停高亮/浮层统一复位；真实设备的
/// 下一个事件会自动重新注册跟踪，不影响后续使用。
class HoverReset {
  HoverReset._();

  static bool _registered = false;

  /// 注册生命周期监听，在窗口/应用可见性变化时复位悬停状态。
  ///
  /// 覆盖场景：Windows 最小化、隐藏到托盘、窗口遮挡、切换窗口，
  /// Android 退后台/返回前台。
  static void ensureRegistered() {
    if (_registered) return;
    _registered = true;
    WidgetsBinding.instance.addObserver(_HoverLifecycleObserver());
  }

  /// 复位鼠标类设备的悬停状态。
  ///
  /// [devices] 为空时复位所有已记录设备，否则仅复位指定设备
  /// （用于 scale_app.dart 中失联设备的清扫）。
  static void reset({Iterable<int>? devices}) {
    final List<int> snapshot = devices != null
        ? devices.toList()
        : ScaledWidgetsFlutterBinding.instance.hoverDevices.toList();
    if (snapshot.isEmpty) return;
    // 延后到微任务派发，避免在事件分发回调（如 MouseRegion.onExit）中
    // 重入；若恰逢帧回调（事件被锁），跳过本次，真实事件到来时会自然刷新。
    scheduleMicrotask(() {
      if (ScaledWidgetsFlutterBinding.instance.isLocked) return;
      for (final int device in snapshot) {
        WidgetsBinding.instance.handlePointerEvent(
          PointerRemovedEvent(device: device, kind: PointerDeviceKind.mouse),
        );
      }
    });
  }
}

class _HoverLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.resumed:
        HoverReset.reset();
      case AppLifecycleState.detached:
        break;
    }
  }
}
