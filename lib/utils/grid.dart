import 'dart:math';

import 'package:PiliPlus/common/skeleton/video_card_h.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

mixin GridMixin {
  late final gridDelegate = Grid.videoCardHDelegate();

  Widget get gridSkeleton => SliverGrid.builder(
    gridDelegate: gridDelegate,
    itemBuilder: (_, _) => const VideoCardHSkeleton(),
    itemCount: 10,
  );
}

abstract final class Grid {
  static final double smallCardWidth = Pref.smallCardWidth;

  /// 横向视频卡片（行高 110）的最小可用宽度：
  /// 16:10 封面约 160 + 左右 padding 24 + 间距 10 + 数据行约 130 + 余量。
  /// 面板放不下两列该宽度的卡片时保持单列，避免卡片过窄导致信息显示不全。
  static const double videoCardHMinWidth = 400;

  static SliverGridDelegateWithMaxCrossAxisExtent videoCardHDelegate({
    double mainAxisExtent = 110,
  }) => SliverGridDelegateWithMaxCrossAxisExtent(
    mainAxisSpacing: 2,
    mainAxisExtent: mainAxisExtent,
    maxCrossAxisExtent: Grid.smallCardWidth * 2,
    minCrossAxisExtent: Grid.videoCardHMinWidth,
  );

  /// 视频竖版卡片网格：主页推荐流、直播流统一使用的列表样式，
  /// 每行最多 [maxCrossAxisCount] 列，超出时整体居中留空。
  static SliverGridDelegateWithExtentAndRatio videoCardVDelegate({
    required double mainAxisExtent,
    int maxCrossAxisCount = 6,
  }) => SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.videoCardSpace,
    crossAxisSpacing: Style.videoCardSpace,
    maxCrossAxisExtent: Pref.recommendCardWidth,
    maxCrossAxisCount: maxCrossAxisCount,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: mainAxisExtent,
  );

  /// 网格在 [crossAxisExtent] 宽度内居中时单侧需要留出的空白。
  ///
  /// 与 [videoCardVDelegate] 的列数上限/居中逻辑保持一致，
  /// 供列表上方的头部元素（如直播页分区栏、搜索页过滤器）对齐卡片区域。
  static double videoGridPadding(
    double crossAxisExtent, {
    int maxCrossAxisCount = 6,
  }) {
    const spacing = Style.videoCardSpace;
    final maxExtent = Pref.recommendCardWidth;
    final count = max(
      1,
      ((crossAxisExtent - spacing) / (maxExtent + spacing)).ceil(),
    );
    if (count <= maxCrossAxisCount) {
      // 未触发列数上限时卡片拉伸铺满整行，与网格 delegate 一致无留白
      return 0;
    }
    final gridWidth =
        maxCrossAxisCount * maxExtent + spacing * (maxCrossAxisCount - 1);
    return max(0.0, (crossAxisExtent - gridWidth) / 2);
  }
}

class SliverGridDelegateWithExtentAndRatio extends SliverGridDelegate {
  /// Creates a delegate that makes grid layouts with tiles that have a maximum
  /// cross-axis extent.
  ///
  /// The [maxCrossAxisExtent], [mainAxisExtent], [mainAxisSpacing],
  /// and [crossAxisSpacing] arguments must not be negative.
  /// The [childAspectRatio] argument must be greater than zero.
  SliverGridDelegateWithExtentAndRatio({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent = 0.0,
    this.maxCrossAxisCount,
  }) : assert(maxCrossAxisExtent > 0),
       assert(mainAxisSpacing >= 0),
       assert(crossAxisSpacing >= 0),
       assert(childAspectRatio > 0);

  /// The maximum extent of tiles in the cross axis.
  ///
  /// This delegate will select a cross-axis extent for the tiles that is as
  /// large as possible subject to the following conditions:
  ///
  ///  - The extent evenly divides the cross-axis extent of the grid.
  ///  - The extent is at most [maxCrossAxisExtent].
  ///
  /// For example, if the grid is vertical, the grid is 500.0 pixels wide, and
  /// [maxCrossAxisExtent] is 150.0, this delegate will create a grid with 4
  /// columns that are 125.0 pixels wide.
  final double maxCrossAxisExtent;

  /// The maximum number of tiles in the cross axis.
  ///
  /// When the cross-axis extent can hold more columns than this limit,
  /// tiles keep at most [maxCrossAxisExtent] wide and the remaining
  /// space is evenly distributed on both sides to center the grid.
  final int? maxCrossAxisCount;

  /// The number of logical pixels between each child along the main axis.
  final double mainAxisSpacing;

  /// The number of logical pixels between each child along the cross axis.
  final double crossAxisSpacing;

  /// The ratio of the cross-axis to the main-axis extent of each child.
  final double childAspectRatio;

  /// The extent of each tile in the main axis. If provided, it would add
  /// after [childAspectRatio] is used.
  final double mainAxisExtent;

  bool _debugAssertIsValid(double crossAxisExtent) {
    assert(crossAxisExtent > 0.0);
    assert(maxCrossAxisExtent > 0.0);
    assert(mainAxisSpacing >= 0.0);
    assert(crossAxisSpacing >= 0.0);
    assert(childAspectRatio > 0.0);
    return true;
  }

  SliverGridLayout? layoutCache;
  double? crossAxisExtentCache;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    // invoked before each frame
    assert(_debugAssertIsValid(constraints.crossAxisExtent));
    if (layoutCache != null &&
        constraints.crossAxisExtent == crossAxisExtentCache) {
      return layoutCache!;
    }
    crossAxisExtentCache = constraints.crossAxisExtent;
    int crossAxisCount =
        ((constraints.crossAxisExtent - crossAxisSpacing) /
                (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    // Ensure a minimum count of 1, can be zero and result in an infinite extent
    // below when the window size is 0.
    crossAxisCount = max(1, crossAxisCount);
    final double usableCrossAxisExtent = max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    double childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    double crossAxisOffset = 0.0;
    // 列数超过上限时不再拉伸铺满，卡片保持最大宽度并把剩余空间平分到两侧
    if (maxCrossAxisCount case final maxCount? when crossAxisCount > maxCount) {
      crossAxisCount = maxCount;
      childCrossAxisExtent = maxCrossAxisExtent;
      crossAxisOffset = max(
        0.0,
        (constraints.crossAxisExtent -
                (childCrossAxisExtent * crossAxisCount +
                    crossAxisSpacing * (crossAxisCount - 1))) /
            2,
      );
    }
    final double childMainAxisExtent =
        childCrossAxisExtent / childAspectRatio + mainAxisExtent;
    return layoutCache = SliverCenteredGridLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      crossAxisOffset: crossAxisOffset,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithExtentAndRatio oldDelegate) {
    final flag =
        oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.mainAxisExtent != mainAxisExtent ||
        oldDelegate.maxCrossAxisCount != maxCrossAxisCount;
    if (flag) layoutCache = null;
    return flag;
  }
}

/// [SliverGridRegularTileLayout] 的变体，支持整体偏移
/// （列数受上限限制、网格居中留空时使用）。
class SliverCenteredGridLayout extends SliverGridLayout {
  const SliverCenteredGridLayout({
    required this.crossAxisCount,
    required this.mainAxisStride,
    required this.crossAxisStride,
    required this.childMainAxisExtent,
    required this.childCrossAxisExtent,
    required this.reverseCrossAxis,
    this.crossAxisOffset = 0.0,
  });

  final int crossAxisCount;
  final double mainAxisStride;
  final double crossAxisStride;
  final double childMainAxisExtent;
  final double childCrossAxisExtent;
  final bool reverseCrossAxis;

  /// 网格在交叉轴方向整体偏移的距离（居中留空用）
  final double crossAxisOffset;

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    return mainAxisStride > 1e-10
        ? crossAxisCount * (scrollOffset ~/ mainAxisStride)
        : 0;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (mainAxisStride > 0.0) {
      final int mainAxisCount = (scrollOffset / mainAxisStride).ceil();
      return max(0, crossAxisCount * mainAxisCount - 1);
    }
    return 0;
  }

  double _getOffsetFromStartInCrossAxis(double crossAxisStart) {
    if (reverseCrossAxis) {
      return crossAxisCount * crossAxisStride -
          crossAxisStart -
          childCrossAxisExtent -
          (crossAxisStride - childCrossAxisExtent) -
          crossAxisOffset;
    }
    return crossAxisStart + crossAxisOffset;
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final double crossAxisStart = (index % crossAxisCount) * crossAxisStride;
    return SliverGridGeometry(
      scrollOffset: (index ~/ crossAxisCount) * mainAxisStride,
      crossAxisOffset: _getOffsetFromStartInCrossAxis(crossAxisStart),
      mainAxisExtent: childMainAxisExtent,
      crossAxisExtent: childCrossAxisExtent,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount == 0) {
      return 0.0;
    }
    final int mainAxisCount = ((childCount - 1) ~/ crossAxisCount) + 1;
    final double mainAxisSpacing = mainAxisStride - childMainAxisExtent;
    return mainAxisStride * mainAxisCount - mainAxisSpacing;
  }
}

class SliverGridDelegateWithMaxCrossAxisExtent extends SliverGridDelegate {
  /// Creates a delegate that makes grid layouts with tiles that have a maximum
  /// cross-axis extent.
  ///
  /// The [maxCrossAxisExtent], [mainAxisExtent], [mainAxisSpacing],
  /// and [crossAxisSpacing] arguments must not be negative.
  /// The [childAspectRatio] argument must be greater than zero.
  SliverGridDelegateWithMaxCrossAxisExtent({
    required this.maxCrossAxisExtent,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
    this.childAspectRatio = 1.0,
    this.mainAxisExtent,
    this.minCrossAxisExtent,
  }) : assert(maxCrossAxisExtent > 0),
       assert(mainAxisSpacing >= 0),
       assert(crossAxisSpacing >= 0),
       assert(childAspectRatio > 0),
       assert(mainAxisExtent == null || mainAxisExtent >= 0),
       assert(minCrossAxisExtent == null || minCrossAxisExtent > 0);

  /// The maximum extent of tiles in the cross axis.
  ///
  /// This delegate will select a cross-axis extent for the tiles that is as
  /// large as possible subject to the following conditions:
  ///
  ///  - The extent evenly divides the cross-axis extent of the grid.
  ///  - The extent is at most [maxCrossAxisExtent].
  ///
  /// For example, if the grid is vertical, the grid is 500.0 pixels wide, and
  /// [maxCrossAxisExtent] is 150.0, this delegate will create a grid with 4
  /// columns that are 125.0 pixels wide.
  final double maxCrossAxisExtent;

  /// The number of logical pixels between each child along the main axis.
  final double mainAxisSpacing;

  /// The number of logical pixels between each child along the cross axis.
  final double crossAxisSpacing;

  /// The ratio of the cross-axis to the main-axis extent of each child.
  final double childAspectRatio;

  /// The extent of each tile in the main axis. If provided it would define the
  /// logical pixels taken by each tile in the main-axis.
  ///
  /// If null, [childAspectRatio] is used instead.
  final double? mainAxisExtent;

  /// The minimum extent of tiles in the cross axis.
  ///
  /// When the grid is not wide enough to keep every column at least this
  /// wide, the column count is reduced (down to 1) instead. null means no
  /// constraint.
  final double? minCrossAxisExtent;

  bool _debugAssertIsValid(double crossAxisExtent) {
    assert(crossAxisExtent > 0.0);
    assert(maxCrossAxisExtent > 0.0);
    assert(mainAxisSpacing >= 0.0);
    assert(crossAxisSpacing >= 0.0);
    assert(childAspectRatio > 0.0);
    return true;
  }

  SliverGridLayout? layoutCache;
  double? crossAxisExtentCache;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    assert(_debugAssertIsValid(constraints.crossAxisExtent));
    if (layoutCache != null &&
        constraints.crossAxisExtent == crossAxisExtentCache) {
      return layoutCache!;
    }
    crossAxisExtentCache = constraints.crossAxisExtent;
    int crossAxisCount =
        (constraints.crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing))
            .ceil();
    // 空间不足以让每列保持 [minCrossAxisExtent] 宽度时减少列数，
    // 避免卡片过窄导致内容显示不全
    if (minCrossAxisExtent case final minExtent?) {
      crossAxisCount = min(
        crossAxisCount,
        (constraints.crossAxisExtent / (minExtent + crossAxisSpacing)).floor(),
      );
    }
    // Ensure a minimum count of 1, can be zero and result in an infinite extent
    // below when the window size is 0.
    crossAxisCount = max(1, crossAxisCount);
    final double usableCrossAxisExtent = max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1),
    );
    final double childCrossAxisExtent = usableCrossAxisExtent / crossAxisCount;
    final double childMainAxisExtent =
        mainAxisExtent ?? childCrossAxisExtent / childAspectRatio;
    return layoutCache = SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: childMainAxisExtent + mainAxisSpacing,
      crossAxisStride: childCrossAxisExtent + crossAxisSpacing,
      childMainAxisExtent: childMainAxisExtent,
      childCrossAxisExtent: childCrossAxisExtent,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(SliverGridDelegateWithMaxCrossAxisExtent oldDelegate) {
    final flag =
        oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.mainAxisExtent != mainAxisExtent ||
        oldDelegate.minCrossAxisExtent != minCrossAxisExtent;
    if (flag) layoutCache = null;
    return flag;
  }
}
