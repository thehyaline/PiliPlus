import 'dart:math' show max;

import 'package:PiliPlus/common/widgets/focus/tv_focus_on_open.dart';
import 'package:PiliPlus/common/widgets/gesture/horizontal_drag_gesture_recognizer.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/gestures.dart' show HorizontalDragGestureRecognizer;
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

abstract class CommonSlidePage extends StatefulWidget {
  const CommonSlidePage({super.key, this.enableSlide = true});

  final bool enableSlide;
}

mixin CommonSlideMixin<T extends CommonSlidePage> on State<T>, TickerProvider {
  static const double offset = 30.0;
  double? _downDx;
  late double _maxWidth;
  double get maxWidth => _maxWidth;
  late bool _isRTL = false;
  late final bool enableSlide;
  late final AnimationController _animController;
  SlideDragGestureRecognizer? _slideDragGestureRecognizer;

  static bool slideDismissReplyPage = Pref.slideDismissReplyPage;

  bool isDxAllowed(double dx) {
    return enableSlide
        ? dx > CommonSlideMixin.offset &&
              dx < maxWidth - CommonSlideMixin.offset
        : true;
  }

  TabBarDragGestureRecognizer horizontalDragGestureRecognizer() {
    return TabBarDragGestureRecognizer(isDxAllowed: isDxAllowed);
  }

  @override
  void initState() {
    super.initState();
    enableSlide = widget.enableSlide && slideDismissReplyPage;
    if (enableSlide) {
      _animController = AnimationController(
        vsync: this,
        reverseDuration: const Duration(milliseconds: 500),
      );
      _slideDragGestureRecognizer =
          SlideDragGestureRecognizer(
              isDxAllowed: (double dx) {
                final isLTR = dx <= offset;
                final isRTL = dx >= _maxWidth - offset;
                if (isLTR || isRTL) {
                  _isRTL = isRTL;
                  return true;
                }
                return false;
              },
            )
            ..onStart = _onDragStart
            ..onUpdate = _onDragUpdate
            ..onEnd = _onDragEnd
            ..onCancel = _onDragEnd;
    }
  }

  @override
  void dispose() {
    if (enableSlide) {
      _animController.dispose();
      _slideDragGestureRecognizer?.dispose();
      _slideDragGestureRecognizer = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 面板是"盖在视频页上的一层"，焦点要么自己送进来，要么就停在底下那页的
    // 按钮上（手柄"点开了却选不了"）。`PublishRoute` 那边已经包了一层，这里再
    // 兜一次底：这套面板不从 `PublishRoute` 进来的时候也照样能用。
    // 重复套不冲突——两次都是"送到这一层 scope 的第一项"，目标一致；
    // `Pref.tvFocus` 关掉时 `TvFocusOnOpen` 是空操作。
    final page = TvFocusOnOpen(child: buildPage(theme));
    if (!enableSlide) return page;
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxWidth = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return Align(
              alignment: AlignmentDirectional.topStart,
              heightFactor: 1 - _animController.value,
              child: child,
            );
          },
          child: page,
        );
      },
    );
  }

  Widget buildPage(ThemeData theme);

  Widget buildList(ThemeData theme) => throw UnimplementedError();

  void _onDragEnd([_]) {
    if (_downDx == null) return;
    final dx = _downDx!;
    if (_animController.value * _maxWidth + (_isRTL ? (_maxWidth - dx) : dx) >=
        100) {
      Get.back();
    } else {
      _animController.reverse();
    }
    _downDx = null;
  }

  void _onDragStart(DragStartDetails details) {
    _downDx = details.localPosition.dx;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final from = _downDx!;
    final to = details.localPosition.dx;
    _animController.value = max(0, _isRTL ? from - to : to - from) / _maxWidth;
  }

  Widget slideList(ThemeData theme) => Listener(
    onPointerDown: (event) => _slideDragGestureRecognizer?.addPointer(event),
    child: buildList(theme),
  );
}

typedef IsDxAllowed = bool Function(double dx);

class SlideDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  SlideDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    required this.isDxAllowed,
  });

  final IsDxAllowed isDxAllowed;

  @override
  bool isPointerAllowed(PointerEvent event) {
    return isDxAllowed(event.localPosition.dx) && super.isPointerAllowed(event);
  }
}

class TabBarDragGestureRecognizer
    extends CustomHorizontalDragGestureRecognizer {
  TabBarDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
    required this.isDxAllowed,
  });

  final IsDxAllowed isDxAllowed;

  @override
  bool isPointerAllowed(PointerEvent event) {
    return isDxAllowed(event.localPosition.dx) && super.isPointerAllowed(event);
  }
}
