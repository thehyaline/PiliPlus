import 'package:material_ui/material_ui.dart'
    show BorderRadius, Radius, BoxConstraints, ButtonStyle, VisualDensity;

abstract final class Style {
  static const cardSpace = 8.0;
  static const safeSpace = 12.0;

  /// 动态瀑布流统一间距：页面左右外边距、卡片上下间距、列间间距均为 12（与首页视频卡片一致）
  static const waterfallMargin = 12.0;

  /// 视频竖版卡片网格（主页推荐/直播流）的行列间距
  static const videoCardSpace = 12.0;

  /// 视频竖版卡片文字区高度（标题/信息行/徽章行）
  static const videoCardContentHeight = 74.0;
  static const mdRadius = BorderRadius.all(imgRadius);
  static const imgRadius = Radius.circular(10);
  static const aspectRatio = 16 / 10;
  static const aspectRatio16x9 = 16 / 9;
  static const imgMaxRatio = 2.6;
  static const bottomSheetRadius = BorderRadius.vertical(top: .circular(18));
  static const dialogFixedConstraints = BoxConstraints.tightFor(width: 420);
  static const topBarHeight = 52.0;
  static const buttonStyle = ButtonStyle(
    visualDensity: VisualDensity(horizontal: -2, vertical: -1.25),
    tapTargetSize: .shrinkWrap,
  );
  static const placeHolder = '\uFFFC';
}
