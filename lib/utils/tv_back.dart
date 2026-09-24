/// 返回键的优先拦截栈。
///
/// 桌面端的 Esc 是在 [FocusManager.addEarlyKeyEventHandler] 里处理的
/// （见 `main.dart`），它跑在**焦点树之前**，所以播放器这类
/// "返回键先关控件、再返回"的场景没法靠 `Focus.onKeyEvent` 抢到。
/// 需要先吃一步的地方（播放器控件层、全屏等）把回调压进来即可，
/// 压在最上面的先拿到机会；返回 false 表示不接手，继续往下走。
abstract final class TvBack {
  static final List<bool Function()> _handlers = <bool Function()>[];

  static void push(bool Function() handler) => _handlers.add(handler);

  static void remove(bool Function() handler) => _handlers.remove(handler);

  /// 有没有人接手；true 表示这次返回已经被消费掉。
  static bool dispatch() {
    for (var i = _handlers.length - 1; i >= 0; i--) {
      if (_handlers[i]()) return true;
    }
    return false;
  }
}
