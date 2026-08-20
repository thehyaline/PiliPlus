## 问题根因

`flutter build windows` 失败的直接错误是：

```
connectivity_plus_plugin.cpp: warning C4819: 该文件包含不能在当前代码页(936)中表示的字符
connectivity_plus_plugin.cpp: error C2220: 警告被视为错误
```

根因链：
1. Flutter 3.47 Windows 模板的 `windows/CMakeLists.txt` 中 `apply_standard_settings()` 带 `/W4 /WX`（警告即错误）——见 `windows/CMakeLists.txt:42`；
2. 系统 ANSI 代码页为 936（GBK），MSVC 默认按系统代码页解读源码文件；
3. `connectivity_plus` 的 pigeon 生成源码 `connectivity_plus_plugin.cpp` 注释中含 UTF-8 的 `—`（em dash，第 180、242 行），GBK 无法表示 → C4819 → 被 `/WX` 升级为 C2220 致命错误。

另：`flutter_inappwebview_windows` 的 `base64.cpp` 也触发同款 C4819（`é`、`…` 等），但该插件未用 `/WX`，仅为警告不致命。

`build_windows.bat` 中的 `chcp 65001` 无效——MSVC 的源码编码按系统 ACP（GetACP）判定，与控制台代码页无关。

## 修复方案

修改 `E:\Repo\PiliPlus\windows\CMakeLists.txt`：在 `cmake_policy(VERSION 3.14...3.25)`（第 11 行）之后、`add_subdirectory`（第 50 行）之前加入：

```cmake
# 系统代码页 (如中文 Windows 的 936/GBK) 无法解码 UTF-8 的插件源码，
# 触发 C4819 警告并在 /WX 下升级为 C2220 错误。强制所有源文件按 UTF-8 解读。
if(MSVC)
  add_compile_options(/utf-8)
endif()
```

要点：
- `add_compile_options` 是目录级属性，会被之后 `add_subdirectory(flutter)`、`add_subdirectory(runner)` 及 `include(flutter/generated_plugins.cmake)` 加入的所有插件目标继承，一处修复覆盖全部目标；
- 不动 `apply_standard_settings()` 本身（该函数被所有插件共用，模板注释也明确建议不要改）；
- 不改 pub 缓存中的插件源码（ephemeral，每次 pub get 重新生成，改了不持久）；
- 顺带消除 `base64.cpp` 等所有 C4819 警告。

## 不做的事

- 日志中的 `CMP0175 ... add_custom_command(TARGET): DEPENDS` 只是 CMake 开发者警告，非致命、不影响构建，不需要处理；
- 不改系统"使用 Unicode UTF-8 提供全球语言支持"选项（属系统级修改，超出仓库范围）。

## 验证步骤

1. 运行 `powershell -NoProfile -ExecutionPolicy Bypass -File lib\scripts\patch.ps1 windows`（与 build_windows.bat 第 2 步一致，确保 SDK 补丁已应用）；
2. 运行 `flutter build windows --release --dart-define-from-file=pili_release.json --no-pub`（即 build_windows.bat 第 3 步的命令）；
3. 确认构建成功、无 C4819/C2220 报错（不跑完整 build_windows.bat，因为它会运行 build.ps1 改写 pubspec.yaml 版本号并生成 dist 产物）。