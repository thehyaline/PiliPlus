## 目标

每次进入"我的"页时自动**全量**刷新（用户信息 + 收藏 + 观看记录，即 `controller.onRefresh(isManual: false)`），覆盖：从其他 tab 切回、从任意 push 页面（视频页、观看记录页、收藏页、收藏夹详情等）返回。新进入（首次创建）已有 `onInit` 加载，不需额外处理。

## 改动（3 个文件）

### 1. `lib/pages/mine/controller.dart` — tab 切回时全量刷新

`MineController.onInit` 中订阅全局 tab 状态（GetX `ever`，Worker 随 controller `onClose` 自动清理，无泄漏）：

```dart
@override
void onInit() {
  super.onInit();
  final mainController = Get.find<MainController>();
  ever(mainController.selectedIndex, (index) {
    if (mainController.navigationBars[index] == NavigationBarType.mine) {
      onRefresh(isManual: false);
    }
  });
  // 原有首次加载逻辑不变
}
```

- `selectedIndex` 是 `RxInt`（`lib/pages/main/controller.dart:39`），切 tab 时变化；`ever` 只在变化时触发，首次创建不会重复刷新。
- `onRefresh(isManual: false)` 全量刷新（queryUserInfo + historyQueryData + 收藏），不跳回顶部，不影响切回时的滚动位置。
- 不选在 `MainController.setIndex` 加分支：`MineController` 是懒创建的，`setIndex` 里 `Get.find` 会抛错或被迫提前创建 controller。
- 新增 import：`pages/main/controller.dart`、`models/common/nav_bar_config.dart`。

### 2. `lib/pages/mine/view.dart` — push 返回时全量刷新

`_MediaPageState` 混入 `RouteAware, RouteAwareMixin`（`route_aware_mixin.dart` 自动订阅/退订全局 `routeObserver`），实现：

```dart
@override
void didPopNext() {
  if (widget.showBackBtn ||
      _mainController.navigationBars[_mainController.selectedIndex.value] ==
          NavigationBarType.mine) {
    controller.onRefresh(isManual: false);
  }
  super.didPopNext();
}
```

- `showBackBtn == true`：push 模式（`toMinePage` 中 `Get.to(MinePage(showBackBtn: true))`），返回即本页，直接刷新。
- tab 模式：仅当前可见 tab 是"我的"时刷新，避免在别的 tab 从视频页返回时误刷（切回 tab 时由 `ever` 补刷）。
- 新增 import：`common/widgets/route_aware_mixin.dart`（`NavigationBarType` 已导入）。

### 3. 删除冗余的 `_autoRefresh`（统一由 `didPopNext` 覆盖）

`_autoRefresh`（view.dart:461，pop 后延迟 150ms 的 `onRefresh(isManual: false)`）与 `didPopNext` 功能重复，保留会造成从 /history、/fav 返回时双重刷新（userInfo 请求两次）：

- `lib/pages/mine/view.dart`：删除 `_autoRefresh` 定义及 3 处 `Get.toNamed(...)?.whenComplete(_autoRefresh)`（/history 标题行、/fav 标题行、查看更多按钮），`FavFolderItem` 不再传 `onPop`。
- `lib/pages/mine/widgets/item.dart`：`FavFolderItem` 删除 `onPop` 字段/构造参数及 `?.whenComplete(onPop)` 调用（该组件仅 view.dart 一处使用，返回 /favDetail 的刷新由 `didPopNext` 覆盖）。

## 不改动

`MainController`、观看记录页、已提交的 `actions.dart` / `history_item.dart`。未登录时 `onRefresh` 内部直接返回，不会发请求。