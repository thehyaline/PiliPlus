## 目标
去掉 Windows 原生标题栏，只保留 Flutter 自绘的 WinUI3 样式标题栏。

## 现状分析（已核实）
- 原生侧已正确实现：`windows/runner/win32_window.cpp:142-146` 创建窗口时使用 `WS_OVERLAPPEDWINDOW & ~WS_CAPTION`（未提交改动），去掉标题栏但保留 WS_THICKFRAME/WS_SYSMENU，从而保留缩放、阴影和 Win11 圆角。这是去除标题栏的标准做法，**不需要再改代码**。
- 13:38 的 Release 构建（piliplus.exe 和 win32_window.obj 均为 13:38）已包含该改动，14:05 的 dist 便携版也是。
- 已排查 fork 版 window_manager 插件源码：不修改 WS_CAPTION，不会运行时把标题栏加回来。
- 最可能的真实原因：**托盘常驻旧实例**。应用设置了 `setPreventClose(true)`（关闭按钮只隐藏到托盘），且 main.cpp 有单实例检测——托盘里有旧构建实例时，启动新 exe 只会把旧窗口置前，看到的仍是带原生标题栏的旧窗口。

## 实施步骤
1. **结束所有残留实例**：`taskkill /f /im piliplus.exe`（含托盘常驻的旧进程，确保单实例检测不会拦截新版本）。
2. **重新构建**：运行 `build_windows.bat`（release 构建 + 便携版 + 安装包，产物到 dist/），保证产物一定包含工作区中的 `~WS_CAPTION` 改动。
3. **启动新构建**：运行新的 piliplus.exe。
4. **运行时验证**（PowerShell 调 Win32 API）：
   - 枚举窗口找到 piliplus 主窗口，读取 `GWL_STYLE`，断言 `WS_CAPTION`(0x00C00000) 未设置、`WS_THICKFRAME`(0x00040000) 保留；
   - 截取窗口区域截图，视觉确认只有 WinUI3 标题栏、无原生标题栏。
5. **兜底方案**（仅当验证发现样式异常时才实施，理论不会发生）：若确认 WS_CAPTION 已移除但仍有残留视觉问题，升级为 WS_POPUP + `DwmExtendFrameIntoClientArea` + `DWMWA_WINDOW_CORNER_PREFERENCE` + `WM_NCHITTEST` 手写命中测试的彻底无边框方案。

## 说明
- 源码无需再改（改动已存在且正确），本次主要工作为重建 + 干净重启 + 验证；改动仍是未提交状态，如需要可以顺带提交。
- 已知的微小交互细节（非缺陷）：Win11 下窗口最顶部约 7px 属于不可见的非客户区缩放边框，鼠标拖拽/双击在标题栏最顶部几像素内不会触发 Flutter 的拖拽事件，属无边框窗口的普遍行为。