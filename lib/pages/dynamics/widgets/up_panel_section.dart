import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/dynamic/live_panel_position.dart';
import 'package:PiliPlus/models/common/dynamic/up_panel_position.dart';
import 'package:PiliPlus/models/dynamics/up.dart';
import 'package:PiliPlus/pages/dynamics/controller.dart';
import 'package:PiliPlus/pages/dynamics/widgets/up_panel.dart';
import 'package:PiliPlus/utils/extension/context_ext.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// UP主栏区域：顶部模式下横向滚动、左右/抽屉模式下竖向固定。
/// 被动态页固定模式与动态列表（UP主栏随页面滚动）复用
class UpPanelSection extends StatelessWidget {
  const UpPanelSection({super.key, required this.dynamicsController});

  final DynamicsController dynamicsController;

  @override
  Widget build(BuildContext context) {
    final upPanelPosition = dynamicsController.upPanelPosition;
    final isTop = upPanelPosition == UpPanelPosition.top;
    final needBg = upPanelPosition.index > 2;
    return Material(
      type: needBg ? MaterialType.canvas : MaterialType.transparency,
      color: needBg ? Theme.of(context).colorScheme.surface : null,
      child: SizedBox(
        width: isTop ? null : 72,
        height: isTop ? Style.upPanelTopHeight : null,
        child: NotificationListener<ScrollEndNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 300) {
              dynamicsController.onLoadMore();
            }
            return false;
          },
          child: Obx(() {
            final showLive =
                dynamicsController.livePanelPosition.value !=
                    LivePanelPosition.hidden &&
                context.showNavbar;
            return _buildUpPanel(
              dynamicsController.loadingState.value,
              // 分离直播栏开启且位于顶部时，直播列表从 UP主栏移出
              showLiveSection:
                  !showLive && !(isTop && Pref.separateTopLiveBar),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildUpPanel(
    LoadingState<FollowUpModel> loadingState, {
    required bool showLiveSection,
  }) {
    return switch (loadingState) {
      Loading() => const SizedBox.shrink(),
      Success(:final response) => UpPanel(
          upData: response,
          dynamicsController: dynamicsController,
          showLiveSection: showLiveSection,
        ),
      Error() => Center(
          child: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: dynamicsController.onReload,
          ),
        ),
    };
  }
}
