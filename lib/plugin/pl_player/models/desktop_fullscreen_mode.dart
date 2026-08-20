// 桌面端全屏模式
enum DesktopFullScreenMode {
  // 系统原生全屏
  fullscreen('全屏（默认）'),
  // 窗口内全屏
  windowFullscreen('窗口全屏'),
  ;

  final String desc;
  const DesktopFullScreenMode(this.desc);
}
