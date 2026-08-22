## 目标

当直播间为左右排布（视频播放器在左、评论区在右，即窗口宽 ≥600 且宽 > 高、非全屏）时，把发送弹幕弹窗移到评论区所在列的底部（右对齐），宽度与半透明的发送弹幕输入栏完全一致；其他场景（竖屏、全屏）保持现状（底部居中、最大宽度 640）。

## 现状

- 弹窗 `LiveSendDmPanel`（`lib/pages/live_room/send_danmaku/view.dart:54-62`）通过 `PublishRoute` 全屏弹出，内容为 `ViewSafeArea > Align(bottomCenter) > Container(constraints: maxWidth 640)`。
- 左右排布时（`view.dart:698-702` `_buildBodyH`），右侧栏宽度为：
  `rightWidth = min(400.0, maxWidth - clampDouble(maxHeight / maxWidth * 1.08, 0.56, 0.7) * maxWidth - padding.horizontal)`
  其中 `maxHeight = size.height - captionBarHeight`。
- 弹窗是覆盖整个 Navigator 的全屏 route，可自行通过 `MediaQuery` 判断布局模式，无需改 controller 的 `onSendDanmaku` 签名（该入口被输入栏、表情按钮、@回复、快捷键、播放器头部控制等多处复用，统一在面板内处理最稳妥）。

## 改动（3 个文件）

### 1. `lib/pages/live_room/controller.dart`
- 新增 imports：`dart:ui`（`clampDouble`）、`package:PiliPlus/plugin/pl_player/utils/fullscreen.dart`（`captionBarHeight`）。
- 在 `LiveRoomController` 中新增静态方法，把 `view.dart` 的右侧栏宽度公式提取为共享实现，防止两处漂移：
  ```dart
  /// 左右排布时右侧栏宽度（评论区/发送弹幕栏），与 view._buildBodyH 保持同步
  static double rightPanelWidth(double maxWidth, double maxHeight, EdgeInsets padding) {
    final videoWidth =
        clampDouble(maxHeight / maxWidth * 1.08, 0.56, 0.7) * maxWidth;
    return math.min(400.0, maxWidth - videoWidth - padding.horizontal);
  }
  ```

### 2. `lib/pages/live_room/view.dart`
- `_buildBodyH`（第 698-702 行）改用 `LiveRoomController.rightPanelWidth(maxWidth, maxHeight, padding)` 计算 `rightWidth`，再反推 `videoWidth`（结果与现在完全等价）。

### 3. `lib/pages/live_room/send_danmaku/view.dart`
- 新增 import：`package:PiliPlus/utils/extension/size_ext.dart`（`SizeExt.isPortrait`）。
- `_ReplyPageState.build`（第 52-73 行）中计算：
  ```dart
  final size = MediaQuery.sizeOf(context);
  final plPlayerController = liveRoomController.plPlayerController;
  final isFullScreen =
      plPlayerController.isFullScreen.value || plPlayerController.isDesktopPip;
  // 左右排布：宽屏且非全屏（此时右侧栏可见）
  final isLandscapeLayout = !size.isPortrait && !isFullScreen;
  final panelWidth = LiveRoomController.rightPanelWidth(
    size.width, size.height, MediaQuery.viewPaddingOf(context));
  ```
- 对齐与宽度改为条件分支：
  - 左右排布：`Align(bottomRight)`，`Container(width: panelWidth)`（不设 maxWidth 约束）。
  - 其他场景：`Align(bottomCenter)`，`Container(constraints: maxWidth 640)`（保持现状）。
- 右侧栏在 `view.dart` 的 Row 中带 `padding.right` 边距且贴屏幕底部，`ViewSafeArea` 的 right padding 同为 `viewPadding.right`，因此右对齐后弹窗与输入栏在水平、垂直方向均自然对齐。

## 不做的事
- 不改 `PublishRoute`、不动 `onSendDanmaku` 签名、不改竖屏/全屏行为、不改视频弹幕面板。

## 验证
- 运行 `flutter analyze` 确认无静态错误。
- 代码走查确认宽度公式提取前后等价、对齐条件与 `_buildBodyH` 的右侧栏可见条件一致。