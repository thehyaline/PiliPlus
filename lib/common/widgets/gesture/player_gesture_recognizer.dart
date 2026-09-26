import 'package:flutter/gestures.dart'
    show
        GestureRecognizer,
        PointerCancelEvent,
        PointerDownEvent,
        PointerEvent,
        PointerPanZoomEndEvent,
        PointerPanZoomStartEvent,
        PointerUpEvent,
        RecognizerCallback,
        ScaleGestureRecognizer;

mixin PlayerGestureMixin on GestureRecognizer {
  bool isPosAllowed = true;

  @override
  T? invokeCallback<T>(
    String name,
    RecognizerCallback<T> callback, {
    String Function()? debugReport,
  }) {
    if (!isPosAllowed) return null;
    return super.invokeCallback(name, callback, debugReport: debugReport);
  }
}

/// [ScaleGestureRecognizer] + 幽灵指针清理（见 [PointerLedger] 的说明）。
///
/// 识别器自己的账（`_pointerQueue`）只有收到同一个指针的 up/cancel 才会清，
/// 漏一个就是"永远按着的手指"：`pointerCount` 从此 ≥ 2，`_update()` 会把
/// 幽灵的位置也算进焦点与跨度，于是**单指拖动的 `details.scale` 不再是 1**，
/// 播放器里就表现为"拖动视频变成双指缩放"。
///
/// 控件层（`PointerLedger`）只能修正"这一下算单指还是多指"的判断，改不了
/// 识别器内部的几何计算；这里在**新手指按下来的那一刻**把久无音信的旧指针
/// 从识别器里摘掉（[rejectGesture]，框架内部就是这么清理的），让数学重新成立。
class PlayerScaleGestureRecognizer extends ScaleGestureRecognizer
    with PlayerGestureMixin {
  PlayerScaleGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    super.dragStartBehavior,
    super.trackpadScrollCausesScale,
    super.trackpadScrollToScaleFactor,
  });

  /// 跟踪中的指针 → 它最后一次产生事件的时刻。
  final Map<int, Duration> _lastSeen = <int, Duration>{};

  /// 超过这么久没有任何事件的跟踪中指针视为幽灵。
  ///
  /// 手指停着不动时平台不发 move，所以这个窗口必须比"正常人按着不动"长得多；
  /// 它只在**又有手指按下来**时被检查（那正是幽灵要开始捣乱的时候）。
  static const Duration staleTimeout = Duration(seconds: 10);

  /// 现在还跟踪着几个指针（调试/测试用）。
  int get trackedPointerCount => _lastSeen.length;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _lastSeen[event.pointer] = event.timeStamp;
    // 放在 super 之后：新指针已经进了跟踪表，踢掉旧指针不会把跟踪表清空
    // （清空会走到 `didStopTrackingLastPointer` 里那条"手势没结束就没人按着了"的
    // assert）。而且它的 down 还没派发到这里（`GestureBinding.hitTest` 把 binding
    // 放在命中链末端，路由在整棵树派发完之后才走），这一脚踢得干净。
    _evictStalePointers(event.timeStamp);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    super.addAllowedPointerPanZoom(event);
    _lastSeen[event.pointer] = event.timeStamp;
    _evictStalePointers(event.timeStamp);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (_lastSeen.containsKey(event.pointer)) {
      _lastSeen[event.pointer] = event.timeStamp;
    }
    super.handleEvent(event);
    if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerPanZoomEndEvent) {
      _lastSeen.remove(event.pointer);
    }
  }

  /// 把"早就该松了、却还留在识别器里"的指针全部作废。
  ///
  /// 只处理"新指针之外还有别的指针"的情况：只剩一个时它可能只是按着不动，
  /// 也可能是真的幽灵，但那种情形下 [GestureBinding.cancelPointer] 那边
  /// （见 `ScaledWidgetsFlutterBinding.releaseStalePointers`）已经会兜住，
  /// 而且这里动它会撞上上面那条 assert。
  void _evictStalePointers(Duration now) {
    if (_lastSeen.length < 2) return;
    final stale = <int>[];
    _lastSeen.forEach((pointer, lastSeen) {
      if (now - lastSeen > staleTimeout) stale.add(pointer);
    });
    if (stale.isEmpty) return;
    for (final int pointer in stale) {
      _lastSeen.remove(pointer);
      // 位置表、队列、跟踪表一起清（框架的 rejectGesture 就是这么干的）
      rejectGesture(pointer);
    }
  }
}
