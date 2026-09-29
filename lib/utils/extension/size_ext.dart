import 'dart:ui' show Size;

import 'package:PiliPlus/utils/device_utils.dart';

extension SizeExt on Size {
  /// 窄屏 / 竖屏形态（手机），也用来在横屏播放页区分"矮屏放不下侧栏"。
  ///
  /// 电视恒为 false：电视盒子的逻辑分辨率可能很窄——1080p@xhdpi 是 960×540，
  /// 密度再高的电视还会更窄，"宽 < 600" 一旦命中就把一块横屏电视判成竖屏手机，
  /// 导航栏于是退回底部那一条。电视是横屏设备，见 `DeviceUtils.isTv`。
  bool get isPortrait => !DeviceUtils.isTv && (width < 600 || height >= width);

}
