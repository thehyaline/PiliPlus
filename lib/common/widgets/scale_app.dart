import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerData, PointerDataPacket, PointerDeviceKind;

import 'package:PiliPlus/common/widgets/hover_reset.dart';
import 'package:flutter/gestures.dart' show PointerEventConverter;
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/widgets.dart';

/// ref https://github.com/LastMonopoly/scaled_app

/// Adapted from [WidgetsFlutterBinding]
///
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  ScaledWidgetsFlutterBinding._({this._scaleFactor = 1.0});

  /// Calculate scale factor from device size.
  double _scaleFactor;

  /// Update scaleFactor callback, then rebuild layout
  set scaleFactor(double scaleFactor) {
    if (_scaleFactor == scaleFactor) return;
    _scaleFactor = scaleFactor;
    handleMetricsChanged();
  }

  double devicePixelRatioScaled = 0;

  /// 出现过的鼠标/触控笔设备 id（可能产生悬停事件的设备）。
  ///
  /// 用于 [HoverReset]（见 hover_reset.dart）：当某设备的最后位置不再更新
  /// （窗口隐藏/最小化/遮挡、触控笔悬停残留等）时，其悬停高亮会被
  /// MouseTracker 每帧无限确认，需要据此清空对应设备的跟踪状态。
  final Set<int> _hoverDevices = <int>{};

  Set<int> get hoverDevices => _hoverDevices;

  /// 各鼠标/触控笔设备最后一次产生事件的时刻。
  final Map<int, DateTime> _hoverDeviceLastSeen = <int, DateTime>{};

  /// 超过该时长未产生任何事件的鼠标/触控笔设备视为失联，
  /// 清除其悬停状态，避免"幽灵悬浮"。
  static const Duration _hoverDeviceStaleTimeout = Duration(seconds: 30);

  /// 是否处于事件锁定状态（帧回调期间），供 HoverReset 判断能否派发合成事件。
  bool get isLocked => locked;

  static ScaledWidgetsFlutterBinding? _binding;

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  /// Scaling will be applied based on [scaleFactor] callback.
  ///
  static WidgetsBinding ensureInitialized({double scaleFactor = 1.0}) =>
      _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor: scaleFactor);

  /// Override the method from [RendererBinding.createViewConfiguration] to
  /// change what size or device pixel ratio the [RenderView] will use.
  ///
  /// See more:
  /// * [RendererBinding.createViewConfiguration]
  /// * [TestWidgetsFlutterBinding.createViewConfiguration]
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    final devicePixelRatio = view.devicePixelRatio;
    devicePixelRatioScaled = devicePixelRatio * _scaleFactor;
    final BoxConstraints physicalConstraints =
        BoxConstraints.fromViewConstraints(view.physicalConstraints);
    return ViewConfiguration(
      physicalConstraints: physicalConstraints,
      logicalConstraints: physicalConstraints / devicePixelRatioScaled,
      devicePixelRatio: devicePixelRatioScaled,
    );
  }

  /// Adapted from [GestureBinding.initInstances]
  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  /// When we scale UI using [ViewConfiguration], [ui.window] stays the same.
  ///
  /// [GestureBinding] uses [platformDispatcher.implicitView.devicePixelRatio] for calculations,
  /// so we override corresponding methods.
  ///
  void _handlePointerDataPacket(PointerDataPacket packet) {
    final DateTime now = DateTime.now();
    for (final PointerData data in packet.data) {
      if (data.kind == PointerDeviceKind.mouse ||
          data.kind == PointerDeviceKind.stylus) {
        _hoverDevices.add(data.device);
        _hoverDeviceLastSeen[data.device] = now;
      }
    }
    // 鼠标/触控笔设备长时间未产生任何事件（触控笔悬停残留、设备失联等），
    // 其悬停高亮会被 MouseTracker 每帧无限确认，形成"幽灵悬浮"；
    // 趁下一个事件包到来时清空这些失联设备的跟踪状态。
    if (_hoverDeviceLastSeen.isNotEmpty) {
      final List<int> stale = <int>[];
      _hoverDeviceLastSeen.forEach((device, lastSeen) {
        if (now.difference(lastSeen) > _hoverDeviceStaleTimeout) {
          stale.add(device);
        }
      });
      if (stale.isNotEmpty) {
        for (final int device in stale) {
          _hoverDevices.remove(device);
          _hoverDeviceLastSeen.remove(device);
        }
        HoverReset.reset(devices: stale);
      }
    }
    // We convert pointer data to logical pixels so that e.g. the touch slop can be
    // defined in a device-independent manner.
    try {
      _pendingPointerEvents.addAll(
        PointerEventConverter.expand(packet.data, _devicePixelRatioForView),
      );
      if (!locked) {
        _flushPointerEventQueue();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'gestures library',
          context: ErrorDescription('while handling a pointer data packet'),
        ),
      );
    }
  }

  double _devicePixelRatioForView(int viewId) => devicePixelRatioScaled;

  /// Dispatch a [PointerCancelEvent] for the given pointer soon.
  ///
  /// The pointer event will be dispatched before the next pointer event and
  /// before the end of the microtask but not within this function call.
  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);

    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}
