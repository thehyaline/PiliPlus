import 'package:PiliPlus/common/widgets/focus/tv_focus_memory.dart';
import 'package:PiliPlus/common/widgets/loading_widget/http_error.dart';
import 'package:PiliPlus/common/widgets/video_card/video_card_h.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/model_hot_video_item.dart';
import 'package:PiliPlus/pages/video/related/controller.dart';
import 'package:PiliPlus/utils/extension/get_ext.dart';
import 'package:PiliPlus/utils/grid.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class RelatedVideoPanel extends StatefulWidget {
  const RelatedVideoPanel({super.key, required this.heroTag});
  final String heroTag;
  @override
  State<RelatedVideoPanel> createState() => _RelatedVideoPanelState();
}

class _RelatedVideoPanelState extends State<RelatedVideoPanel> with GridMixin {
  late final RelatedController _relatedController;

  @override
  void initState() {
    super.initState();
    _relatedController = Get.putOrFind(
      RelatedController.new,
      tag: widget.heroTag,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: 7, bottom: 100),
      sliver: Obx(() => _buildBody(_relatedController.loadingState.value)),
    );
  }

  Widget _buildBody(LoadingState<List<HotVideoItemModel>?> loadingState) {
    return switch (loadingState) {
      Loading() => gridSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  return VideoCardH(
                    videoItem: response[index],
                    onRemove: () {
                      // 删掉的正好是焦点所在的那张卡时焦点会掉到区域 scope 上
                      // （方向键无处可去），park/restore 让它落到接替位置的卡上
                      TvFocusMemory.park();
                      _relatedController.loadingState
                        ..value.data!.removeAt(index)
                        ..refresh();
                      TvFocusMemory.restore(preferIndex: index);
                    },
                  );
                },
                itemCount: response.length,
              )
            : const SliverToBoxAdapter(),
      Error(:final errMsg) => HttpError(
        errMsg: errMsg,
        onReload: _relatedController.onReload,
      ),
    };
  }
}
