import 'dart:io' show Platform;

import 'package:PiliPlus/utils/android/bindings.g.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, Size;

abstract final class DeviceUtils {
  static final int sdkInt = AndroidHelper.sdkInt();

  static bool get isTablet {
    return size.shortestSide >= 600;
  }

  /// 电视 / 电视盒子（遥控器、10 英尺界面）。
  ///
  /// 判定只有这一个入口：Android 侧问系统（见 `AndroidHelper.isTelevision`）。
  /// **不能拿屏幕尺寸猜**：电视的逻辑短边只有 540dp（1080p@xhdpi 就是 960×540），
  /// 够不到 `isTablet` 那条 600dp 门槛——一块 55 英寸的屏在这里和手机归成一类。
  /// 于是首帧就锁上竖屏，系统再把竖屏窗口摆到横屏面板上，左右各留一条黑边
  /// （"界面左右留黑"就是这么来的），导航栏也跟着退回底部那一条（手机布局）。
  static bool get isTv => Platform.isAndroid && _isTv;

  /// 惰性初始化：只有真的在 Android 上问到时才走 JNI，桌面等平台不碰。
  static final bool _isTv = AndroidHelper.isTelevision;

  static Size get size {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  /// 设置导出/导入的默认文件名用的：电视的备份不和手机、平板混在一起。
  static String get platformName => PlatformUtils.isDesktop
      ? 'desktop'
      : isTv
      ? 'tv'
      : isTablet
      ? 'pad'
      : 'phone';
}
