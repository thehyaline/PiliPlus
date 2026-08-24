import 'dart:math';

import 'package:PiliPlus/common/skeleton/dynamic_card.dart';
import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/rendering.dart' show SliverConstraints;
import 'package:material_ui/material_ui.dart';
import 'package:waterfall_flow/waterfall_flow.dart'
    show SliverWaterfallFlowDelegate;

/// 计算瀑布流网格在给定可用宽度下的列数与网格宽度，
/// 供网格 delegate 与外部布局（动态页侧边直播板块定位）共用
({int count, double gridWidth, bool isLimited}) dynGridMetrics(
  double gridExtent,
) {
  final cardW = Pref.dynamicCardWidth;
  final limit = Pref.dynamicsColumnLimit;
  final naturalCount = max(1, (gridExtent / (cardW + Style.waterfallMargin)).ceil());
  if (limit == 0 || naturalCount <= limit) {
    return (count: naturalCount, gridWidth: gridExtent, isLimited: false);
  }
  return (
    count: limit,
    gridWidth: limit * cardW + (limit - 1) * Style.waterfallMargin,
    isLimited: true,
  );
}

mixin DynMixin {
  SliverWaterfallFlowDelegateWithMaxCrossAxisExtent get dynGridDelegate =>
      SliverWaterfallFlowDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: Pref.dynamicCardWidth,
        crossAxisSpacing: Style.waterfallMargin,
        maxCrossAxisCount: Pref.dynamicsColumnLimit == 0
            ? null
            : Pref.dynamicsColumnLimit,
      );

  Widget buildPage(Widget child) {
    // 给上下左右留出外边距，保持卡片圆角背景样式一致；
    // 列数受限时的居中留空由 dynGridDelegate 处理
    return SliverPadding(
      padding: const EdgeInsets.only(
        left: Style.waterfallMargin,
        top: Style.waterfallMargin,
        right: Style.waterfallMargin,
      ),
      sliver: child,
    );
  }

  SliverGridDelegateWithExtentAndRatio get skeDelegate =>
      SliverGridDelegateWithExtentAndRatio(
        crossAxisSpacing: Style.waterfallMargin,
        mainAxisSpacing: 0,
        maxCrossAxisExtent: Pref.dynamicCardWidth,
        childAspectRatio: Style.aspectRatio,
        mainAxisExtent: 50,
        maxCrossAxisCount: Pref.dynamicsColumnLimit == 0
            ? null
            : Pref.dynamicsColumnLimit,
      );

  Widget get dynSkeleton {
    return SliverGrid.builder(
      gridDelegate: skeDelegate,
      itemBuilder: (_, _) => const DynamicCardSkeleton(),
      itemCount: 10,
    );
  }
}

class SliverWaterfallFlowDelegateWithMaxCrossAxisExtent
    extends SliverWaterfallFlowDelegate {
  /// Creates a delegate that makes masonry layouts with tiles that have a maximum
  /// cross-axis extent.
  ///
  /// All of the arguments must not be null. The [maxCrossAxisExtent],
  /// [mainAxisSpacing], and [crossAxisSpacing] arguments must not be negative.
  SliverWaterfallFlowDelegateWithMaxCrossAxisExtent({
    required this.maxCrossAxisExtent,
    this.maxCrossAxisCount,
    super.mainAxisSpacing,
    super.crossAxisSpacing,
    super.lastChildLayoutTypeBuilder,
    super.collectGarbage,
    super.viewportBuilder,
    super.closeToTrailing,
  }) : assert(maxCrossAxisExtent >= 0);

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

  /// 最大列数限制；为 null 时按 [maxCrossAxisExtent] 自适应。
  /// 超出限制时优先保证侧边板块：空间足够则卡片保持 [maxCrossAxisExtent]
  /// 宽度并水平居中，空间不足则卡片收缩铺满。
  final int? maxCrossAxisCount;

  int? crossAxisCount;
  double? crossAxisExtent;

  /// 当前约束下是否触发了列数上限（自然列数超出 [maxCrossAxisCount]）
  bool _isLimited(SliverConstraints constraints) =>
      dynGridMetrics(constraints.crossAxisExtent).isLimited;

  @override
  int getCrossAxisCount(SliverConstraints constraints) {
    final crossAxisExtent = constraints.crossAxisExtent;
    if (crossAxisCount != null && this.crossAxisExtent == crossAxisExtent) {
      return crossAxisCount!;
    }
    this.crossAxisExtent = crossAxisExtent;
    return crossAxisCount = dynGridMetrics(crossAxisExtent).count;
  }

  @override
  double getChildUsableCrossAxisExtent(SliverConstraints constraints) {
    // 列数受限时优先保证侧边"正在直播"板块：空间足以容纳满宽网格（limit 列 × 最大卡片宽）
    // 时卡片保持最大宽度居中留白；空间不足时退化为铺满（卡片收缩），不再挤压板块
    final metrics = dynGridMetrics(constraints.crossAxisExtent);
    if (metrics.isLimited &&
        constraints.crossAxisExtent >= metrics.gridWidth) {
      return maxCrossAxisExtent;
    }
    return super.getChildUsableCrossAxisExtent(constraints);
  }

  @override
  double getCrossAxisOffset(SliverConstraints constraints, int? crossAxisIndex) {
    final offset = super.getCrossAxisOffset(constraints, crossAxisIndex);
    if (!_isLimited(constraints)) {
      return offset;
    }
    // 受限且空间充足时网格整体水平居中：剩余空间平分到两侧；
    // 空间不足时卡片铺满（收缩），无居中偏移
    final gridWidth = dynGridMetrics(constraints.crossAxisExtent).gridWidth;
    return offset + max(0.0, (constraints.crossAxisExtent - gridWidth) / 2);
  }

  @override
  bool shouldRelayout(SliverWaterfallFlowDelegate oldDelegate) {
    final flag =
        (oldDelegate.runtimeType != runtimeType) ||
        (oldDelegate is SliverWaterfallFlowDelegateWithMaxCrossAxisExtent &&
            (oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
                oldDelegate.maxCrossAxisCount != maxCrossAxisCount ||
                super.shouldRelayout(oldDelegate)));
    if (flag) {
      crossAxisCount = null;
    }
    return flag;
  }
}
