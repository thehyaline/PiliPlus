## 修改计划：我的页「观看记录」「我的收藏」板块

### 文件 1：`lib/pages/mine/view.dart`

**观看记录标题栏 `_buildHistory`（约 471-518 行）**
1. 删除标题右侧的刷新按钮（`trailing: IconButton(...)` 整段）。
2. 把 `>` 箭头从标题文字中移出（删除 WidgetSpan），改为放在 `trailing` 位置（即原刷新按钮的位置），尺寸由 18 缩小到 16，并加 `right: 8` 的 padding 使其与原刷新图标位置一致：
   ```dart
   trailing: Padding(
     padding: const EdgeInsets.only(right: 8),
     child: Icon(Icons.arrow_forward_ios, size: 16, color: secondary),
   ),
   ```
3. 标题改为常规字重：删除 `fontWeight: .bold`（跟随主题默认字重，与应用内其他板块标题一致）；标题文本 `'观看记录  '` 去掉多余空格改为 `'观看记录'`。

**我的收藏标题栏 `_buildFav`（约 570-620 行）**
4. 与观看记录相同的三处改动：删除刷新按钮、箭头移至 trailing（16 号）、标题删除 `fontWeight: .bold` 并清理空格（`'我的收藏  '` → `'我的收藏'`；数量文本 `${count}  ` → `${count} `，数量文字样式不变）。
5. 删除板块顶部的 `Divider`（约 573-576 行）——即两个板块中间的分割线；分割线自带的 20 高度间距也随之消失，两个板块间距自然缩小（剩余间距仅来自标题行自身的 padding）。

### 文件 2：`lib/pages/mine/widgets/history_item.dart`（观看记录封面）

6. 删除封面外层 `DecoratedBox` 的 `boxShadow`（即"背景阴影"）。该 DecoratedBox 除了阴影外无其他可见效果（圆角由 `NetworkImgLayer` 自身提供），直接移除这层 DecoratedBox 包裹，保留内部 Stack。封面保持 180×110 尺寸，本就撑满所在卡片宽度，去阴影后视觉上干净地填满卡片。

### 说明
- 「我的收藏」的封面（`FavFolderItem`）不在本次需求内，保持原样。
- 收藏夹数量文字、封面角标（进度/已看完等）均不变。
- 改动后运行 `flutter analyze` 验证无编译错误。