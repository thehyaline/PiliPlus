## 目标

在"我的"页面（`lib/pages/mine/view.dart`）的"我的收藏"板块上方新增"观看记录"板块：标题行（观看记录 + ">" + 右侧刷新按钮，点击整行进入 `/history`）+ 横向滚动卡片列表（卡片尺寸与收藏夹一致，封面 + 主标题 + "UP主/主播 · 观看时间"副标题）。数据来源与观看记录页"全部"tab 相同（`UserHttp.historyList(type: 'all')`，游标分页），左滑接近末尾自动加载下一页；长按卡片弹出与观看记录页三点菜单完全相同的菜单（访问UP主 / 稍后再看 / 删除记录），删除成功后从横向列表移除（右侧自然左移）。

## 改动文件

### 1. 新增 `lib/pages/history/widgets/actions.dart`（从观看记录页提取共享逻辑，保证菜单/跳转行为完全一致）

- `Future<void> openHistoryItem(HistoryItemModel item)`：把 `history/widgets/item.dart` 的 onTap 跳转逻辑原样搬出（article/live/pgc/cheese/archive 分发，`PageUtils.toVideoPage` / `toLiveRoom` / `viewPgc` / `viewPgcFromUri`，cid 缺失时 `SearchHttp.ab2cWithDimension` 补查）。
- `List<PopupMenuEntry<void>> buildHistoryItemMenu(HistoryItemModel item, VoidCallback onDelete)`：三项菜单原样搬出 —— "访问：{authorName}"（有 authorMid 时）、"稍后再看"（排除 pgc/番剧/动画/直播/专栏）、"删除记录"。

### 2. 修改 `lib/pages/history/widgets/item.dart`

改用上述共享函数（onTap → `openHistoryItem(item)`，itemBuilder → `buildHistoryItemMenu(item, onDelete)`），行为完全不变，只是去重。

### 3. 新增 `lib/pages/mine/widgets/history_item.dart` — `MineHistoryItem` 卡片

- 尺寸/样式与收藏夹卡片一致：封面 `NetworkImgLayer` 180×110、圆角 12、同款阴影 DecoratedBox；主标题单行 fade；副标题 `labelSmall` + outline 色，格式 `${authorName} · ${DateFormatUtils.chatFormat(viewAt, isHistory: true)}`（authorName 为空时只显示时间）。
- `onTap` → `openHistoryItem(item)`（直播未开播 toast 等逻辑随之复用）。
- `onLongPress`（桌面端同时 `onSecondaryTapDown`）→ `Feedback.forLongPress(context)` + `showMenu(position: PageUtils.menuPosition(按压位置), items: buildHistoryItemMenu(item, onDelete))`。

### 4. 修改 `lib/pages/mine/controller.dart` — MineController 增加历史状态机

- 新增字段：`Rx<LoadingState<List<HistoryItemModel>?>> historyState = LoadingState.loading().obs`、游标 `historyMax`/`historyViewAt`、`historyIsEnd`/`historyIsLoading`。
- `historyQueryData([bool isRefresh = true])`：仿 `CommonListController.queryData` —— 请求 `UserHttp.historyList(type: 'all', max: historyMax, viewAt: historyViewAt, account: Accounts.history)`；成功时用末条的 `history.oid`/`viewAt` 更新游标，空列表置 `isEnd`；刷新替换列表、加载更多追加并 `historyState.refresh()`；刷新失败置 Error、加载更多失败 toast。未登录直接返回。
- `historyDelete(HistoryItemModel item)`：仿观看记录页 `_onDelete` —— `SmartDialog.showLoading` → `UserHttp.delHistory('${item.history.business}_${item.kid}')` → 成功则 `list.remove(item)` + `historyState.refresh()`（列表删空且未到底时自动继续加载下一页补位），toast"已删除"；失败 `res.toast()`。
- 挂接：`onInit`（有缓存时）和 `onRefresh`（登录后）里调用 `historyQueryData()`，使下拉刷新联动刷新历史板块。

### 5. 修改 `lib/pages/mine/view.dart`

- ListView children 中 `_buildActions` 之后、收藏板块 Obx 之前插入：
  `Obx(() => controller.historyState.value is Loading ? const SizedBox.shrink() : _buildHistory(theme, secondary))`（未登录时 state 保持 Loading → 整块隐藏，与收藏一致）。
- `_buildHistory`：仿 `_buildFav` —— Divider + `ListTile(dense)`（title 为 Text.rich："观看记录  " + `Icons.arrow_forward_ios` 小图标，无数字；`onTap: Get.toNamed('/history')?.whenComplete(_autoRefresh)`；trailing 为刷新 IconButton → `controller.historyQueryData()`）+ `_buildHistoryBody`。
- `_buildHistoryBody`：switch loadingState —— `Success` 且列表为空 → shrink（与收藏一致）；否则外层 `NotificationListener<ScrollEndNotification>`（`metrics.pixels >= metrics.maxScrollExtent - 300` 时 `controller.historyQueryData(false)`，与 dynamics 页同一阈值模式）+ `SizedBox(height: 170)` + 横向 `ListView.separated`（padding left/right 20、top 10，间距 14，item 为 `MineHistoryItem`）；`Error` 显示错误文本。

## 行为要点

- 菜单、跳转、删除接口与观看记录页完全一致（共享代码）；删除参数 `business_kid`、账号 `Accounts.history`（自动兼容无痕模式）。
- 左滑自动翻页受 `isEnd`/`isLoading` 保护，不会重复请求。
- 卡片为纯封面样式（不含进度条/角标），与收藏夹卡片观感一致。