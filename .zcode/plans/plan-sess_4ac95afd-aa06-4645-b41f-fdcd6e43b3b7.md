## 目标
给悬浮式导航栏（FloatingNavigationBar）背景增加高斯模糊（毛玻璃）效果。仅修改一个文件，改动后由你自行构建验证。

## 背景调研结论
- 组件位置：`lib/common/widgets/floating_navigation_bar.dart`
- 背景绘制在 `build()` 第 87-102 行：`DecoratedBox` + `ShapeDecoration`（胶囊形 `RoundedSuperellipseBorder`，圆角 32）
- 默认背景色 `_colors.surfaceContainer`（不透明），定义在 `_NavigationBarDefaultsM3.backgroundColor`（第 728 行）
- 调用处 `lib/pages/main/view.dart:290` 未传 `backgroundColor`，默认值生效，无需改调用处
- `lib/common/widgets/main_layout.dart` 中 bottomNav 在 body **之后**绘制（覆盖在正文之上），因此 `BackdropFilter` 能正确采样到导航栏下方的页面内容，无需调整布局
- 项目中暂无任何 BackdropFilter 用法，此改动是首次引入

## 实现步骤（全部在 floating_navigation_bar.dart 内）

1. **导入**：添加 `import 'dart:ui' show ImageFilter;`

2. **新增顶层常量**：
   - `_kBlurSigma = 15.0`（模糊强度）
   - `_kBackgroundOpacity = 0.72`（背景色透明度）

3. **build() 中包裹模糊层**：把 `SizedBox` 的 child 从 `DecoratedBox` 改为：
   ```
   ClipPath(
     clipper: _ShapeBorderClipper(_kNavigationShape),
     child: BackdropFilter(
       filter: ImageFilter.blur(sigmaX: _kBlurSigma, sigmaY: _kBlurSigma),
       child: DecoratedBox(...)  // 原样保留
     ),
   )
   ```
   用 `ClipPath` 按现有胶囊形状裁剪模糊区域，防止模糊效果溢出到导航栏四角之外的矩形区域（那里会直接透出正文内容）。

4. **新增 `_ShapeBorderClipper` 类**（文件底部，与 `_kNavigationShape` 配套）：
   ```dart
   class _ShapeBorderClipper extends CustomClipper<Path> {
     const _ShapeBorderClipper(this.shape);
     final ShapeBorder shape;
     @override
     Path getClip(Size size) => shape.getOuterPath(Offset.zero & size);
     @override
     bool shouldReclip(_ShapeBorderClipper oldClipper) => oldClipper.shape != shape;
   }
   ```

5. **默认背景色改为半透明**：`_NavigationBarDefaultsM3.backgroundColor`（第 728 行）改为
   `_colors.surfaceContainer.withValues(alpha: _kBackgroundOpacity)`，
   否则不透明背景会完全遮住模糊效果。

## 说明
- 描边（borderSide）、指示器、图标等其余绘制逻辑不动，描边仍在模糊层之上
- 模糊层只在导航栏小面积内生效，性能开销可接受
- 模糊强度与透明度如觉不合适，调整 `_kBlurSigma` / `_kBackgroundOpacity` 两个常量即可
- 构建由你自行执行，我不运行构建