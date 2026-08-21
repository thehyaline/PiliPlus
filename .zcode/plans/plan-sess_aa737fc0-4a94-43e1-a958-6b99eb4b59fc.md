## 修复：Windows 触摸屏在直播间无法唤起播放控制栏

### 根因
`lib/plugin/pl_player/view/view.dart` 的 `_onPointerDown`（第 1286-1288 行）桌面端分支对直播（isLive=true）只注册双击识别器、不注册单击识别器。而触摸单击切换控制栏的唯一入口是 `_onTapUp`（`default` 分支 → `controls = !showControls`），导致桌面+直播+触摸时控制栏永远唤不出。鼠标能正常是因为有独立的 `MouseRegion.onEnter/onHover` 唤出路径，触摸不产生 hover 事件。此回归由 2026-05-09 的 commit `fab34df973`（手势重构）引入。

### 改动
单文件单分支修改：`lib/plugin/pl_player/view/view.dart` `_onPointerDown` 的桌面直播分支，对非鼠标指针（touch/stylus）额外注册 `_tapGestureRecognizer`：

```dart
    } else if (controlsUnlock) {
      if (plPlayerController.isLive) {
        if (event.kind != ui.PointerDeviceKind.mouse) {
          _tapGestureRecognizer.addPointer(event);
        }
        _doubleTapGestureRecognizer.addPointer(event);
      } else {
        _tapGestureRecognizer.addPointer(event);
        _doubleTapGestureRecognizer.addPointer(event);
        longPressRecognizer.addPointer(event);
      }
      _scaleGestureRecognizer.addPointer(event);
    }
```

（`ui.PointerDeviceKind` 在本文件已有使用，无需新增 import）

### 行为影响
- 桌面+直播+触摸/触控笔单击：切换控制栏显隐（与移动端直播一致）——修复目标
- 桌面+直播+鼠标：行为完全不变（单击仍无动作靠 hover，双击仍切换全屏），因 `_onTapUp` 对鼠标走播放/暂停分支，故刻意不注册鼠标指针
- 桌面+直播+触摸双击：竞技场裁决后 doubleTap 获胜，tap 被 reject，双击行为不变
- 控制栏锁定（controlsLock）时仍不注册任何手势，锁定语义不变

### 验证
1. `flutter analyze` 确认无编译错误
2. 需要用户在 Windows 触摸屏设备上验证：直播间触摸单击可唤起/隐藏控制栏；鼠标操作无回归；视频页无回归