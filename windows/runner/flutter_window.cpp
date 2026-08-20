#include "flutter_window.h"

#include <commctrl.h>
#include <optional>
#include <variant>
#include <windowsx.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// The engine's Flutter view is a child window covering the whole client area,
// so WM_NCHITTEST goes to it (DefWindowProc returns HTCLIENT) and the
// top-level window never gets a chance to run its own hit-test for points
// inside the window. Subclass the view to answer the resize-border hit-test
// for the top-level window and to forward non-client mouse messages to it,
// which lets DefWindowProc run the native resize loop.
LRESULT CALLBACK FlutterViewSubclassProc(HWND hwnd, UINT const message,
                                         WPARAM const wparam,
                                         LPARAM const lparam, UINT_PTR,
                                         DWORD_PTR) noexcept {
  switch (message) {
    case WM_NCHITTEST: {
      HWND parent = GetParent(hwnd);
      if (!parent) {
        return HTCLIENT;
      }
      POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      return HitTestResizeBorder(parent, pt);
    }
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
    case WM_NCLBUTTONUP:
      // 命中代码位于 wParam（HTLEFT..HTBOTTOMRIGHT 连续），把边框操作
      // 转交给顶层窗口，由其 DefWindowProc 执行原生 resize 循环 /
      // 双击最大化。
      if (wparam >= HTLEFT && wparam <= HTBOTTOMRIGHT) {
        HWND parent = GetParent(hwnd);
        if (parent) {
          return SendMessage(parent, message, wparam, lparam);
        }
      }
      break;
    case WM_SETCURSOR:
      // 引擎在 HTCLIENT 时吞掉 WM_SETCURSOR 以免光标被重置回类光标；
      // 边缘命中时这里显式设置 resize 光标。
      switch (LOWORD(lparam)) {
        case HTLEFT:
        case HTRIGHT:
          SetCursor(LoadCursor(nullptr, IDC_SIZEWE));
          return TRUE;
        case HTTOP:
        case HTBOTTOM:
          SetCursor(LoadCursor(nullptr, IDC_SIZENS));
          return TRUE;
        case HTTOPLEFT:
        case HTBOTTOMRIGHT:
          SetCursor(LoadCursor(nullptr, IDC_SIZENWSE));
          return TRUE;
        case HTTOPRIGHT:
        case HTBOTTOMLEFT:
          SetCursor(LoadCursor(nullptr, IDC_SIZENESW));
          return TRUE;
        default:
          break;
      }
      break;
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  child_window_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(child_window_);

  // 客户区被 Flutter 子窗口铺满后，边缘缩放命中测试必须由该子窗口
  // 应答（见 FlutterViewSubclassProc），否则顶层窗口收不到
  // WM_NCHITTEST。
  SetWindowSubclass(child_window_, FlutterViewSubclassProc, 0, 0);

  ime_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "piliplus/ime",
          &flutter::StandardMethodCodec::GetInstance());
  ime_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setEnabled") {
          if (const auto* enabled = std::get_if<bool>(call.arguments())) {
            SetImeEnabled(*enabled);
          }
        }
        result->Success();
      });

  // flutter_controller_->engine()->SetNextFrameCallback([&]() {
  //   this->Show();
  // });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ime_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetImeEnabled(bool enabled) {
  if (enabled == ime_enabled_) {
    return;
  }
  ime_enabled_ = enabled;
  // 键盘输入实际落在 Flutter 子窗口，顶层窗口也一并处理以防输入法
  // 按顶层窗口状态判断。
  SetWindowIme(GetHandle(), enabled, top_ime_context_);
  SetWindowIme(child_window_, enabled, child_ime_context_);
}

// static
void FlutterWindow::SetWindowIme(HWND hwnd, bool enabled, HIMC& saved_context) {
  if (enabled) {
    ImmAssociateContext(hwnd, saved_context);
  } else {
    // ImmAssociateContext 返回之前关联的上下文，首次解除时保存供恢复。
    HIMC previous = ImmAssociateContext(hwnd, nullptr);
    if (saved_context == nullptr) {
      saved_context = previous;
    }
  }
}

// static
void FlutterWindow::AdjustMaximizeBounds(HWND hwnd, MINMAXINFO* info) {
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfo(monitor, &monitor_info)) {
    info->ptMaxPosition = {monitor_info.rcWork.left, monitor_info.rcWork.top};
    info->ptMaxSize = {monitor_info.rcWork.right - monitor_info.rcWork.left,
                       monitor_info.rcWork.bottom - monitor_info.rcWork.top};
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Prefill the maximize rect with the monitor work area before plugins see
  // the message. The window_manager plugin handles WM_GETMINMAXINFO itself
  // (and returns 0 without setting the rect), which would otherwise leave the
  // default fullscreen bounds — the maximized window would cover the taskbar.
  // Plugins can still override the min/max track sizes afterwards.
  if (message == WM_GETMINMAXINFO) {
    AdjustMaximizeBounds(hwnd, reinterpret_cast<MINMAXINFO*>(lparam));
  }

  if (message == WM_STYLECHANGED && wparam == GWL_STYLE &&
      (GetWindowLongPtr(hwnd, GWL_STYLE) & (WS_THICKFRAME | WS_SYSMENU)) &&
      IsZoomed(hwnd)) {
    // media_kit 的原生全屏进出不清除 WS_MAXIMIZE：最大化状态下进入
    // 全屏后，退出全屏时窗口仍处于"最大化"但边界停留在整屏
    // rcMonitor（遮住任务栏）。样式恢复时把窗口重新钳制到监视器
    // 工作区，与 SC_MAXIMIZE 的处理保持一致。
    // 注意窗口样式不含 WS_CAPTION，不能用 WS_OVERLAPPEDWINDOW
    // 判断“非全屏”样式（该掩码要求 WS_CAPTION 位）。
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

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
