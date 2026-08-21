## 目标

去掉视频切换相关的所有 toast，共 6 处：

### 1. 分集面板切换 toast
**文件**: `lib/pages/episode_panel/view.dart:443`

删除 `SmartDialog.showToast('切换到：$title');`。该面板被分P列表、合集（season）集数、PGC 剧集共用，删除后点击任意分集/剧集切换不再弹 toast。保留同处 `'需要大会员'` 提示及 `onChangeEpisode` 逻辑。

### 2. 播放历史气泡跳转分P toast
**文件**: `lib/pages/video/controller.dart:585`

删除 `SmartDialog.showToast('已跳至第${item + 1}P');`，保留 catch 分支的 `'跳转失败'` 错误提示。

### 3-4. 键盘快捷键边界提示
**文件**: `lib/pages/video/widgets/player_focus.dart:272-286`

`bracketLeft` / `bracketRight` 两个 case 中，删除 toast 后把空条件改为直接调用：
```dart
// 修改前
if (!introController.prevPlay()) {
  SmartDialog.showToast('已经是第一集了');
}
// 修改后
introController.prevPlay();
```
`nextPlay()` 同理。

### 5-6. 上一集/下一集按钮边界提示
**文件**: `lib/plugin/pl_player/view/view.dart:424-428` 和 `441-445`

onTap 中删除 toast，简化为 `onTap: () => introController.prevPlay(),` / `onTap: () => introController.nextPlay(),`。

### 保留项
- `'需要大会员'`（会员限制）、`'跳转失败'`（错误）、`'暂无相关视频，停止连播'` 等非切换类 toast 全部保留。

### 说明
删除后 4 个文件仍有其它 `SmartDialog` 调用（episode_panel 440/594 行、controller 多处、player_focus 159/215 行、view.dart 843/2222 行），无需处理 import。