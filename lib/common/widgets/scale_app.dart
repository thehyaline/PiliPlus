import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show Queue;
import 'dart:ui'
    show
        PointerChange,
        PointerData,
        PointerDataPacket,
        PointerDeviceKind,
        ViewFocusEvent,
        ViewFocusState;

import 'package:PiliPlus/common/widgets/hover_reset.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
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

  // ---------------------------------------------------------------------------
  // 指针泄漏自愈（"幽灵触摸"，见 `PointerLedger` 的说明）
  // ---------------------------------------------------------------------------

  /// 现在按着、但还没抬起的指针 —— 直接读原始事件包记账。
  ///
  /// 键是 [PointerData.pointerIdentifier]（和 `PointerEvent.pointer` 同一套 id）。
  /// `PointerData` 那一层是平台原话，不会有"转换失败被丢掉"的可能，
  /// 所以它是"哪些指针还按着"最可信的一份账。
  final Set<int> _downPointers = <int>{};

  /// 这些指针最后一次产生事件的时刻（用来判断"账是不是已经过期"）。
  final Map<int, DateTime> _pointerLastSeen = <int, DateTime>{};

  /// 一个按着的指针多久没有任何事件就当它已经不在屏幕上了。
  ///
  /// 手指停着不动时平台**不发** move，所以这个窗口不能太短——它只在
  /// "又有新手指按下来"时被检查一次（那正是幽灵要开始捣乱的时候）：
  /// 十几秒没动静的旧账，碰到新按下就清掉。
  static const Duration _pointerStaleTimeout = Duration(seconds: 10);

  /// 现在记账里还按着的指针数（测试和调试用）。
  int get activePointerCount => _downPointers.length;

  /// 把"记着还按着、其实早就该松了"的指针全部作废。
  ///
  /// 窗口失焦、尺寸/比例突变（旋转、拉伸、切显示器）之后，那些指针的
  /// up/cancel 永远不会来了。留着它们的后果不只是我们自己账目不清：
  /// `ScaleGestureRecognizer.pointerCount` 会永远 ≥ 2，于是播放器里
  /// **单指拖动被判成双指捏合**（"一根手指按在屏幕上"的感觉）。
  /// 这里替平台补一个 cancel：识别器收 cancel 会 abort 当前手势、
  /// 清队列，界面回到"没人在按"的状态。
  void releaseStalePointers(String reason) {
    if (_downPointers.isEmpty) return;
    final pointers = _downPointers.toList(growable: false);
    _downPointers.clear();
    _pointerLastSeen.clear();
    if (kDebugMode) {
      debugPrint('[pointer] 作废 ${pointers.length} 个失联指针（$reason）：$pointers');
    }
    for (final pointer in pointers) {
      cancelPointer(pointer);
    }
  }

  /// 只清掉那些很久没有事件的指针（新手指按下来时调，见 [_pointerStaleTimeout]）。
  void _releaseIdlePointers() {
    if (_downPointers.isEmpty) return;
    final now = DateTime.now();
    final stale = <int>[];
    _pointerLastSeen.forEach((pointer, lastSeen) {
      if (now.difference(lastSeen) > _pointerStaleTimeout) stale.add(pointer);
    });
    if (stale.isEmpty) return;
    for (final pointer in stale) {
      _downPointers.remove(pointer);
      _pointerLastSeen.remove(pointer);
    }
    if (kDebugMode) {
      debugPrint('[pointer] 作废 ${stale.length} 个长时间没动静的指针：$stale');
    }
    for (final pointer in stale) {
      cancelPointer(pointer);
    }
  }

  /// 窗口（Flutter 视图）失去焦点：按着的指针不会再收到 up 了。
  @override
  void handleViewFocusChanged(ViewFocusEvent event) {
    super.handleViewFocusChanged(event);
    if (event.state == ViewFocusState.unfocused) {
      releaseStalePointers('视图失焦');
    }
  }

  /// 应用被切到后台/挂起：同理。
  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    super.handleAppLifecycleStateChanged(state);
    if (state != AppLifecycleState.resumed) {
      releaseStalePointers('应用切走：${state.name}');
    }
  }

  /// 尺寸/像素比突变（旋转、拉伸窗口、切显示器）：指针坐标系整个换了。
  ///
  /// 只在**视图的物理尺寸真的变了**时动手：键盘弹出、系统栏显示/隐藏这些
  /// 只改 `viewInsets` 的变化同样会走到这里，那时按着的指针是好的。
  @override
  void handleMetricsChanged() {
    super.handleMetricsChanged();
    final view = renderViews.isEmpty ? null : renderViews.first.flutterView;
    final size = view?.physicalSize;
    if (size == null || size == _lastViewSize) return;
    _lastViewSize = size;
    releaseStalePointers('视图尺寸变化 $size');
  }

  Size? _lastViewSize;

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
    var hasNewPointer = false;
    for (final PointerData data in packet.data) {
      if (data.kind == PointerDeviceKind.mouse ||
          data.kind == PointerDeviceKind.stylus) {
        _hoverDevices.add(data.device);
        _hoverDeviceLastSeen[data.device] = now;
      }
      // 活指针记账（见 releaseStalePointers）：平台原话里"按下/抬起"是
      // 最清楚的一份账，识别器和控件那两层的判断都以它为准。
      final pointer = data.pointerIdentifier;
      switch (data.change) {
        case PointerChange.down:
          _downPointers.add(pointer);
          _pointerLastSeen[pointer] = now;
          hasNewPointer = true;
        case PointerChange.move:
          if (_downPointers.contains(pointer)) {
            _pointerLastSeen[pointer] = now;
          }
        case PointerChange.up:
        case PointerChange.cancel:
          _downPointers.remove(pointer);
          _pointerLastSeen.remove(pointer);
        default:
          break;
      }
    }
    // 又有手指按下来了 —— 正是幽灵要开始捣乱的时候：顺手清掉那些
    // 十几秒没动静的旧账（它们的 up 永远不会来了）
    if (hasNewPointer) {
      _releaseIdlePointers();
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
    //
    // **逐条**转换：一条坏数据会让 `PointerEventConverter.expand` 抛异常，
    // 而整包一起转换时那一下会把包里**后面**的事件一起丢掉——丢掉一个
    // up/cancel 就是一根"永远按着的手指"（"幽灵触摸"，见 [PointerLedger]）。
    // 现在只丢坏的那条，其余的照常入队。
    var failed = 0;
    for (final PointerData data in packet.data) {
      try {
        _pendingPointerEvents.addAll(
          PointerEventConverter.expand(<PointerData>[data], _devicePixelRatioForView),
        );
      } catch (error, stack) {
        // 只报第一条：坏数据通常是同一个原因成片出现，全报会刷屏
        if (failed++ == 0) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'gestures library',
              context: ErrorDescription('while converting a pointer data packet'),
            ),
          );
        }
      }
    }
    if (!locked) {
      _flushPointerEventQueue();
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
