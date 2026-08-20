import 'package:PiliPlus/common/constants.dart';
import 'package:PiliPlus/plugin/pl_player/utils/fullscreen.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 自绘窗口标题栏（WinUI3 风格），替代原生标题栏。
///
/// 原生标题栏的图标/标题固定绘制在窗口最左端且无法内缩，
/// 在圆角过大的显示器上会被左上角遮挡；自绘后可通过
/// [WindowCaption.insetLeft]/[insetRight] 自由控制左右内边距。
///
/// 依赖原生窗口已移除 WS_CAPTION（见 windows/runner/win32_window.cpp），
/// 仅在 Windows 上使用。
class WindowCaption extends StatelessWidget {
  const WindowCaption({super.key});

  /// 左侧内边距（图标与窗口左缘的距离）。
  ///
  /// 采用 WinUI3 的标准做法：内容置于 AppWindow.TitleBar.LeftInset 加
  /// 12px 处（窗口按钮右置时 LeftInset 为 0），与原生标题栏图标位置一致，
  /// 同时也大于 Win11 的圆角半径（8px），不会被圆角裁切。
  static const double insetLeft = 12;

  /// 右侧内边距（窗口按钮与窗口右缘的距离）。
  static const double insetRight = 16;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: desktopCaptionHidden,
      builder: (context, hidden, _) {
        // 原生全屏（media_kit）与桌面画中画期间隐藏标题栏
        if (hidden) return const SizedBox.shrink();
        return const _CaptionBar();
      },
    );
  }
}

class _CaptionBar extends StatefulWidget {
  const _CaptionBar();

  @override
  State<_CaptionBar> createState() => _CaptionBarState();
}

class _CaptionBarState extends State<_CaptionBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _updateMaximizedState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _updateMaximizedState() async {
    final isMaximized = await windowManager.isMaximized();
    if (mounted && isMaximized != _isMaximized) {
      setState(() => _isMaximized = isMaximized);
    }
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    // 跟随系统深色模式（而非应用主题）：标题栏是窗口系统 UI 的一部分，
    // 应始终与 Windows 的明暗设置保持一致。
    final brightness = MediaQuery.platformBrightnessOf(context);
    final titleColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black.withValues(alpha: 0.8956);
    return ColoredBox(
      // WinUI3 明/暗标题栏底色，固定值以跟随系统而非应用主题
      color: brightness == Brightness.dark
          ? const Color(0xFF1C1C1C)
          : Colors.white,
      child: SizedBox(
        height: kWindowCaptionHeight,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTap: windowManager.popUpWindowMenu,
                child: DragToMoveArea(
                child: Row(
                  children: [
                    const SizedBox(width: WindowCaption.insetLeft),
                    // 与任务栏/资源管理器使用同一个窗口图标文件，
                    // 直接以资产方式加载（Flutter 引擎支持解码 ICO）。
                    Image.asset(
                      'windows/runner/resources/app_icon.ico',
                      width: 16,
                      height: 16,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 8),
                    // 用原生标题栏同款文字（Segoe UI 12px，与 Win11 一致）。
                    // 标题栏位于 MaterialApp.builder 内、Material 组件之外，
                    // 未显式设置的样式会继承框架的"错误样式"（w900 粗体 +
                    // 黄色双下划线），因此必须完整指定 fontWeight/decoration。
                    Text(
                      Constants.appName,
                      style: TextStyle(
                        fontFamily: 'Segoe UI',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                        color: titleColor,
                      ),
                    ),
                    // 占满剩余宽度，保证整条区域可拖拽/可右键
                    const Expanded(child: SizedBox.expand()),
                  ],
                ),
                ),
              ),
            ),
            const SizedBox(width: WindowCaption.insetRight),
            WindowCaptionButton.minimize(
              brightness: brightness,
              onPressed: windowManager.minimize,
            ),
            if (_isMaximized)
              WindowCaptionButton.unmaximize(
                brightness: brightness,
                onPressed: windowManager.unmaximize,
              )
            else
              WindowCaptionButton.maximize(
                brightness: brightness,
                onPressed: windowManager.maximize,
              ),
            WindowCaptionButton.close(
              brightness: brightness,
              onPressed: windowManager.close,
            ),
          ],
        ),
      ),
    );
  }
}
