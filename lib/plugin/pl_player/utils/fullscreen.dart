import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:PiliPlus/utils/device_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:ffi/ffi.dart' show calloc;
import 'package:flutter/services.dart'
    show SystemChrome, SystemUiOverlay, DeviceOrientation;
import 'package:window_manager/window_manager.dart' show windowManager;
import 'package:win32/win32.dart' as win32;

/// 播放器全屏（「窗口全屏」设置关闭时的那一档）进行中，见
/// [enterDesktopFullScreen] / [exitDesktopFullScreen]。
bool _isDesktopFullScreen = false;

/// 本应用记的窗口全屏状态；以及进全屏前窗口是否最大化（进入时还原掉，退出时
/// 最大化回来）。
///
/// 状态自己记、不去问平台（同 Shale 的 FullscreenService）：窗口全屏只有本应用
/// 在切，自己记的与插件里那个变量一致，能省一次平台通道往返。
bool _isWindowFullScreen = false;
bool _wasMaximized = false;

/// 应用主窗口的类名，与 windows/runner/win32_window.cpp 保持一致。
const _kAppWindowClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

/// 本应用的主窗口（按类名查找并校验 PID，避免命中其他 Flutter 应用）。
///
/// 只用于两件平台接口给不了的事：剥/恢复标题栏（[setWindowTitleBarVisible]）
/// 和退出全屏后把焦点还给窗口（[_focusAppWindow]）。
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

/// 显示/隐藏系统标题栏（`WS_CAPTION`）。
///
/// 窗口默认带系统标题栏（见 windows/runner/win32_window.cpp）：有标题栏时
/// 拖动、边框缩放、系统菜单全交回系统；全屏期间剥掉它，客户区铺满整窗，runner
/// 在 `WM_NCCALCSIZE`、`WM_NCHITTEST`、`WM_NCACTIVATE` 中按同一位判断。
///
/// 为什么插件管不了这位：window_manager 的 `setFullScreen` 只剥
/// `WS_THICKFRAME | WS_MAXIMIZEBOX`（media_kit 那套写法），`WS_CAPTION` 留着，
/// 整屏窗口顶上就会挂一条系统标题栏，所以由应用自己剥、退出时自己恢复。顺序上
/// 进全屏要剥在 `setFullScreen(true)` 之前（插件要把剥好的样式存下来），退出要
/// 恢复在 `setFullScreen(false)` 之后（插件会把存的那份样式写回来，会盖掉先恢复
/// 的标题栏），见 [_setWindowFullScreen]。
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

/// 切换窗口全屏：一律走 window_manager 的 `setFullScreen`（和 Shale 一样），
/// 应用不碰任务栏、也不自己摆窗口几何。
///
/// 插件在 Windows 上做的就是媒体播放器软件那一套：读所在显示器信息、剥掉
/// `WS_THICKFRAME | WS_MAXIMIZEBOX`、把窗口摆到显示器的 `rcMonitor`（整块屏幕，
/// 不是工作区），退出时照「进全屏那一刻」存下的样式与矩形写回去。窗口盖住整块
/// 显示器后，主任务栏的隐藏与恢复由系统自己处理（浏览器全屏同理）——应用一次都
/// 不去 ShowWindow 任务栏，也就不会把它停在本不该有的隐藏状态上。
///
/// 应用自己只管三件插件管不了的事（都不是任务栏）：
/// - 剥/恢复标题栏，见 [setWindowTitleBarVisible]；
/// - 最大化状态：Windows 不把最大化窗口认成全屏窗口，那样任务栏会压在全屏窗口
///   最上层，进全屏前先用插件的 unmaximize 还原掉、退出时再 maximize 回来（退出
///   前也要确认窗口不是最大化，见代码）；
/// - 可见性：进全屏时窗口若还隐藏着（启动即全屏那条路，见 main.dart），插件存下
///   的样式里没有 `WS_VISIBLE`，退出写回后窗口就成了「看不见的窗口」（托盘图标
///   还在、鼠标点不着，同 Shale 的 FullscreenService），所以退出后补一次 show。
///
/// 状态没变时直接返回：插件那两步都会重摆一遍窗口（剥样式 + 两次 SetWindowPos），
/// 白做一次就是一次看得见的闪动；状态自己记着，该不该动窗口不必问平台。
Future<void> _setWindowFullScreen(bool value) async {
  if (_isWindowFullScreen == value) return;
  if (value) {
    // 剥标题栏必须在插件存样式之前，见 setWindowTitleBarVisible。
    setWindowTitleBarVisible(false);
    _wasMaximized = (await _isMaximized()) ?? false;
    if (_wasMaximized) {
      // 还原失败不拦着进全屏：那样只是回到「最大化 + 整屏」的样子（任务栏压在
      // 最上层），窗口本身仍是全屏的。
      try {
        await windowManager.unmaximize();
      } catch (_) {}
    }
    try {
      await windowManager.setFullScreen(true);
    } catch (_) {
      // 平台调用失败（窗口还没建好等）：标题栏还回去，状态不动，下次切换重试。
      setWindowTitleBarVisible(true);
      return;
    }
    _isWindowFullScreen = true;
    return;
  }
  final wasVisible = await _isVisible();
  if ((await _isMaximized()) ?? false) {
    // 全屏期间窗口被最大化过（Win+Up 之类）：先还原。插件退出全屏时若发现窗口
    // 是最大化状态，只刷新不摆位置，会把窗口留在「最大化 + 整屏矩形」且不解除它
    // 自己的无边框标记；还原之后退出走的才是那条把样式和矩形都摆回去的常规路径。
    // 这份最大化状态照记，退出后最大化回去（和进全屏前就最大化的情况一样）。
    _wasMaximized = true;
    try {
      await windowManager.unmaximize();
    } catch (_) {}
  }
  try {
    await windowManager.setFullScreen(false);
  } catch (_) {
    return;
  }
  _isWindowFullScreen = false;
  // 标题栏要等插件把样式写回之后再恢复，见 setWindowTitleBarVisible。
  setWindowTitleBarVisible(true);
  if (_wasMaximized) {
    _wasMaximized = false;
    try {
      await windowManager.maximize();
    } catch (_) {}
  }
  // 退出前窗口本来就看不见（收着启动、启动即全屏）：那种窗口该继续看不见，
  // 不管它；看得见而退出后被样式写回弄没了，补一次 show（它专门补 WS_VISIBLE）。
  if (wasVisible == true && await _isVisible() == false) {
    try {
      await windowManager.show();
    } catch (_) {}
  }
}

/// 窗口此刻是否最大化 / 是否可见；问不出来（平台通道出岔子）时为 null。
Future<bool?> _isMaximized() async {
  try {
    return await windowManager.isMaximized();
  } catch (_) {
    return null;
  }
}

Future<bool?> _isVisible() async {
  try {
    return await windowManager.isVisible();
  } catch (_) {
    return null;
  }
}

/// 进入窗口全屏（设置-外观里的「窗口全屏」开关 / F11 / 启动时）。
///
/// 窗口铺满所在显示器的整块屏幕、无边框（[_setWindowFullScreen]）。任务栏的隐藏
/// 与恢复由系统自己处理：鼠标移到屏幕下沿它就滑出来，切到别的窗口也照常，应用
/// 从头到尾不去动它。播放器全屏（[enterDesktopFullScreen]）用的是同一套窗口全屏
/// ——播放器的全屏等于「应用内布局进全屏 + 这一次窗口全屏」，两者效果一致。
///
/// 重复调用（从托盘恢复显示、设置页开关）是空操作，状态没变时
/// [_setWindowFullScreen] 直接返回。
Future<void> enterWindowFullScreen() async {
  // 播放器全屏进行中：窗口此刻已经全屏，那一套状态由
  // enterDesktopFullScreen / exitDesktopFullScreen 负责，这里不插手——两种全屏
  // 共用同一个窗口，这时候再动窗口只会让播放器退出全屏时把这份状态一并盖掉。
  // 设置本身已经写进存储（开关那一下先落设置），下次启动、F11、进出托盘
  // 都会照它应用（同 toggleWindowFullScreen 在播放器全屏里的让位）。
  if (_isDesktopFullScreen) return;
  await _setWindowFullScreen(true);
}

/// 退出窗口全屏（设置开关关闭 / F11）。
///
/// 窗口交回插件恢复：样式、矩形都照进全屏那一刻存的那份写回来（进全屏前最大化的
/// 话再最大化回去、窗口当时若还隐藏着则补一次 show），见 [_setWindowFullScreen]。
@pragma('vm:notify-debugger-on-exception')
Future<void> exitWindowFullScreen() async {
  // 播放器全屏进行中：窗口归 enter/exitDesktopFullScreen 管，见
  // enterWindowFullScreen。
  if (_isDesktopFullScreen) return;
  await _setWindowFullScreen(false);
}

/// 切换「窗口全屏」：设置-外观里的开关与 F11 共用同一份状态。
///
/// 先写设置再应用——这样下次启动照最后的状态打开（开关本身就代表着这个
/// 状态），也顺带让设置页的开关跟着 F11 变（见 SetSwitchItem 的存储监听）。
@pragma('vm:notify-debugger-on-exception')
Future<void> toggleWindowFullScreen() async {
  // 播放器全屏期间窗口已经是全屏，这一键不动它：退出全屏仍由播放器的按钮 /
  // Esc 负责，两种全屏状态不互相打断。
  if (_isDesktopFullScreen) return;
  final next = !Pref.windowFullScreen;
  await GStorage.setting.put(SettingBoxKey.windowFullScreen, next);
  if (next) {
    await enterWindowFullScreen();
  } else {
    await exitWindowFullScreen();
  }
}

/// 进入播放器全屏：应用内布局进全屏（`isFullScreen`）+ 窗口全屏，也就是
/// 「视频窗口全屏的同时窗口也全屏」。
///
/// 「窗口全屏」设置开着时窗口本来就全屏，这里只切应用内布局（见
/// [enterWindowFullScreen] 为什么直接返回）。[inAppFullScreen] 是「只进应用内
/// 全屏、不动窗口」那条路（Web 全屏等调用方显式指定）。
@pragma('vm:notify-debugger-on-exception')
Future<void> enterDesktopFullScreen({bool inAppFullScreen = false}) async {
  if (Pref.windowFullScreen) return;
  if (inAppFullScreen || _isDesktopFullScreen) return;
  _isDesktopFullScreen = true;
  await _setWindowFullScreen(true);
}

/// 退出播放器全屏：窗口全屏一并退出（「窗口全屏」设置开着的话窗口保持全屏，只切
/// 应用内布局），并把前台与键盘焦点还给应用窗口。
@pragma('vm:notify-debugger-on-exception')
Future<void> exitDesktopFullScreen() async {
  if (!_isDesktopFullScreen) return;
  _isDesktopFullScreen = false;
  // 设置在这期间被打开了：窗口按设置保持全屏，只切应用内布局。
  if (Pref.windowFullScreen) return;
  await _setWindowFullScreen(false);
  await _focusAppWindow();
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

List<DeviceOrientation>? _lastOrientation;
Future<void>? _setPreferredOrientations(List<DeviceOrientation> orientations) {
  if (_lastOrientation == orientations) {
    return null;
  }
  _lastOrientation = orientations;
  return SystemChrome.setPreferredOrientations(orientations);
}

/// 电视上唯一站得住的形态就是横屏（见 `DeviceUtils.isTv`）：电视屏是横的，也没有
/// 重力传感器，任何"换成竖屏"的请求都会被系统兑现成**一个竖屏窗口**——把它摆在
/// 横屏面板正中，左右各留一条黑边。所以电视上把这些请求统一收敛成横屏，调用方
/// （播放器跟着视频方向转屏、退出全屏时复位、设置页预览离开时还原）不必各自判平台。
///
/// 连"不锁方向"（[fullMode]，FULL_SENSOR）也一并收敛：碰到框架自认竖屏的电视
/// 盒子，系统会顺着它选回竖屏，等于没修。
Future<void>? portraitUpMode() {
  if (DeviceUtils.isTv) return landscapeLeftMode();
  return _setPreferredOrientations(const [.portraitUp]);
}

Future<void>? portraitDownMode() {
  if (DeviceUtils.isTv) return landscapeLeftMode();
  return _setPreferredOrientations(const [.portraitDown]);
}

Future<void>? landscapeLeftMode() {
  return _setPreferredOrientations(const [.landscapeLeft]);
}

Future<void>? landscapeRightMode() {
  return _setPreferredOrientations(const [.landscapeRight]);
}

Future<void>? fullMode() {
  if (DeviceUtils.isTv) return landscapeLeftMode();
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
