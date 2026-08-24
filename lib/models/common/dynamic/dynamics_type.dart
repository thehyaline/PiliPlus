enum DynamicsTabType {
  all('全部'),
  video('视频'),
  pgc('番剧'),
  article('专栏'),
  up('UP'),
  ;

  final String label;
  const DynamicsTabType(this.label);

  /// 动态页实际展示的选项卡（其余类型仅保留用于数据层/API 兼容）
  static const visibleValues = [all, video];
}
