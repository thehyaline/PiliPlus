## 目标

直播间播放器在**非全屏**（嵌入直播间页面）时，去掉上下控制按钮栏的黑色渐变背景；窗口全屏、全屏时保留渐变。**只影响直播间**，视频播放器保持原样。

## 背景

渐变背景来自 `lib/plugin/pl_player/widgets/app_bar_ani.dart` 的 `AppBarAni` 组件（顶部 `LinearGradient`：transparent → `Color(0xBF000000)`，底部对称），在 `build` 中**无条件**通过 `DecoratedBox` 应用（app_bar_ani.dart:54-57）。该组件已被传入 `isFullScreen` 参数，且播放器控制器有现成的 `isLive` 字段（controller.dart:123），可用来区分直播间与视频播放器。

## 改动

### 1. `lib/plugin/pl_player/widgets/app_bar_ani.dart`
- 构造函数新增 `required this.isLive` 字段。
- `build` 中渐变仅在 `isFullScreen || !isLive` 时应用，即非全屏的直播间播放器不画渐变：
  ```dart
  decoration: BoxDecoration(
    gradient: (isFullScreen || !isLive) ? (isTop ? _topDecoration : _bottomDecoration) : null,
  ),
  ```

### 2. `lib/plugin/pl_player/view/view.dart`（两处调用点，第 1622 行、1635 行）
- 两处 `AppBarAni(...)` 均传入 `isLive: plPlayerController.isLive`。

## 效果

- 直播间嵌入页面（非全屏）：上下控制栏无渐变背景。
- 直播间窗口全屏 / 全屏（`isFullScreen == true`）：渐变保留。
- 直播间桌面画中画（PiP，属于非全屏）：按同一规则渐变也会去掉（如需保留可后续单独调整）。
- 视频播放器（`isLive == false`）：行为完全不变。

## 验证

改动后运行 `flutter analyze` 确认无静态错误；该改动为纯 UI 条件渲染，逻辑简单，无需改测试。