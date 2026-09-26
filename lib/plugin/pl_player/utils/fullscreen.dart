import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:PiliPlus/utils/calc_window_position.dart';
import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;
import 'package:window_manager/window_manager.dart' show windowManager;
import 'package:win32/win32.dart' as win32;

bool _isDesktopFullScreen = false;

/// 进入全屏（原生全屏或窗口全屏）时隐藏的任务栏窗口，退出时恢复。
///
/// Windows 只会对覆盖主显示器整屏的窗口自动隐藏主任务栏，副屏任务栏
/// 不会自动隐藏，会浮在全屏窗口上方（表现为全屏排除了任务栏区域）。
/// 因此进入全屏前主动隐藏所在显示器的任务栏（Shell_TrayWnd /
/// Shell_SecondaryTrayWnd），退出时恢复。
final List<win32.HWND> _hiddenTaskbars = [];

/// 应用主窗口的类名，与 windows/runner/win32_window.cpp 保持一致。
const _kAppWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

const _kTaskbarClasses = ['Shell_TrayWnd', 'Shell_SecondaryTrayWnd'];

/// 当前枚举任务栏时对匹配窗口执行的动作（EnumWindows 回调是同步的，
/// 经此模块级变量传递，避免闭包无法用于 [Pointer.fromFunction]）。
void Function(win32.HWND hwnd)? _taskbarAction;

int _enumTaskbarProc(Pointer ptr, int _) {
  final buf = win32.wsalloc(256);
  try {
    final hwnd = win32.HWND(ptr);
    win32.GetClassName(hwnd, buf, 256);
    if (_kTaskbarClasses.contains(buf.toDartString())) {
      _taskbarAction?.call(hwnd);
    }
  } finally {
    win32.free(buf);
  }
  return win32.TRUE;
}

/// 对类名匹配任务栏的所有顶层窗口执行 [action]。
void _forEachTaskbar(void Function(win32.HWND hwnd) action) {
  _taskbarAction = action;
  try {
    win32.EnumWindows(
      Pointer.fromFunction<win32.WNDENUMPROC>(_enumTaskbarProc, win32.FALSE),
      const win32.LPARAM(0),
    );
  } finally {
    _taskbarAction = null;
  }
}

/// 本应用的主窗口（按类名查找并校验 PID，避免命中其他 Flutter 应用）。
win32.HWND? _appWindow() {
  final className = _kAppWindowClass.toPcwstr();
  try {
    final hwnd = win32.FindWindow(className, null).value;
    if (hwnd.address == 0) return null;
    // GetWindowThreadProcessId 的返回值是窗口所属线程的 ID，进程 ID
    // 由第二个输出参数返回——拿返回值与进程 ID 比较会永远不相等。
    final pidPtr = calloc<Uint32>();
    try {
      win32.GetWindowThreadProcessId(hwnd, pidPtr);
      if (pidPtr.value != win32.GetCurrentProcessId()) return null;
    } finally {
      win32.free(pidPtr);
    }
    return hwnd;
  } finally {
    win32.free(className);
  }
}

/// 隐藏窗口所在显示器的任务栏（进入原生全屏前调用）。
void _hideTaskbarOnCurrentMonitor() {
  if (!PlatformUtils.isWindows || _hiddenTaskbars.isNotEmpty) return;
  final appWindow = _appWindow();
  if (appWindow == null) return;
  final monitor = win32.MonitorFromWindow(
    appWindow,
    win32.MONITOR_DEFAULTTONEAREST,
  );
  _forEachTaskbar((hwnd) {
    if (win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONEAREST) ==
        monitor) {
      win32.ShowWindow(hwnd, win32.SW_HIDE);
      _hiddenTaskbars.add(hwnd);
    }
  });
}

/// 恢复进入全屏时隐藏的任务栏（退出全屏时调用）。
void _restoreTaskbars() {
  if (!PlatformUtils.isWindows) return;
  for (final hwnd in _hiddenTaskbars) {
    // SW_SHOWNA：恢复任务栏但不激活它，避免前台窗口被任务栏抢走。
    win32.ShowWindow(hwnd, win32.SW_SHOWNA);
  }
  _hiddenTaskbars.clear();
}

/// 恢复所有任务栏：应用启动/关闭时兜底调用（覆盖上次异常退出残留的隐藏
/// 状态），退到托盘时也调用（窗口不可见时不该继续占着任务栏）。
void restoreAllTaskbars() {
  if (!PlatformUtils.isWindows) return;
  _forEachTaskbar((hwnd) => win32.ShowWindow(hwnd, win32.SW_SHOW));
  _hiddenTaskbars.clear();
}

/// 进入全屏前窗口是否为最大化状态，退出全屏后恢复。
///
/// media_kit fork 的原生全屏剥样式时不清除 WS_MAXIMIZE（该位不在
/// WS_OVERLAPPEDWINDOW 掩码内），最大化状态下进入全屏、退出后窗口仍
/// 保持 IsZoomed 且停在整屏矩形；这里只记录状态，退出时按
/// _restoreMaximizedState 的确定性序列恢复。
bool _wasMaximized = false;

/// 进入全屏前记录的目标工作区矩形（rcWork，仅在窗口最大化时保存）。
///
/// 退出全屏恢复最大化时窗口应落在该矩形上。任务栏由 ShowWindow 恢复
/// 后 Explorer 异步收回工作区——只有等实时 rcWork 重新等于该值时执行
/// 最大化，落点才是“任务栏之下”的正确工作区，而不是任务栏隐藏期间
/// 被扩展的整屏工作区。
int _savedWorkLeft = 0;
int _savedWorkTop = 0;
int _savedWorkRight = 0;
int _savedWorkBottom = 0;

void _recordMaximizedState() {
  final appWindow = _appWindow();
  if (appWindow == null) return;
  final placement = calloc<win32.WINDOWPLACEMENT>();
  try {
    placement.ref.length = sizeOf<win32.WINDOWPLACEMENT>();
    if (!win32.GetWindowPlacement(appWindow, placement).value) return;
    if (placement.ref.showCmd == win32.SW_MAXIMIZE) {
      _wasMaximized = true;
      // 记录当前工作区矩形：退出全屏恢复最大化时以它为落点
      // （此时任务栏尚未隐藏，值正确）。
      final monitorInfo = calloc<win32.MONITORINFO>();
      try {
        monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
        final monitor = win32.MonitorFromWindow(
          appWindow,
          win32.MONITOR_DEFAULTTONEAREST,
        );
        if (win32.GetMonitorInfo(monitor, monitorInfo)) {
          final w = monitorInfo.ref.rcWork;
          _savedWorkLeft = w.left;
          _savedWorkTop = w.top;
          _savedWorkRight = w.right;
          _savedWorkBottom = w.bottom;
        }
      } finally {
        win32.free(monitorInfo);
      }
    } else {
      // 显式复位：进入窗口全屏时也会调用本函数（见 enterWindowFullScreen），
      // 残留的 true 会让退出时把普通窗口当最大化处理。
      _wasMaximized = false;
    }
  } finally {
    win32.free(placement);
  }
}

/// 进入窗口全屏前的窗口矩形（GetWindowRect 的物理像素原值）。
///
/// 退出时要和「恢复窗口样式」放在同一次同步调用里用它把窗口摆回去：
/// 两步之间只要隔了一帧（例如改走 windowManager.setBounds 的平台通道，
/// 或先 await 一次查显示器），标题栏就会在整屏矩形上闪一下——同
/// [setWindowTitleBarVisible] 里说明的时序问题。
({int left, int top, int right, int bottom})? _savedWindowRect;

void _recordWindowRect(win32.HWND appWindow) {
  final rect = calloc<win32.RECT>();
  try {
    if (win32.GetWindowRect(appWindow, rect).value) {
      _savedWindowRect = (
        left: rect.ref.left,
        top: rect.ref.top,
        right: rect.ref.right,
        bottom: rect.ref.bottom,
      );
    }
  } finally {
    win32.free(rect);
  }
}

/// DwmFlush：阻塞到 DWM 完成下一次合成。dwmapi 不存在时保持 null（不阻塞）。
final int Function()? _dwmFlush = () {
  try {
    return DynamicLibrary.open('dwmapi.dll')
        .lookupFunction<Int32 Function(), int Function()>('DwmFlush');
  } catch (_) {
    return null;
  }
}();

/// 等「刚剥掉标题栏」这一帧真的合成出去，再改窗口几何。
///
/// 剥样式和铺满是两次独立的窗口操作，但都落在同一屏帧里的话，DWM 仍可能拿
/// 着还带标题栏的旧帧去合成新的（整屏）几何——见 setWindowTitleBarVisible。
/// DwmFlush 返回时这一步已经上屏，之后的几何变化不会再画出标题栏。合成不可用
/// 时（远程桌面等）直接跳过，最多退回调用前那种一帧的闪动。
void _flushCompositor() {
  if (!PlatformUtils.isWindows) return;
  try {
    _dwmFlush?.call();
  } catch (_) {}
}

/// 显示/隐藏系统标题栏（`WS_CAPTION`）。
///
/// 窗口默认带系统标题栏（见 windows/runner/win32_window.cpp）：有标题栏时
/// 拖动、边框缩放、系统菜单全交回系统；「窗口全屏」与播放器全屏期间剥掉它，
/// 客户区铺满整窗（边框缩放由 runner 的命中区提供），runner 在
/// `WM_NCCALCSIZE`、`WM_NCHITTEST`、`WM_NCACTIVATE` 中按同一位判断。
///
/// 进全屏的调用方要在**任何改窗口状态的操作之前**先调它（隐藏任务栏、铺满
/// 显示器都算；[_recordMaximizedState] 这类只读记录在它前面）。这一步之后
/// 窗口没有非客户区，谁来重摆窗口都画不出标题栏；反过来，只要改窗口状态时
/// 标题栏还在，DWM 就有机会在整屏矩形上把旧帧的标题栏合成出来一帧——表现为
/// 进全屏时闪一下系统标题栏（隐藏任务栏会让工作区扩展、系统随之重摆最大化的
/// 窗口；铺满则是 media_kit 的 EnterNativeFullscreen 里和剥样式同一条
/// SetWindowPos）。
void setWindowTitleBarVisible(bool visible) {
  if (!PlatformUtils.isWindows) return;
  final appWindow = _appWindow();
  if (appWindow == null) return;
  final style = win32.GetWindowLongPtr(appWindow, win32.GWL_STYLE).value;
  if ((style & win32.WS_CAPTION != 0) == visible) return;
  win32.SetWindowLongPtr(
    appWindow,
    win32.GWL_STYLE,
    visible ? style | win32.WS_CAPTION : style & ~win32.WS_CAPTION,
  );
  win32.SetWindowPos(
    appWindow,
    null,
    0,
    0,
    0,
    0,
    win32.SWP_NOMOVE |
        win32.SWP_NOSIZE |
        win32.SWP_NOZORDER |
        win32.SWP_NOACTIVATE |
        win32.SWP_FRAMECHANGED,
  );
}

/// 进入窗口全屏：窗口铺满所在显示器（连同任务栏区域）且无边框。
///
/// 与原生全屏（[enterDesktopFullScreen]）用的是同一套窗口样式处理：
/// 剥 `WS_OVERLAPPEDWINDOW` 后铺满 `rcMonitor`（对齐 media_kit fork 的
/// EnterNativeFullscreen），只是不进原生全屏——「窗口全屏」设置开启时
/// 窗口常驻该状态，播放器的全屏因此不再需要动窗口。
///
/// 铺满整屏的普通窗口会被顶层（topmost）的任务栏盖住，这里照旧隐藏
/// 所在显示器的任务栏；关闭、退出到托盘前由 _restoreTaskbars /
/// restoreAllTaskbars 恢复。退出（设置开关关闭 / F11）见
/// [exitWindowFullScreen]。
Future<void> enterWindowFullScreen() async {
  if (!PlatformUtils.isWindows) {
    await windowManager.setFullScreen(true);
    return;
  }
  final appWindow = _appWindow();
  if (appWindow == null) return;
  if (win32.GetWindowLongPtr(appWindow, win32.GWL_STYLE).value &
          win32.WS_OVERLAPPEDWINDOW !=
      0) {
    // 窗口还在普通状态：这一次是真的"进入"（不是从托盘恢复显示之类的
    // 重复调用），记录最大化状态、目标工作区与窗口矩形供退出时恢复。
    // 此时任务栏尚未隐藏，工作区值正确，见 _hideTaskbarOnCurrentMonitor。
    _recordMaximizedState();
    _recordWindowRect(appWindow);
  }
  // 剥标题栏放在隐藏任务栏之前，顺序见 setWindowTitleBarVisible。
  setWindowTitleBarVisible(false);
  _flushCompositor();
  // 任务栏仍然要无条件隐藏：窗口已是全屏样式（重复调用，例如从托盘恢复
  // 显示）时下面的样式那段会提前返回，任务栏却未必还在隐藏状态。
  _hideTaskbarOnCurrentMonitor();
  final style = win32.GetWindowLongPtr(appWindow, win32.GWL_STYLE).value;
  if (style & win32.WS_OVERLAPPEDWINDOW == 0) return;
  final monitorInfo = calloc<win32.MONITORINFO>();
  try {
    monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
    final monitor = win32.MonitorFromWindow(
      appWindow,
      win32.MONITOR_DEFAULTTONEAREST,
    );
    if (!win32.GetMonitorInfo(monitor, monitorInfo)) return;
    final rect = monitorInfo.ref.rcMonitor;
    win32.SetWindowLongPtr(
      appWindow,
      win32.GWL_STYLE,
      style & ~win32.WS_OVERLAPPEDWINDOW,
    );
    win32.SetWindowPos(
      appWindow,
      win32.HWND_TOP,
      rect.left,
      rect.top,
      rect.right - rect.left,
      rect.bottom - rect.top,
      win32.SWP_NOOWNERZORDER | win32.SWP_FRAMECHANGED,
    );
  } finally {
    win32.free(monitorInfo);
  }
}

/// 退出窗口全屏：恢复普通窗口样式与进入前的窗口形态。
///
/// 与退出原生全屏（[exitDesktopFullScreen]）同序——先恢复任务栏并等工作区
/// 收回，再动窗口样式；区别只是不去碰 media_kit 的原生全屏状态（窗口全屏
/// 期间播放器的全屏只切应用内布局，见 [enterDesktopFullScreen]）。
@pragma('vm:notify-debugger-on-exception')
Future<void> exitWindowFullScreen() async {
  if (!PlatformUtils.isWindows) {
    await windowManager.setFullScreen(false);
    return;
  }
  // 播放器原生全屏进行中：窗口样式同样是被剥掉的，但那套状态由
  // enterDesktopFullScreen / exitDesktopFullScreen 负责，这里不插手。
  if (_isDesktopFullScreen) return;
  final appWindow = _appWindow();
  if (appWindow == null) return;
  final style = win32.GetWindowLongPtr(appWindow, win32.GWL_STYLE).value;
  // 已经是普通窗口（重复调用）：不动窗口几何，任务栏由托盘/关闭那几条
  // 路径负责兜底。
  if (style & win32.WS_OVERLAPPEDWINDOW != 0) return;
  final savedRect = _savedWindowRect;
  final wasMaximized = _wasMaximized;
  _restoreTaskbars();
  if (wasMaximized) {
    // 落点依赖工作区收回后的实时值（同 exitDesktopFullScreen）。
    await _waitForWorkAreaSettle(appWindow);
  }
  // 恢复普通窗口样式（含 WS_CAPTION）：系统标题栏、边框缩放、系统菜单回来，
  // DWM 圆角也跟着样式位回来（见 runner 的 SyncWindowCornerPreference）。
  win32.SetWindowLongPtr(
    appWindow,
    win32.GWL_STYLE,
    style | win32.WS_OVERLAPPEDWINDOW,
  );
  if (wasMaximized) {
    // 窗口仍处于最大化状态（WS_MAXIMIZE 没被动过）：先让它按新样式重算
    // 非客户区，再由 _restoreMaximizedState 对齐记录的工作区并同步
    // window_manager 的状态机。
    win32.SetWindowPos(
      appWindow,
      null,
      0,
      0,
      0,
      0,
      win32.SWP_NOMOVE |
          win32.SWP_NOSIZE |
          win32.SWP_NOZORDER |
          win32.SWP_NOACTIVATE |
          win32.SWP_FRAMECHANGED,
    );
    _restoreMaximizedState();
  } else if (savedRect case final rect?) {
    // 与恢复样式同一次同步调用里摆回原矩形：中间不留帧，标题栏就不会在
    // 整屏矩形上闪一下（见 _savedWindowRect）。
    win32.SetWindowPos(
      appWindow,
      null,
      rect.left,
      rect.top,
      rect.right - rect.left,
      rect.bottom - rect.top,
      win32.SWP_NOZORDER | win32.SWP_NOACTIVATE | win32.SWP_FRAMECHANGED,
    );
  } else {
    // 没有记录到矩形（异常路径）：退回启动时的同一套计算（会校验记录的位置
    // 是否仍落在与主屏同 DPI 的显示器里见 calcWindowBounds）。
    await windowManager.setBounds(await calcWindowBounds(Pref.windowSize));
  }
}

/// 切换「窗口全屏」：设置-外观里的开关与 F11 共用同一份状态。
///
/// 先写设置再应用——这样下次启动照最后的状态打开（开关本身就代表着这个
/// 状态），也顺带让设置页的开关跟着 F11 变（见 SetSwitchItem 的存储监听）。
@pragma('vm:notify-debugger-on-exception')
Future<void> toggleWindowFullScreen() async {
  // 播放器原生全屏期间窗口已经铺满显示器，这一键不动它：退出全屏仍由
  // 播放器的按钮 / Esc 负责，两种全屏状态不互相打断。
  if (_isDesktopFullScreen) return;
  final next = !Pref.windowFullScreen;
  await GStorage.setting.put(SettingBoxKey.windowFullScreen, next);
  if (next) {
    await enterWindowFullScreen();
  } else {
    await exitWindowFullScreen();
  }
}

/// 轮询等待实时工作区与进入前记录的 TARGET 一致（任务栏恢复后
/// Explorer 异步收回工作区），每 30ms 查一次、上限 1500ms。
///
/// 在退出原生全屏之前调用：等待期间窗口仍铺满屏幕、视频仍在全屏
/// 播放，没有可见的中间态。超时后照常继续（退出时的钳制与
/// SetWindowPos 落点用的都是确定值，见 _restoreMaximizedState）。
Future<void> _waitForWorkAreaSettle(win32.HWND appWindow) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsedMilliseconds < 1500) {
    final monitorInfo = calloc<win32.MONITORINFO>();
    try {
      monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
      final monitor = win32.MonitorFromWindow(
        appWindow,
        win32.MONITOR_DEFAULTTONEAREST,
      );
      if (win32.GetMonitorInfo(monitor, monitorInfo)) {
        final w = monitorInfo.ref.rcWork;
        if (w.left == _savedWorkLeft &&
            w.top == _savedWorkTop &&
            w.right == _savedWorkRight &&
            w.bottom == _savedWorkBottom) {
          return;
        }
      }
    } finally {
      win32.free(monitorInfo);
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

/// 退出全屏后恢复进入前为最大化状态的窗口。
///
/// 退出全屏时窗口仍 IsZoomed 且停在整屏矩形（media_kit fork 进出全屏
/// 不清 WS_MAXIMIZE）。不要先还原成普通状态再重新最大化——那会在屏幕
/// 上产生多次可见的窗口缩放（闪动），且"还原→重新最大化"的落点依赖
/// 实时工作区。正确做法是保持窗口的最大化状态，只把它移动到进入前
/// 记录的目标工作区矩形（与 runner 中 WM_STYLECHANGED 的钳制同模式）：
/// IsZoomed、showCmd、还原矩形全部原样保留，随后补发一条
/// SIZE_MAXIMIZED 的 WM_SIZE，让 window_manager 插件把内部状态机同步
/// 为 MAXIMIZED（其状态只在 WM_SIZE 中切换，缺了这条之后"取消最大化"
/// 的事件会丢失，标题栏按钮与实际状态脱节）。
void _restoreMaximizedState() {
  if (!_wasMaximized) return;
  _wasMaximized = false;
  final appWindow = _appWindow();
  if (appWindow == null) return;
  // 防御：若 fork 行为变化导致窗口已不是最大化状态，则不做移动，
  // 避免把普通状态的窗口摆成"假最大化"。
  if (!win32.IsZoomed(appWindow)) return;
  // 保持最大化状态，把窗口移到目标工作区矩形。
  win32.SetWindowPos(
    appWindow,
    null,
    _savedWorkLeft,
    _savedWorkTop,
    _savedWorkRight - _savedWorkLeft,
    _savedWorkBottom - _savedWorkTop,
    win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
  );
  // 补发 SIZE_MAXIMIZED，让 window_manager 插件状态机同步为
  // MAXIMIZED（lParam 填真实客户区尺寸，供读取方使用）。
  final clientRect = calloc<win32.RECT>();
  try {
    if (win32.GetClientRect(appWindow, clientRect).value) {
      final cx = clientRect.ref.right - clientRect.ref.left;
      final cy = clientRect.ref.bottom - clientRect.ref.top;
      final lParam = (cy << 16) | (cx & 0xFFFF);
      win32.PostMessage(
        appWindow,
        win32.WM_SIZE,
        const win32.WPARAM(win32.SIZE_MAXIMIZED),
        win32.LPARAM(lParam),
      );
    }
  } finally {
    win32.free(clientRect);
  }
}

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  // 窗口全屏（设置开启时）：窗口本身已经铺满显示器，播放器的全屏
  // 只需要切换应用内布局，不再调用（原生）全屏，见 enterWindowFullScreen。
  if (Pref.windowFullScreen) return;
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    if (PlatformUtils.isWindows) {
      // 记录最大化状态与目标工作区（供退出时确定性恢复，只读不改窗口状态）。
      _recordMaximizedState();
      // 再剥标题栏，之后才允许动窗口：下面隐藏任务栏（工作区扩展、系统会
      // 重摆最大化的窗口）、media_kit 的 EnterNativeFullscreen（剥剩余样式
      // 并铺满显示器）都会改窗口状态，标题栏必须已经不在了，顺序见
      // setWindowTitleBarVisible。
      setWindowTitleBarVisible(false);
      _flushCompositor();
      _hideTaskbarOnCurrentMonitor();
    }
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.EnterNativeFullscreen');
    } catch (_) {}
  }
}

/// 退出全屏后把前台与键盘焦点还给应用窗口。
///
/// 键盘焦点实际落在 Flutter 视图（主窗口的子窗口）上，显式设置一次；
/// 主窗口收到 WM_ACTIVATE 后 runner 也会做同样的事。SetForegroundWindow
/// 在进程前台权限受限制时可能失败，短暂重试。
Future<void> _focusAppWindow() async {
  if (!PlatformUtils.isWindows) return;
  final appWindow = _appWindow();
  if (appWindow == null) return;
  final child = win32.GetWindow(appWindow, win32.GW_CHILD).value;
  final hasChild = child.address != 0;
  final target = hasChild ? child : appWindow;
  var foregroundOk = win32.SetForegroundWindow(appWindow);
  win32.SetFocus(target);
  for (var i = 0; i < 2 && !foregroundOk; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    foregroundOk = win32.SetForegroundWindow(appWindow);
  }
  win32.SetFocus(target);
}

@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (!_isDesktopFullScreen) return;
  _isDesktopFullScreen = false;
  if (PlatformUtils.isWindows) {
    // 先恢复任务栏并等工作区落定：窗口此时仍铺满屏幕、视频仍在全屏
    // 播放，任务栏在视频上方滑入（自然的退出观感），不会出现"窗口已
    // 还原但工作区尚未收回"的中间态。
    _restoreTaskbars();
    if (_wasMaximized) {
      final appWindow = _appWindow();
      if (appWindow != null) {
        await _waitForWorkAreaSettle(appWindow);
      }
    }
  }
  try {
    await const MethodChannel(
      'com.alexmercerind/media_kit_video',
    ).invokeMethod('Utils.ExitNativeFullscreen');
  } catch (_) {}
  if (PlatformUtils.isWindows) {
    // 把窗口恢复成进入前为最大化时的状态，再恢复焦点。
    _restoreMaximizedState();
    await _focusAppWindow();
  }
}

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

Future<void>? portraitUpMode() {
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [.landscapeRight]);
}

Future<void>? fullMode() {
  return _setPreferredOrientations(
    const [.portraitUp, .portraitDown, .landscapeLeft, .landscapeRight],
  );
}

bool _showSystemBar = true;
bool get showSystemBar_ => _showSystemBar;
Future<void>? hideSystemBar() {
  if (!_showSystemBar) {
    return null;
  }
  _showSystemBar = false;
  return SystemChrome.setEnabledSystemUIMode(.immersiveSticky);
}

//退出全屏显示
Future<void>? showSystemBar() {
  if (_showSystemBar) {
    return null;
  }
  _showSystemBar = true;
  return SystemChrome.setEnabledSystemUIMode(
    Platform.isAndroid && DeviceUtils.sdkInt < 29 ? .manual : .edgeToEdge,
    overlays: SystemUiOverlay.values,
  );
}
