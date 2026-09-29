import 'package:PiliPlus/utils/device_utils.dart';
import 'package:material_ui/material_ui.dart';

/// from Getx
extension ContextExtensions on BuildContext {
  /// The same of [MediaQuery.of(context).size]
  Size get mediaQuerySize => MediaQuery.sizeOf(this);

  /// The same of [MediaQuery.of(context).size.height]
  /// Note: updates when you rezise your screen (like on a browser or
  /// desktop window)
  double get height => MediaQuery.heightOf(this);

  /// The same of [MediaQuery.of(context).size.width]
  /// Note: updates when you resize your screen (like on a browser or
  /// desktop window)
  double get width => MediaQuery.widthOf(this);

  /// similar to [MediaQuery.of(context).padding]
  ThemeData get theme => Theme.of(this);

  /// Check if dark mode theme is enable
  bool get isDarkMode => (Theme.brightnessOf(this) == Brightness.dark);

  /// give access to Theme.of(context).iconTheme.color
  Color? get iconColor => IconTheme.of(this).color;

  /// similar to [MediaQuery.of(context).padding]
  TextTheme get textTheme => TextTheme.of(this);

  /// similar to [MediaQuery.of(context).padding]
  EdgeInsets get mediaQueryPadding => MediaQuery.viewPaddingOf(this);

  /// similar to [MediaQuery.of(context).padding]
  MediaQueryData get mediaQuery => MediaQuery.of(this);

  /// similar to [MediaQuery.of(context).viewPadding]
  EdgeInsets get mediaQueryViewPadding => MediaQuery.viewPaddingOf(this);

  /// similar to [MediaQuery.of(context).viewInsets]
  EdgeInsets get mediaQueryViewInsets => MediaQuery.viewInsetsOf(this);

  /// similar to [MediaQuery.of(context).orientation]
  Orientation get orientation => MediaQuery.orientationOf(this);

  /// check if device is on landscape mode
  bool get isLandscape => orientation == Orientation.landscape;

  /// check if device is on portrait mode
  bool get isPortrait => orientation == Orientation.portrait;

  /// similar to [MediaQuery.of(this).devicePixelRatio]
  double get devicePixelRatio => MediaQuery.devicePixelRatioOf(this);

  /// similar to [MediaQuery.of(this).textScaleFactor]
  TextScaler get textScaler => MediaQuery.textScalerOf(this);

  /// get the shortestSide from screen
  double get mediaQueryShortestSide => mediaQuerySize.shortestSide;

  /// True if width be larger than 800
  bool get showNavbar => (width > 800);

  /// True if the shortestSide is smaller than 600p
  ///
  /// 电视是宽屏设备，走平板/桌面那一套，所以这里也不成立（见 [isSmallTablet]）。
  bool get isPhone => !isSmallTablet;

  /// True if the shortestSide is largest than 600p
  ///
  /// 电视也算：电视盒子的逻辑短边只有 540dp（1080p@xhdpi 是 960×540），按尺寸
  /// 会被判成手机、退回手机那套窄布局（导航栏变成底部一条、发布页缩短…）。
  /// 电视是 10 英尺的宽屏设备，就按平板那一套走，见 `DeviceUtils.isTv`。
  bool get isSmallTablet => DeviceUtils.isTv || (mediaQueryShortestSide >= 600);

  /// True if the shortestSide is largest than 720p
  bool get isLargeTablet => (mediaQueryShortestSide >= 720);

  /// True if the current device is Tablet
  bool get isTablet => isSmallTablet;
}
