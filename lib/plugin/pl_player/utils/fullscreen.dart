import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart'
    show SystemChrome, MethodChannel, SystemUiOverlay, DeviceOrientation;
import 'package:window_manager/window_manager.dart' show kWindowCaptionHeight;
import 'package:win32/win32.dart' as win32;

bool _isDesktopFullScreen = false;

/// 进入原生全屏时隐藏的任务栏窗口，退出全屏时恢复。
///
/// Windows 只会对覆盖主显示器整屏的窗口自动隐藏主任务栏，副屏任务栏
/// 不会自动隐藏，会浮在全屏窗口上方（表现为全屏排除了任务栏区域）。
/// 因此进入原生全屏前主动隐藏所在显示器的任务栏（Shell_TrayWnd /
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
  final monitor =
      win32.MonitorFromWindow(appWindow, win32.MONITOR_DEFAULTTONEAREST);
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
    win32.ShowWindow(hwnd, win32.SW_SHOW);
  }
  _hiddenTaskbars.clear();
}

/// 恢复所有任务栏，供应用启动/关闭时兜底调用（覆盖上次异常退出残留的隐藏状态）。
void restoreAllTaskbars() {
  if (!PlatformUtils.isWindows) return;
  _forEachTaskbar((hwnd) => win32.ShowWindow(hwnd, win32.SW_SHOW));
  _hiddenTaskbars.clear();
}

/// 进入全屏前窗口是否为最大化状态，退出全屏后恢复。
///
/// 最大化状态由 media_kit fork 的原生全屏自行清除（utils.cc 在剥
/// WS_OVERLAPPEDWINDOW 的同时清 WS_MAXIMIZE，避免窗口保持 IsZoomed
/// 被钳制回工作区），这里只记录状态供退出时恢复，不动窗口。
bool _wasMaximized = false;

/// 进入全屏前记录的窗口还原矩形（仅在窗口最大化时保存）。
///
/// media_kit fork 的 EnterNativeFullscreen 把还原矩形存进
/// rect_before_fullscreen_，退出时把窗口放回该矩形（即“最大化前的位置
/// 和大小”）；若进入前为最大化，这里用 SetWindowPlacement 一步把窗口
/// 恢复为最大化，并写回还原矩形。
int _savedNormalLeft = 0;
int _savedNormalTop = 0;
int _savedNormalRight = 0;
int _savedNormalBottom = 0;

/// 全屏状态机的诊断日志：debugPrint 之外追加写入系统临时目录，
/// 便于用户直接从文件反馈（终端里看不到 Flutter 日志时）。
final File _fsLogFile = File('${Directory.systemTemp.path}/piliplus_fs.log');

void _log(String message) {
  final line = '[PiliPlus FS] $message';
  debugPrint(line);
  try {
    _fsLogFile.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $line\n',
      mode: FileMode.append,
    );
  } catch (_) {
    // 日志文件写入失败不影响全屏流程。
  }
}

void _recordMaximizedState() {
  final appWindow = _appWindow();
  if (appWindow == null) {
    _log('record: appWindow not found');
    return;
  }
  final placement = calloc<win32.WINDOWPLACEMENT>();
  try {
    placement.ref.length = sizeOf<win32.WINDOWPLACEMENT>();
    if (!win32.GetWindowPlacement(appWindow, placement).value) {
      _log('record: GetWindowPlacement failed');
      return;
    }
    final r = placement.ref.rcNormalPosition;
    _log('record: showCmd=${placement.ref.showCmd} '
        'IsZoomed=${win32.IsZoomed(appWindow)} '
        'normal=(${r.left},${r.top},${r.right},${r.bottom})');
    if (placement.ref.showCmd == win32.SW_MAXIMIZE) {
      _wasMaximized = true;
      _savedNormalLeft = r.left;
      _savedNormalTop = r.top;
      _savedNormalRight = r.right;
      _savedNormalBottom = r.bottom;
    }
  } finally {
    win32.free(placement);
  }
}

/// 兜底清除窗口上的 WS_CAPTION 样式。
///
/// media_kit fork 的 ExitNativeFullscreen 已改为恢复样式时不加
/// WS_CAPTION（utils.cc），此处防御 fork 被上游版本覆盖时旧行为
/// （`style | WS_OVERLAPPEDWINDOW` 把创建时剥掉的 WS_CAPTION 加回来）
/// 导致的系统标题栏残留。窗口样式正常时此函数为无操作。
void _stripCaptionStyle() {
  final appWindow = _appWindow();
  if (appWindow == null) return;
  final style = win32.GetWindowLongPtr(appWindow, win32.GWL_STYLE).value;
  if (style & win32.WS_CAPTION != 0) {
    win32.SetWindowLongPtr(
      appWindow,
      win32.GWL_STYLE,
      style & ~win32.WS_CAPTION,
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
}

void _restoreMaximizedState() {
  _log('restore: _wasMaximized=$_wasMaximized');
  if (!_wasMaximized) return;
  _wasMaximized = false;
  final appWindow = _appWindow();
  if (appWindow == null) {
    _log('restore: appWindow not found');
    return;
  }
  final placement = calloc<win32.WINDOWPLACEMENT>();
  try {
    placement.ref.length = sizeOf<win32.WINDOWPLACEMENT>();
    placement.ref.showCmd = win32.SW_MAXIMIZE;
    placement.ref.rcNormalPosition.left = _savedNormalLeft;
    placement.ref.rcNormalPosition.top = _savedNormalTop;
    placement.ref.rcNormalPosition.right = _savedNormalRight;
    placement.ref.rcNormalPosition.bottom = _savedNormalBottom;
    final ok = win32.SetWindowPlacement(appWindow, placement).value;
    _log('restore: SetWindowPlacement ok=$ok '
        'IsZoomed=${win32.IsZoomed(appWindow)}');
  } finally {
    win32.free(placement);
  }
}

/// 桌面端自绘标题栏的隐藏开关：原生全屏、桌面画中画期间置为 true。
final ValueNotifier<bool> desktopCaptionHidden = ValueNotifier(false);

/// Windows 自绘标题栏当前占用的布局高度（标题栏可见时为 32，否则为 0）。
///
/// 自绘标题栏是窗口内布局的一部分（见 main.dart 的 builder），
/// 但它的高度不会体现在 MediaQuery 中，页面计算可用高度时需要减去它。
double get captionBarHeight {
  if (!PlatformUtils.isWindows || !Pref.showWindowTitleBar) return 0;
  if (desktopCaptionHidden.value) return 0;
  return kWindowCaptionHeight;
}

@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (!inAppFullScreen && !_isDesktopFullScreen) {
    _isDesktopFullScreen = true;
    desktopCaptionHidden.value = true;
    if (PlatformUtils.isWindows) {
      // 最大化状态由原生全屏自行清除（见 _recordMaximizedState），
      // 这里隐藏所在显示器的任务栏，然后铺满显示器。
      _recordMaximizedState();
      _hideTaskbarOnCurrentMonitor();
    }
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.EnterNativeFullscreen');
    } catch (_) {}
  }
}

@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (_isDesktopFullScreen) {
    _isDesktopFullScreen = false;
    desktopCaptionHidden.value = false;
    try {
      await const MethodChannel(
        'com.alexmercerind/media_kit_video',
      ).invokeMethod('Utils.ExitNativeFullscreen');
    } catch (_) {}
    if (PlatformUtils.isWindows) {
      // 先剥掉 media_kit 退出全屏残留的 WS_CAPTION（避免系统标题栏
      // 闪现/残留），再恢复任务栏（工作区随之恢复），最后恢复最大化，
      // 否则最大化会按“任务栏隐藏时的整屏工作区”铺满盖住任务栏。
      _stripCaptionStyle();
      _restoreTaskbars();
      _restoreMaximizedState();
    }
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
