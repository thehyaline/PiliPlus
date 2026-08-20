#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "win32_window.h"

#include <imm.h>

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The native window of the Flutter view; it receives keyboard input.
  HWND child_window_ = nullptr;

  // 无文本输入框聚焦时解除窗口 IME 关联，避免中文输入法消费按键
  // 导致播放器快捷键失效；聚焦输入框时恢复关联。
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> ime_channel_;
  bool ime_enabled_ = true;
  HIMC top_ime_context_ = nullptr;
  HIMC child_ime_context_ = nullptr;

  // 处理 Dart 侧 ImeController 发来的 setEnabled 消息。
  void SetImeEnabled(bool enabled);

  // 关联/解除 |hwnd| 的输入法上下文；首次解除时保存原上下文用于恢复。
  static void SetWindowIme(HWND hwnd, bool enabled, HIMC& saved_context);

  // Fills |info| with maximized bounds limited to the monitor work area.
  // The window_manager plugin consumes WM_GETMINMAXINFO and returns 0 without
  // writing the maximize rect, so without this the window would maximize over
  // the whole screen including the taskbar.
  static void AdjustMaximizeBounds(HWND hwnd, MINMAXINFO* info);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
