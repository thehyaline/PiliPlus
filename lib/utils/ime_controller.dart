import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Windows 输入法上下文控制。
///
/// 焦点在文本输入框（实现了 [TextInputClient] 的组件，覆盖 SDK 的 TextField
/// 与项目 vendored 的 RichTextField）时启用输入法，否则禁用窗口 IME，
/// 避免中文输入法消费按键导致播放器快捷键失效。
abstract final class ImeController {
  static const MethodChannel _channel = MethodChannel('piliplus/ime');

  static bool _enabled = true;

  static void init() {
    if (!PlatformUtils.isWindows) {
      return;
    }
    FocusManager.instance.addListener(_sync);
    // 首帧前引擎窗口尚未创建，此时发送的消息会丢失，故初始同步
    // 推迟到首帧之后。
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  static bool _hasEditableFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) {
      return false;
    }
    var editable = false;
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is TextInputClient) {
        editable = true;
        return false;
      }
      return true;
    });
    return editable;
  }

  static void _sync() {
    final enabled = _hasEditableFocus();
    if (enabled == _enabled) {
      return;
    }
    _enabled = enabled;
    _channel.invokeMethod('setEnabled', enabled);
  }
}
