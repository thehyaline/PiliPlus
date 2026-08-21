## 根因分析（已通过源码确认）

### 问题 2：上下卡片之间的"不明色块"
动态卡片底部有一个 8px 高的底部分隔带（`DecoratedBox` 的 `BorderSide(width: 8, color: dividerColor@5%)`，`dynamic_panel.dart`），它悬浮在卡片之间的空隙里：浅色主题下颜色接近卡片底色，像一块脱离卡片的碎块；深色主题下是比页面背景亮的杂色条。这就是用户看到的"色块"。修复：删除分隔带，垂直间距改由卡片底部 padding 承担。

### 问题 1：各页瀑布流卡片宽度不一致
瀑布流列宽 = 可用宽度按列数平分，列数 = ceil(可用宽度 / (maxCrossAxisExtent + 列距))。各页面对外参数不一致，导致同一窗口下卡片宽度不同（已验证同一视图内宽度必一致——`asBoxConstraints(crossAxisExtent:)` 是紧约束）：
- `lib/pages/my_reply/view.dart`：`SliverWaterfallFlow` 没包 `buildPage()` → 缺 16px 左右边距，卡片比动态页宽 16px；
- `lib/pages/search_panel/all/view.dart`：`crossAxisSpacing: Style.safeSpace`(12)，动态页是 4 → 列数边界不同，卡片宽度显著不同；
- `lib/pages/member_opus/view.dart`：`maxCrossAxisExtent: Grid.smallCardWidth`(240，动态页是 480) + 间距 12 → 列数多、卡片窄得多。

## 改动

### 1. 移除色块、统一垂直间距
- `lib/pages/dynamics/widgets/dynamic_panel.dart`：删除 `DecoratedBox` 底部分隔带，`Padding(bottom: 8)` 改为 `Padding(bottom: Style.waterfallMargin)`(16)。卡片间垂直间距仍为 16px（= 左右边距），列表模式节奏不变（原 8+8=16）。Card 圆角/背景保留。
- `lib/common/skeleton/dynamic_card.dart`：同步删除分隔带，容器 padding 增加 `bottom: 12`（12 + 骨架网格 mainAxisSpacing 4 = 16，与真实卡片间距一致）。

### 2. 统一各页面瀑布流参数（卡片宽度一致）
- `lib/pages/my_reply/view.dart`：`SliverWaterfallFlow` 包一层 `buildPage(...)`，补上 16px 左右边距。
- `lib/pages/search_panel/all/view.dart`：`crossAxisSpacing` 12 → 4。
- `lib/pages/member_opus/view.dart`：`maxCrossAxisExtent` 240 → `Grid.smallCardWidth * 2`(480)，`crossAxisSpacing`/`mainAxisSpacing` 12 → 4（与 `dynGridDelegate` 一致）。
- `lib/common/style.dart`：更新 `waterfallMargin` 注释（不再有"8+8"来源）。

其余页面（动态主页、话题页、用户空间动态、搜索页）已用 `dynGridDelegate` + `buildPage`，参数一致，无需改动。

## 验证
- `flutter analyze` 无错误。
- 构建并运行 Windows 版本，截图确认：卡片间无杂色带、各瀑布流页面卡片宽度一致、圆角与边距正常。