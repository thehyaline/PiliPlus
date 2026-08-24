## 背景（已核实）

- `LiveTag`（lib/common/widgets/live_tag.dart，新文件）：胶囊底色/文字/动画色取 `colorScheme.primary`/`onPrimary`；图标尺寸 = fontSize+3、间距 3、padding 6/2 全是固定常量；无任何宽度约束/缩放手段。
- 问题根因：38px 小头像处 `Positioned(left:0, right:0)` 把标签 maxWidth 约束成 38px，而 fontSize 10 的标签内容固有宽度约 58px → 内容溢出胶囊背景。个人页 80px 头像（默认字号 13，内容约 70px）能容纳，所以"展示良好"。
- 主题色机制：默认 variant 是 material3Legacy（浅色 primary=tone40 永远偏深、深色=tone80 偏浅，onPrimary 分别配白/深黑）；用户设置的主题色是 `colorThemeTypes[Pref.customColor].color` 种子色（如灰色 #9E9E9E），与生成色 `colorScheme.primary`（灰主题实际渲染约 #676767）不一致。
- 现状描边与标签底色已经都取自 `colorScheme.primary`（各处一致），但按需求应改用"程序设置的当前主题色"本身，并加浅色判定。
- Android 动态取色启用时（`_light/_dark 非空 && Pref.dynamicColor`），主题色应取 `colorScheme.primary`；否则取种子色。

## 改动方案

### 1. lib/common/widgets/live_tag.dart（核心改动）
- 新增无参帮助函数：
  ```dart
  /// 当前程序设置的当前主题色；Android 动态取色生效时取主题方案主色
  Color currentThemeColor() {
    if (ThemeUtils.isDynamicColor) return ThemeUtils.theme.colorScheme.primary;
    return colorThemeTypes[Pref.customColor].color;
  }
  ```
- `LiveTag.build` 重写：
  - 背景 = `currentThemeColor()`（不再是 colorScheme.primary）。
  - 前景（文字 + 信号动画）判定：`useDark = lum > 0.4 || (近无彩色 && lum > 0.25)`，其中 lum = 背景色 `computeLuminance()`，近无彩色 = r/g/b 最大最小差 < 0.07。`useDark` 时前景 = `Colors.black87`，否则 = `Colors.white`（浅色模式 onPrimary 本就是白；深色模式胶囊统一用种子色后白色更合适）。
    - 灰色 #9E9E9E（lum≈0.34、无彩色）→ 深色文字 ✓；白色/浅黄/橙等（lum>0.4）→ 深色 ✓；默认绿/粉红等 → 白字，保持现有徽标风格 ✓。
  - 宽度适配：把整个胶囊（Container，padding 6/2 保留）包进 `FittedBox(fit: BoxFit.scaleDown)`——有宽度约束（小头像 38px）时整体等比缩小，内容物永远在胶囊内、图标+文字保持整体居中、有效字号随头像变小（38px 头像上约 6.5px，实现"最小字号进一步缩小"）；无约束（80px 个人页）时保持原尺寸不变。
  - 同步更新文件顶部注释（原注释描述的 onPrimary 行为已不准确）。
- `liveAvatarBorder` 函数签名不变，颜色由调用方传入。

### 2. 描边颜色改为同一主题色（3 处）
- lib/common/widgets/pendant_avatar.dart:86：`liveAvatarBorder(color: currentThemeColor(), ...)`（live_tag.dart 已 import）。
- lib/pages/dynamics/widgets/up_panel.dart:182：同改。
- lib/pages/dynamics/widgets/live_panel_section.dart:119：同改（该函数无 context 参数，`currentThemeColor()` 无参设计正好适用）。

### 3. 动态取色状态暴露
- lib/utils/theme_utils.dart：新增 `static bool isDynamicColor = false;`
- lib/main.dart:256 的 `getAllTheme()` 中：`final dynamicColor = ...` 后加 `ThemeUtils.isDynamicColor = dynamicColor;`

## 不做的事
- 不改 up_panel/live_panel_section 的 `fontSize: 10` 与 `Positioned(left:0,right:0)`——FittedBox 会自动等比缩放，改字号对最终渲染几乎无影响。
- 不改 PendantAvatar 默认字号 13（个人页 80px 头像不受约束缩放，保持现状"展示良好"）。
- 不构建、不运行验证（由你自行验证）。

## 验证建议（你来做）
1. 动态页 UP 列表 / 正在直播板块：38px 头像上标签宽度不超过头像、图标+文字完整在胶囊内且整体居中、字号明显小于之前。
2. 主题切到灰色：胶囊和头像描边都显示 #9E9E9E 灰色，文字与信号动画为深色；切白色/黄色等浅色同样深色文字；默认绿/粉红等仍为白字。
3. 个人页 80px 头像标签外观应与改动前基本一致（字号 13、胶囊约 70px）。