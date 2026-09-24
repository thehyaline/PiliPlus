import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart'
    show KeyEvent, LogicalKeyboardKey;
import 'package:material_ui/material_ui.dart';

/// 进度条微调需要的全部播放器能力。
///
/// 收窄成接口有两个好处：能脱离真实播放器做测试（见 `test/tv_focus_test.dart`），
/// 也把"微调到底依赖哪些状态"写清楚了。
abstract interface class TvSeekBarHost {
  /// 当前播放位置（秒）。
  int get position;

  /// 总时长（秒）；≤0 表示还不知道时长（没加载完/直播），这时不微调。
  int get duration;

  /// 微调中的位置（秒），和拖动共用同一个状态。
  int get seekPosition;
  set seekPosition(int value);

  /// 开始一次 seek（微调的第一步；拖动那条路由进度条自己调）。
  void beginSeek(int seconds);

  /// 提交一次 seek（毫秒），和拖动结束时是同一个动作。
  void commitSeek(int milliseconds);

  /// 微调时同步预览缩略图（拖动路径本来就有的行为）。
  void previewIndex(int seconds);

  /// 要不要预览图（`showSeekPreview`，直播/文件源没有）。
  bool get showPreview;

  /// 进度条上按确定键 = 播放/暂停（对齐 blbl：停在时间线上时确定键不 seek）。
  void togglePlay();
}

/// 给进度条加一个焦点节点，让手柄能"停在时间线上"微调。
///
/// - ←/→：±[TvFocusSpec.seekStep]，按住不放跟着系统重复一路累加；
///   走的是和拖动同一条路（[TvSeekBarHost.beginSeek] → `seekPosition`），
///   **抬起时才提交**，所以按住的过程不会一直发 seek 请求；
/// - 确定键：播放/暂停；
/// - ↑/↓：不拦，交给几何寻焦去下面的播放/暂停按钮。
///
/// 焦点离开时会把没提交的微调先提交掉，免得"按了 B 直接收控制条"时停在
/// `isSeeking` 状态上——那会让控制条再也不自动隐藏。
///
/// `Pref.tvFocus` 关掉时原样返回 [child]（鼠标拖动照旧）。
class TvSeekBar extends StatefulWidget {
  const TvSeekBar({
    super.key,
    required this.host,
    required this.child,
  });

  final TvSeekBarHost host;
  final Widget child;

  @override
  State<TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<TvSeekBar> {
  late final FocusNode _node = FocusNode(debugLabel: 'TvSeekBar');
  bool _adjusting = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final host = widget.host;
    final total = host.duration;
    if (total <= 0) return;
    if (!_adjusting) {
      _adjusting = true;
      host.beginSeek(host.position);
    }
    final next = (host.seekPosition + delta).clamp(0, total);
    host.seekPosition = next;
    if (host.showPreview) {
      host.previewIndex(next);
    }
  }

  void _commit() {
    if (!_adjusting) return;
    _adjusting = false;
    widget.host.commitSeek(widget.host.seekPosition * 1000);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    if (isLeft || key == LogicalKeyboardKey.arrowRight) {
      if (TvKeys.isRelease(event)) {
        _commit();
      } else {
        _step(TvFocusSpec.seekStep.inSeconds * (isLeft ? -1 : 1));
      }
      return KeyEventResult.handled;
    }
    if (TvKeys.isOk(event)) {
      if (TvKeys.isFirstPress(event)) {
        _commit();
        widget.host.togglePlay();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) {
      return widget.child;
    }
    return FocusRing(
      focusNode: _node,
      debugLabel: 'TvSeekBar',
      radius: TvFocusSpec.playerRadius,
      borderWidth: TvFocusSpec.playerBorderWidth,
      // 进度条是整宽的，缩放会顶出视口：只靠描边表示"停在这条时间线上"
      scale: 1.0,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) {
        if (!focused) _commit();
      },
      builder: (context, node, focused) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Focus(
          focusNode: node,
          debugLabel: 'TvSeekBar',
          child: widget.child,
        ),
      ),
    );
  }
}
