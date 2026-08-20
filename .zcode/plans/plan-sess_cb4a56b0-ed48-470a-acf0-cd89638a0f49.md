## 修复：Windows 最大化窗口退出全屏后遮住任务栏

### 根因
media_kit fork 的原生全屏（`Utils::EnterNativeFullscreen`/`ExitNativeFullscreen`，pub 缓存 `media_kit_video/windows/utils.cc`）在进入全屏时只去掉 `WS_OVERLAPPEDWINDOW`，**不清除 `WS_MAXIMIZE`**，并把窗口移到整屏 `rcMonitor`。退出全屏时 `IsZoomed(window)` 为 true，走 `utils.cc:70-81` 的分支——该分支只做无位移的 `SWP_FRAMECHANGED` 刷新，**从不把边界重新钳制回工作区**，于是窗口保持"最大化"状态但边界停在整屏（遮住任务栏）。

应用自身正常最大化路径（`win32_window.cpp` 的 `SC_MAXIMIZE` 处理，`rcWork` 钳制）不受影响，所以只有全屏往返这一条路径坏掉。

### 改动（仅一个文件）
`E:\Repo\PiliPlus\windows\runner\flutter_window.cpp` 的 `FlutterWindow::MessageHandler` 中，在 `WM_GETMINMAXINFO` 处理块旁边（`HandleTopLevelWindowProc` 之前）新增 `WM_STYLECHANGED` 处理：

- 条件：`wparam == GWL_STYLE`，且恢复后的样式含 `WS_OVERLAPPEDWINDOW`，且 `IsZoomed(hwnd)`。
- 动作：用 `MonitorFromWindow(MONITOR_DEFAULTTONEAREST)` + `GetMonitorInfo` 取 `rcWork`，`SetWindowPos` 将窗口钳制到工作区（与 `win32_window.cpp:246-250` 的 `SC_MAXIMIZE` 处理完全一致），`SWP_NOZORDER | SWP_NOACTIVATE`。
- 附中文注释说明原因（media_kit 全屏不清 WS_MAXIMIZE，退出时边界停留在 rcMonitor）。

时序说明：`WM_STYLECHANGED` 在 `ExitNativeFullscreen` 的 `SetWindowLongPtr` 调用期间同步发送，我们的钳制先执行，media_kit 后续的 `FRAMECHANGED` 刷新与子视图尺寸更新发生在钳制后的正确边界上，最终状态正确且无闪烁。进入全屏时（`WS_OVERLAPPEDWINDOW` 被移除）条件不满足，不会误触发；窗口已在工作区时 `SetWindowPos` 为同值无操作，幂等安全。

### 验证
1. `flutter build windows --debug`（或 IDE 直接运行）确认编译通过。
2. 手动验证：
   - 最大化窗口 → 视频播放器点全屏 → 确认铺满整屏（含任务栏区域）→ 退出全屏 → 窗口回到**避开任务栏**的最大化状态（本 bug）。
   - 回归：非最大化窗口 → 全屏 → 退出 → 恢复原窗口大小（既有 else 分支路径，改动不影响）。
   - 直播播放器全屏往返同路径验证。
   - 最大化状态下全屏按钮二次触发、Esc 退出等入口抽查。

不需要改动 Dart 侧、media_kit 缓存或 pubspec。