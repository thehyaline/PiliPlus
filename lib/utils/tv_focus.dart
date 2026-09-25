import 'package:PiliPlus/utils/storage_pref.dart';
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

  /// 播放器「画面」大焦点的预选框。
  ///
  /// 和控件那套（[playerRadius] / [playerBorderWidth] / [playerScale]）分开：
  /// 画面是整块视频，缩放会把画面推出视口，圆角也不该跟着按钮那套走
  /// （blbl 的 `blbl_focus_bg_round.xml` 用的是 10dp 圆角）。
  /// 描边画在视频边界**内侧**，所以贴着内边距、不会被视口裁掉。
  static const surfaceRadius = BorderRadius.all(Radius.circular(10));
  static const surfaceBorderWidth = 2.0;

  /// 顶部标签栏预选框的圆角。
  ///
  /// 标签格子只有 ~42 高、彼此紧挨着，卡片那套（[radius]，12）在这个高度上
  /// 看着偏圆；对齐 blbl 的 `blbl_focus_bg_round.xml`（10dp）。
  static const tabRadius = BorderRadius.all(Radius.circular(10));

  /// 标签预选框底纹的不透明度（用主题色打这个透明度）。
  ///
  /// 底纹画在标签文字**底下**（见 [FocusRing.fillColor]），所以可以比描边明显
  /// 一点，但不能压过"当前选中的那一栏"的指示条——调的时候看着指示条调。
  static const tabFillAlpha = 0.12;
}

/// 播放器是不是按"手柄播放器模型"走。**视频页和直播页一样**（对齐 BBLL）。
///
/// 这是 [Pref.tvFocus] 的一部分，没有单独的开关。打开后播放器整套语义都换掉：
/// - 非全屏：整块画面 = 一个焦点，播放器里的控件一个都进不了焦点树，
///   确定键 = 进全屏（见 `TvPlayerSurface`）；
/// - 全屏：焦点可以进上下栏；上下栏收起来时焦点停在画面上、环也不画，
///   确定键 = 播放/暂停，方向键 = 唤栏 + 焦点送到播放/暂停按钮；
///   进上栏锁到返回键、进下栏锁到播放/暂停（见 `TvEntryLock`）。
///
/// 页面里判断一律用它，别在调用点上再分直播/视频：两页的差别全在上下栏
/// 各自的内容里（直播页没有进度条、快进被 `isLive` 短路），而这一套只谈
/// "焦点停在哪、确定键干什么"，那部分两页是一致的。
bool isPlayerTvMode() => Pref.tvFocus;

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

  /// 播放器**页面那一层**（`PlayerFocus` 的节点，焦点锚点）。
  ///
  /// 画面那一层（[playerSurface]）被从树上拿掉时，焦点落到这里。
  /// 播放器不是一直都在的：`videoState` 还没就绪、`autoPlay` 关着、
  /// 切布局（画中画/横屏/几乎方屏）、拉流失败重试……这些时候
  /// `PLVideoPlayer` 会被换成 `SizedBox.shrink()`。
  /// 焦点正停在里面时，框架只会把焦点向上交给某个 scope（最后是根 scope），
  /// 那之后就**按方向键什么都不会发生**——环没了，也没有下一个控件可去
  /// （那个 scope 的矩形覆盖整页）。所以画面消失前得把焦点主动交给还活着的这一层。
  static const playerPage = 'player-page';

  /// 播放器 OSD 整层（顶部信息栏 + 底部控制条）。
  static const playerOsd = 'player-osd';

  /// 顶部信息栏（返回、投屏、设置……）。
  ///
  /// 焦点**进到这一栏**里时落点锁在返回键上（见 `TvEntryLock`）。
  static const playerOsdTop = 'player-osd-top';

  /// 底部控制条。
  ///
  /// 焦点进到这一栏里时落点锁在播放/暂停按钮上（见 `TvEntryLock`）。
  static const playerOsdBar = 'player-osd-bar';

  /// 底部控制条的播放/暂停按钮（焦点**锚点**）。
  ///
  /// 进下栏时的固定落点，也是全屏下按方向键时"焦点回到哪儿"的答案。
  static const playerPlayPause = 'player-play-pause';

  /// 顶部信息栏的返回按钮（焦点**锚点**）。
  ///
  /// 进上栏时的固定落点（bbll 的返回键是刻意不可聚焦的，这里反过来
  /// 拿它当上栏入口：手柄用户进上栏十有八九是想退出去）。
  ///
  /// 两页的返回键**都**登记这个锚点，但直播页的返回键只在全屏 / 桌面画中画
  /// 才有——那正是手柄模式下焦点能进上栏的时候，非全屏时上栏整层不可聚焦。
  static const playerBack = 'player-back';
}
