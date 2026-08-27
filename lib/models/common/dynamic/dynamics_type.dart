import 'package:PiliPlus/models/common/enum_with_label.dart';

enum DynamicsTabType implements EnumWithLabel {
  all('全部'),
  video('视频'),
  pgc('番剧'),
  article('专栏'),
  up('UP'),
  ;

  @override
  final String label;
  const DynamicsTabType(this.label);

  /// 动态页实际展示的选项卡（其余类型仅保留用于数据层/API 兼容）
  static const visibleValues = [all, video];
}
