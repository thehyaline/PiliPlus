import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;

/// 运行时注册的字体。HarmonyOS Sans 仅在 Windows 平台打包，
/// 其余平台不包含字体资源，也不会调用注册。
abstract final class FontUtils {
  static const String harmonyFamily = 'HarmonyOS Sans SC';

  static const List<String> _harmonyFiles = [
    'HarmonyOS_Sans_SC_Thin.ttf',
    'HarmonyOS_Sans_SC_Light.ttf',
    'HarmonyOS_Sans_SC_Regular.ttf',
    'HarmonyOS_Sans_SC_Medium.ttf',
    'HarmonyOS_Sans_SC_Bold.ttf',
    'HarmonyOS_Sans_SC_Black.ttf',
  ];

  /// 注册 HarmonyOS Sans 全字重，失败时静默回退系统字体。
  static Future<void> loadHarmonyOSFonts() async {
    if (!PlatformUtils.isWindows) return;
    try {
      final loader = FontLoader(harmonyFamily);
      for (final file in _harmonyFiles) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    } catch (e) {
      // 字体加载失败不影响启动
    }
  }
}
