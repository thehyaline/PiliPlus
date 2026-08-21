import 'package:material_ui/material_ui.dart';

/// 封面底部信息条：渐变阴影 + 左下/右下两个信息插槽。
///
/// 渐变与直播间播放器操作栏一致（见 pl_player/widgets/app_bar_ani.dart），
/// 视频卡片、直播卡片共用，保证封面上的文字统一为白字 12 号。
class CoverBottomInfo extends StatelessWidget {
  final Widget? left;
  final Widget? right;

  const CoverBottomInfo({super.key, this.left, this.right});

  static const _gradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  /// 封面信息文字的统一样式（白字 12 号）
  static TextStyle textStyle() =>
      const TextStyle(fontSize: 12, color: Colors.white);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.only(top: 26, left: 8, right: 8, bottom: 6),
        decoration: const BoxDecoration(gradient: _gradient),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            left ?? const SizedBox.shrink(),
            right ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
