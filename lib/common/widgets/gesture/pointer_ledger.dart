import 'package:flutter/gestures.dart';

/// 活指针记账：**现在真的还按在屏幕上的指针有几个**。
///
/// 为什么不能用 `ScaleStartDetails.pointerCount`：那是识别器自己的账
/// （`ScaleGestureRecognizer.pointerCount = 2 * 触控板指针 + _pointerQueue.length`），
/// 而 `_pointerQueue` **只有**收到同一个指针的 up / cancel 才会被清掉。
/// 窗口失焦、系统把手势抢走（通知栏、来电、手势导航、触控笔走开）、事件包被丢
/// ……只要有一次 up/cancel 没送到，那个指针就永远留在队列里 → `pointerCount`
/// 永远 ≥ 2 → **之后每一次单指拖动都被判成双指捏合**。播放器里的表现就是
/// 用户说的"幽灵触摸"：好像一根手指一直按在屏幕上，拖动视频变成双指缩放。
///
/// 这里的账由**事件流**自己记：down 加一，up/cancel 减一；触控板的一次
/// pan-zoom 按框架的口径算两根（见 [ScaleGestureRecognizer.pointerCount]）。
///
/// 再叠一条**按压时间窗**（[multiTouchWindow]）：两根手指**前后脚按下**
/// （相差不超过这个窗口）才算多指。真捏合的两指间隔通常只有几十毫秒，
/// 而泄漏的指针是上一轮留下的、按下时刻早就过去了——于是就算自愈没赶上
/// （见 `ScaledWidgetsFlutterBinding.releaseStalePointers`），拖动也不会被
/// 误判成捏合；真的两根手指同时按下仍然照旧算多指。
class PointerLedger {
  /// 两根手指"A 按下之后多久之内 B 也按下"才算多指。
  ///
  /// 真捏合是两只手同时落下去，几十毫秒内；调大了会把"泄漏一根旧指针 +
  /// 新按下一根"也算成多指（旧指针按下时刻很久以前，所以它是被**排除**的
  /// 那一头），调小了会漏掉反应稍慢的捏合。
  static const window = Duration(milliseconds: 120);

  /// 还按着的指针 → 它**按下**的时刻（平台时间戳，同一个平台上是单调的）。
  final Map<int, Duration> _down = <int, Duration>{};

  /// 还活着的触控板 pan-zoom（框架口径：一个算两根）。
  int _panZooms = 0;

  /// 现在活着的指针数（触控板那一路一个算两根）。
  int get count => _down.length + 2 * _panZooms;

  /// 这次手势算"多指"吗——见类文档里那条时间窗。
  bool get isMultiTouch {
    if (_panZooms > 0) return true;
    if (_down.length < 2) return false;
    // 只看**最新的两根**：它们前后脚按下才算同一轮多指；
    // 更早的那些（泄漏的旧指针）不参与判断
    final times = _down.values.toList(growable: false)..sort();
    return times.last - times[times.length - 2] <= window;
  }

  /// 现在算不算"单指"（有指针按着，而且不是多指）。
  bool get isSingleTouch => count > 0 && !isMultiTouch;

  /// 记下一个指针按下。
  void down(int pointer, Duration timeStamp) => _down[pointer] = timeStamp;

  /// 记下一个指针起来（up / cancel 都算）。
  void up(int pointer) => _down.remove(pointer);

  /// 触控板：一次 pan-zoom 开始 / 结束。
  void panZoomStart() => _panZooms++;

  void panZoomEnd() {
    if (_panZooms > 0) _panZooms--;
  }

  /// 全部作废（窗口失焦、尺寸突变之后由调用方重置）。
  void clear() {
    _down.clear();
    _panZooms = 0;
  }

  /// 直接从事件记账；[PointerEvent.pointer] 是框架给的唯一 id。
  void track(PointerEvent event) {
    switch (event) {
      case PointerDownEvent():
        down(event.pointer, event.timeStamp);
      case PointerUpEvent():
      case PointerCancelEvent():
        up(event.pointer);
      case PointerPanZoomStartEvent():
        panZoomStart();
      case PointerPanZoomEndEvent():
        panZoomEnd();
      default:
        break;
    }
  }
}
