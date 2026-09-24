import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_ui/material_ui.dart' show BorderRadius, Radius;

/// 10-foot 焦点相关的共享常量与判定。
///
/// 视觉规格对齐 blbl 的 `blbl_focus_scale.xml`（scale 1.04 / 120ms）与
/// `blbl_focus_stroke.xml`（2dp 主题色描边）。
abstract final class TvFocusSpec {
  /// 焦点态缩放倍数。
  static const scale = 1.04;

  /// 焦点态过渡时长。
  static const duration = Duration(milliseconds: 120);

  /// 描边宽度。
  static const borderWidth = 2.0;

  /// 默认圆角（与 Card / VideoCardV 的 InkWell 一致）。
  static const radius = BorderRadius.all(Radius.circular(12));

  /// 长按确定触发「更多」所需的按住时长（与 Flutter `kLongPressTimeout`、 Android
  /// `ViewConfiguration.getLongPressTimeout()` 一致）。
  static const longPressDuration = Duration(milliseconds: 500);

  /// 焦点缩放的安全空隙。
  ///
  /// 1.04 倍缩放每边溢出约卡片尺寸的 2%；网格列间距为 12 时不会压到邻卡，
  /// 但最外侧一行/列会超出视口被裁切，所以滚动区域左右各留这么多内边距。
  static const safeSpace = 8.0;

  /// 网格/列表的 `scrollCacheExtent`。
  ///
  /// 默认 250 只够半行，下一行不进焦点树，方向键到底部就会卡住
  /// （`TraversalEdgeBehavior.stop` 让焦点原地不动）。
  /// 撑到 800 后下一行始终在树里，方向键找得到目标、`Scrollable.ensureVisible`
  /// 会把它滚进来。
  static const cacheExtent = ScrollCacheExtent.pixels(800);

  /// 首页等信息流里"每屏一栏"的切换步长（供后续 TV 分栏使用）。
  static const Duration scrollAnimation = Duration(milliseconds: 220);

  /// 播放器控件的焦点环。
  ///
  /// 播放器按钮只有 30~34 见方、紧挨着排，卡片那套（1.04 倍 + 2dp）会互相压边，
  /// 所以描边细一点、圆角小一点、缩放也更克制。
  static const playerRadius = BorderRadius.all(Radius.circular(8));
  static const playerBorderWidth = 1.5;
  static const playerScale = 1.1;

  /// 手柄停在进度条上按左右键的微调步长。
  ///
  /// 比画面上的快进/快退（`Pref.fastForBackwardDuration`，默认 15 秒）小，
  /// 用来精确对时间点；按住不放会跟着系统重复一路累加。
  static const seekStep = Duration(seconds: 5);
}

/// 播放器各层共享的 `TvRegions` 标签。
///
/// 播放器是"一块画面 + 一层悬浮 OSD"，而 OSD 由视频页和直播页各自拼装，
/// 标签放哪一边都不合适，统一挪到这里。
abstract final class TvLabels {
  /// 播放器画面本身（焦点**锚点**，不是区域）。
  ///
  /// 控制条收起来时焦点要回到这里：这样方向键重新是音量/快进，
  /// 而不是停在一个已经看不见的按钮上。
  static const playerSurface = 'player-surface';

  /// 播放器 OSD 整层（顶部信息栏 + 底部控制条）。
  static const playerOsd = 'player-osd';

  /// 底部控制条。
  ///
  /// 「确定键进控制条」的落点：视频页是进度条，直播页是播放/暂停按钮。
  static const playerOsdBar = 'player-osd-bar';
}
