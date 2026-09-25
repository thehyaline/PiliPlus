#include "win32_window.h"

#include <algorithm>
#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

// Same redefinition for the corner preference / border color attributes.
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

// Returns the effective DPI of |monitor| via shcore.dll (Win8.1+),
// dynamically loaded so old systems fall back to 0 (guard disabled).
UINT DpiForMonitor(HMONITOR monitor) {
  using GetDpiForMonitorFn = HRESULT(WINAPI*)(HMONITOR, int, UINT*, UINT*);
  static GetDpiForMonitorFn fn = []() -> GetDpiForMonitorFn {
    HMODULE shcore = LoadLibraryA("Shcore.dll");
    if (!shcore) {
      return nullptr;
    }
    return reinterpret_cast<GetDpiForMonitorFn>(
        GetProcAddress(shcore, "GetDpiForMonitor"));
  }();
  if (fn == nullptr) {
    return 0;
  }
  UINT dpi_x = 0;
  UINT dpi_y = 0;
  if (FAILED(fn(monitor, 0 /*MDT_EFFECTIVE_DPI*/, &dpi_x, &dpi_y))) {
    return 0;
  }
  return dpi_x;
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();
  creation_time_ = GetTickCount64();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  // 默认是带系统标题栏的普通窗口：拖动、边框缩放、系统菜单、阴影与 Win11
  // 圆角都由系统负责。开启「窗口全屏」时由 Dart 侧剥掉 WS_CAPTION
  // （见 fullscreen.dart 的 SetWindowTitleBarVisible），此后客户区铺满整窗、
  // 边框缩放改由下面的 WM_NCCALCSIZE / WM_NCHITTEST 提供。
  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  // Win11: 显式使用 WinUI3 标准圆角（8px），带不带系统标题栏都一致，
  // 不依赖系统对窗口形态的默认判断；最大化/全屏时系统会自动保持直角。
  DWORD corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_WINDOWPOSCHANGING: {
      // 启动初期，外部窗口管理工具（Shell/开始菜单/资源管理器等）会把
      // 新窗口搬到发起启动的显示器。此类迁移不限于 SetWindowPlacement
      // 的完整移动（可能不带 NOACTIVATE|NOZORDER，也可能只移动位置或
      // 只改尺寸），因此启动 30 秒内只要会把窗口移到不同 DPI 的显示器
      // 一律拦截，不看 flags 和是否携带尺寸。窗口一旦跨 DPI 迁移
      // （DPI-unaware 调用者传的坐标会被系统换算成物理像素）就会连锁
      // 触发 WM_DPICHANGED 缩放，而启动阶段首帧尚未渲染，引擎 surface
      // 重建等不到光栅帧而超时损坏，表现为“窗口不见了、任务栏还有
      // 任务”或“窗口透明只剩边框”。用户手动拖动（拖动期间不拦截）、
      // 最大化/还原（同一显示器内）不受影响；同 DPI 显示器间的迁移不
      // 触发 DPI 链、保持放行。30 秒后完全放行，避免影响显示器拔插时
      // 的窗口重排。
      auto* wp = reinterpret_cast<WINDOWPOS*>(lparam);
      if (wp != nullptr && !in_drag_move_ &&
          GetTickCount64() - creation_time_ < 30000) {
        RECT current{};
        if (GetWindowRect(hwnd, &current)) {
          // 用矩形中心点判定所在显示器，避免跨屏矩形时 MonitorFromRect
          // 只按相交面积取显示器而误判目标。
          HMONITOR cur_monitor = MonitorFromPoint(
              {current.left + (current.right - current.left) / 2,
               current.top + (current.bottom - current.top) / 2},
              MONITOR_DEFAULTTONEAREST);
          HMONITOR dst_monitor = MonitorFromPoint(
              {wp->x + wp->cx / 2, wp->y + wp->cy / 2},
              MONITOR_DEFAULTTONEAREST);
          if (cur_monitor != dst_monitor &&
              DpiForMonitor(dst_monitor) != GetDpiForWindow(hwnd)) {
            // 返回 TRUE 让系统取消整个位置变更流程。仅把坐标改回当前矩形
            // 不足以阻止 User32 内部跨 DPI 处理链——子窗口（FlutterView）
            // 的 WS_VISIBLE 会被破坏且没有后续完整迁移来修复，表现为
            // 窗口透明只剩 DWM 边框。
            return TRUE;
          }
        }
      }
      break;
    }
    case WM_WINDOWPOSCHANGED: {
      auto* wp = reinterpret_cast<WINDOWPOS*>(lparam);
      if (wp != nullptr && (wp->flags & SWP_SHOWWINDOW) &&
          child_content_ != nullptr && !IsWindowVisible(child_content_)) {
        // 兜底：show 流程完成后 FlutterView 子窗口 WS_VISIBLE 仍未恢复
        // 时强制显示（跨 DPI 异步 SetWindowPos 竞争会破坏该状态）。
        ShowWindow(child_content_, SW_SHOW);
      }
      break;
    }
    case WM_ENTERSIZEMOVE:
      in_drag_move_ = true;
      break;

    case WM_EXITSIZEMOVE:
      in_drag_move_ = false;
      break;
    case WM_SYSCOMMAND:
      if (wparam == SC_KEYMENU && (lparam >> 16) <= 0) {
        return 0;
      }
      if (wparam == SC_MAXIMIZE) {
        // 自绘标题栏下 DefWindowProc 走的是 WINDOWPLACEMENT/rcNormalPosition
        // 的通用最大化路径，副屏时会把窗口放到错误的位置；改为确定性最大化：
        // 先把当前矩形保存为还原矩形，再铺满 MonitorFromWindow 对应的工作区。
        if (!IsZoomed(hwnd)) {
          WINDOWPLACEMENT placement{};
          placement.length = sizeof(placement);
          GetWindowPlacement(hwnd, &placement);
          GetWindowRect(hwnd, &placement.rcNormalPosition);
          placement.showCmd = SW_MAXIMIZE;
          SetWindowPlacement(hwnd, &placement);
          MONITORINFO monitor_info{};
          monitor_info.cbSize = sizeof(monitor_info);
          HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
          if (GetMonitorInfo(monitor, &monitor_info)) {
            SetWindowPos(hwnd, nullptr, monitor_info.rcWork.left,
                         monitor_info.rcWork.top,
                         monitor_info.rcWork.right - monitor_info.rcWork.left,
                         monitor_info.rcWork.bottom - monitor_info.rcWork.top,
                         SWP_NOZORDER | SWP_NOACTIVATE);
          }
        }
        return 0;
      }
    break;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_SHOWWINDOW:
      if (wparam != 0 && child_content_ != nullptr) {
        const LRESULT result = DefWindowProc(hwnd, message, wparam, lparam);
        // 兜底：跨 DPI 异步 SetWindowPos 竞争会丢失 FlutterView 子窗口的
        // WS_VISIBLE，客户区无内容表现为整窗透明只剩 DWM 边框。show 后
        // 强制恢复子窗口可见性。
        if (!IsWindowVisible(child_content_)) {
          ShowWindow(child_content_, SW_SHOW);
        }
        return result;
      }
      break;

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_NCACTIVATE:
      // 无标题栏（「窗口全屏」剥掉了 WS_CAPTION）时非客户区为空、客户区
      // 铺满整窗：跳过默认的边框重绘，避免焦点切出/切回时 DWM 边框闪白。
      // 带标题栏时交给系统，让标题栏按钮跟随焦点状态重绘。
      if (!(GetWindowLongPtr(hwnd, GWL_STYLE) & WS_CAPTION)) {
        return TRUE;
      }
      break;

    case WM_ERASEBKGND:
      // 窗口类没有背景画刷，无需擦除。
      return 1;

    case WM_NCCALCSIZE:
      // 带系统标题栏（「窗口全屏」关闭）时客户区由系统计算，标题栏照常
      // 显示（见 SetWindowTitleBarVisible）。
      if (GetWindowLongPtr(hwnd, GWL_STYLE) & WS_CAPTION) {
        break;
      }
      // WS_CAPTION is removed but WS_THICKFRAME still reserves a non-client
      // border (a ~7px empty strip on top plus thin lines on the other
      // edges). Let the client area fill the whole window; edge resize
      // hit-testing is provided by WM_NCHITTEST below.
      return 0;

    case WM_NCHITTEST: {
      // 带系统标题栏时命中测试（标题栏拖动、系统菜单、边框缩放）交给系统。
      if (GetWindowLongPtr(hwnd, GWL_STYLE) & WS_CAPTION) {
        break;
      }
      // 客户区占满窗口后 DefWindowProc 不再提供边缘缩放命中区
      // （全部返回 HTCLIENT），这里按系统边框宽度手动返回。鼠标在
      // Flutter 视图子窗口上时由该子窗口的命中测试走同一逻辑
      // （见 flutter_window.cpp）。
      const POINT pt = {static_cast<LONG>(static_cast<short>(LOWORD(lparam))),
                        static_cast<LONG>(static_cast<short>(HIWORD(lparam)))};
      return HitTestResizeBorder(hwnd, pt);
    }

//    case WM_DWMCOLORIZATIONCOLORCHANGED:
//      UpdateTheme(hwnd);
//      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
    // 固定 DWM 边框颜色，避免激活状态变化时边框闪色。
    DWORD border_color = enable_dark_mode ? 0x1C1C1C : 0xFFFFFF;
    DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &border_color,
                          sizeof(border_color));
  }
}

LRESULT HitTestResizeBorder(HWND hwnd, POINT pt) {
  const LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
  // 带系统标题栏时（「窗口全屏」关闭，见 SetWindowTitleBarVisible）缩放、
  // 拖动、系统菜单全部由系统负责，这里不再提供命中区。
  if (style & WS_CAPTION) {
    return HTCLIENT;
  }
  // 全屏样式（media_kit 原生全屏 / 窗口全屏都会剥掉 WS_OVERLAPPEDWINDOW）
  // 下窗口铺满整屏、不可缩放，屏幕边缘不应有缩放命中区，否则碰一下边缘
  // 就会把全屏窗口拽小。
  if (!(style & WS_OVERLAPPEDWINDOW)) {
    return HTCLIENT;
  }
  if (IsZoomed(hwnd)) {
    // 最大化时窗口铺满工作区，边缘不应再响应缩放。media_kit 原生全屏
    // 退出后窗口可能停留在“最大化 + 整屏矩形”的卡死状态（盖住任务栏），
    // 这里顺带钳回工作区，让边缘缩放恢复。
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    if (GetMonitorInfo(monitor, &monitor_info)) {
      RECT rc;
      GetWindowRect(hwnd, &rc);
      if (EqualRect(&rc, &monitor_info.rcMonitor)) {
        SetWindowPos(hwnd, nullptr, monitor_info.rcWork.left,
                     monitor_info.rcWork.top,
                     monitor_info.rcWork.right - monitor_info.rcWork.left,
                     monitor_info.rcWork.bottom - monitor_info.rcWork.top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
      }
    }
    return HTCLIENT;
  }

  RECT rc;
  GetWindowRect(hwnd, &rc);
  // GetSystemMetrics 按系统 DPI 返回边框宽度，换算到窗口所在显示器的
  // 物理像素，保证高分屏上命中区宽度一致。
  const double dpi_ratio =
      GetDpiForWindow(hwnd) / static_cast<double>(GetDpiForSystem());
  const int frame = std::max(
      8, static_cast<int>((GetSystemMetrics(SM_CXSIZEFRAME) +
                           GetSystemMetrics(SM_CXPADDEDBORDER)) *
                              dpi_ratio +
                          0.5));
  // 与系统边框行为一致，命中区同时覆盖窗口外侧一圈。
  const bool left = pt.x >= rc.left - frame && pt.x < rc.left + frame;
  const bool right = pt.x < rc.right + frame && pt.x >= rc.right - frame;
  const bool top = pt.y >= rc.top - frame && pt.y < rc.top + frame;
  const bool bottom = pt.y < rc.bottom + frame && pt.y >= rc.bottom - frame;
  if (top && left) return HTTOPLEFT;
  if (top && right) return HTTOPRIGHT;
  if (bottom && left) return HTBOTTOMLEFT;
  if (bottom && right) return HTBOTTOMRIGHT;
  if (top) return HTTOP;
  if (bottom) return HTBOTTOM;
  if (left) return HTLEFT;
  if (right) return HTRIGHT;
  return HTCLIENT;
}
