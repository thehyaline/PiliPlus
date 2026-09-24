import 'package:PiliPlus/utils/tv_back.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

/// 统一的返回动作：先给拦截栈，再关弹窗，最后交给路由。
///
/// 手柄 B / 遥控器返回 / 键盘 Esc / 鼠标侧键都走这里，
/// 这样"返回"只有一套语义，各处不用各写一份。
void appBack() {
  if (TvBack.dispatch()) return;

  if (SmartDialog.checkExist()) {
    SmartDialog.dismiss();
    return;
  }

  final route = Get.routing.route;
  if (route is GetPageRoute && route.popDisposition == .doNotPop) {
    route.onPopInvokedWithResult(false, null);
    return;
  }

  final navigator = Get.key.currentState;
  if (navigator != null && navigator.canPop()) {
    navigator.pop();
  }
}
