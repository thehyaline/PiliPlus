## 问题根因

**不是全屏状态 bug，而是视频页布局分支选择缺陷。**

进入视频播放页时，播放器"占满窗口、其他 UI 消失"，但窗口全屏按钮仍然可见 —— 这证明 `isFullScreen == false`（按钮只在 `!isFullScreen` 时显示，`lib/plugin/pl_player/view/view.dart:942-945`），排除了全屏状态机异常。

真正的问题在布局分支选择（`lib/pages/video/view.dart:1256-1268`）：

```dart
if (isPipMode) child = plPlayer(...);
else if (!videoDetailController.horizontalScreen) child = childWhenDisabled;  // ← 问题分支
else if (maxWidth / maxHeight >= kScreenRatio) child = childWhenDisabledLandscape;
else if (maxWidth / Style.aspectRatio16x9 < 0.4 * maxHeight) child = childWhenDisabled;
else child = childWhenDisabledAlmostSquare;
```

- `Pref.horizontalScreen`（设置项"横屏适配"，`storage_pref.dart:655-663`）为 **false** 时，视频页无条件走 `childWhenDisabled` —— 这是为手机竖屏设计的吸顶播放器布局。
- 该布局的播放器高度（`view.dart:557-558`）：`isFullScreen || !isPortrait ? maxHeight : ...`，即**横向窗口（宽>高，`!isPortrait`）下播放器高度恒等于整窗高度**、宽度等于整窗宽；简介/评论 Tab 全部被挤到首屏折叠线以下，返回按钮初始透明度为 0 不可见 → 视觉上完全像"窗口全屏"。
- 直播页没有该布局分支（固定"播放器在上、内容在下"），所以直播页正常。

桌面端 `horizontalScreen == false` 的成因：用户手动关闭过"横屏适配"开关，或该键首次落库时窗口最短边 < 600（`DeviceUtils.isTablet` 判定，`device_utils.dart:8-10`），之后窗口变为横向。这与最近的窗口改动（b107410a5 调整了启动窗口尺寸/位置计算）可能只是时间上的巧合——核心缺陷是布局分支在"横向窗口 + 关闭横屏适配"时把播放器钉满整窗。

## 修复方案（单文件最小改动）

修改 `lib/pages/video/view.dart:1260`，`!horizontalScreen` 分支只对竖屏窗口生效，横向窗口回退到正常比例分支：

```dart
} else if (!videoDetailController.horizontalScreen && isPortrait) {
  child = childWhenDisabled;
}
```

效果：
- 竖窗 + 关闭横屏适配 → 保持原竖屏布局（行为不变）
- **横窗 + 关闭横屏适配 → 进入 Landscape 分栏（宽窗，左侧播放器+右侧简介/评论）或 AlmostSquare（上方播放器+下方内容），恢复正常**（本 bug 修复目标）
- 横窗 + 开启横屏适配 → 不变
- 全屏（`isFullScreen`）行为完全不受影响，各布局原有的全屏整窗逻辑保留

影响面核查（均已确认无副作用）：
- `PlPlayerController` 中 `horizontalScreen` 相关的方向切换逻辑（`pl_player/controller.dart:500-523`）只在移动端方向监听中触发，桌面端不生效
- `main.dart:123` 的 `Pref.horizontalScreen` 只在移动端启动分支使用
- `header_control.dart:123` 只影响控制条时间显示样式，非布局问题

## 验证

1. 运行 `flutter analyze` 确认无编译错误
2. 构建运行：横向窗口（如 1280x720）下分别测试"横屏适配"开关开/关两种状态进入视频页，确认均显示正常分栏布局；再测试竖窗（窄窗口）下关闭开关仍为竖屏布局；测试全屏/窗口全屏切换仍正常