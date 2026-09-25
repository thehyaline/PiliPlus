import 'package:PiliPlus/common/widgets/focus/focus_ring.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:PiliPlus/utils/tv_focus.dart';
import 'package:PiliPlus/utils/tv_keys.dart';
import 'package:flutter/services.dart' show KeyEvent, LogicalKeyboardKey;
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
/// - ↑/↓：不拦，交给几何寻焦去别处（手柄播放器模型下就是"上下切换焦点"）。
///
/// 焦点离开时会把没提交的微调先提交掉，免得"按了 B 直接收控制条"时停在
/// `isSeeking` 状态上——那会让控制条再也不自动隐藏。
///
/// `builder` 拿到的 `focused` 是**预选框真的画出来的时候**（触摸时是 false），
/// 手柄播放器模型靠它把预选框挪到进度指示器上（`ProgressBar.thumbFocusRing`）。
///
/// `builder` 是**懒构建**的：它在 `TvSeekBar` 自己的 build 里（也就是这条子树
/// 更下面、另一个 build 过程）才被调用。所以需要跟着 Rx 变的内容——进度条的
/// 位置、缓冲、时长——必须在 `builder` **里面**自己包一层 `Obx`；写在 `builder`
/// 外面（比如拿它当 `Obx` 的返回值）时 GetX 读不到任何订阅，会抛
/// "improper use of a GetX"。
///
/// `Pref.tvFocus` 关掉时原样返回 builder 的内容（鼠标拖动照旧）。
class TvSeekBar extends StatefulWidget {
  const TvSeekBar({
    super.key,
    required this.host,
    required this.builder,
    this.focusOnThumb = false,
  });

  final TvSeekBarHost host;

  /// 进度条本身。`focused` 为真表示"焦点停在这条时间线上、并且预选框可见"。
  final Widget Function(BuildContext context, bool focused) builder;

  /// 预选框画在**进度指示器**上（手柄播放器模型）。
  ///
  /// 此时焦点只有"当前进度"这一个落点，整条进度条的描边就不画了：
  /// 两个框同时出现会让人以为这里有两个能停的地方。
  final bool focusOnThumb;

  @override
  State<TvSeekBar> createState() => _TvSeekBarState();
}

class _TvSeekBarState extends State<TvSeekBar> {
  late final FocusNode _node = FocusNode(debugLabel: 'TvSeekBar');
  bool _adjusting = false;
  bool _focused = false;

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
      return widget.builder(context, false);
    }
    return FocusRing(
      focusNode: _node,
      debugLabel: 'TvSeekBar',
      radius: TvFocusSpec.playerRadius,
      // 进度条是整宽的，缩放会顶出视口：只靠描边表示"停在这条时间线上"；
      // 焦点在进度指示器上时连描边也不要，那一圈由进度条自己画在 thumb 上
      borderWidth: widget.focusOnThumb && _focused
          ? 0
          : TvFocusSpec.playerBorderWidth,
      scale: 1.0,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) {
        if (!focused) _commit();
        if (widget.focusOnThumb && focused != _focused) {
          setState(() => _focused = focused);
        }
      },
      builder: (context, node, focused) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Focus(
          focusNode: node,
          debugLabel: 'TvSeekBar',
          child: widget.builder(context, focused),
        ),
      ),
    );
  }
}
