import 'dart:async' show Completer;

import 'package:PiliPlus/common/widgets/focus/tv_focus_on_open.dart';
import 'package:PiliPlus/common/widgets/focus/tv_focus_return.dart';
import 'package:PiliPlus/common/widgets/scaffold/bottom_sheet.dart';
import 'package:PiliPlus/common/widgets/scaffold/bottom_sheet_layout.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:material_ui/material_ui.dart';

class MiniScaffold extends StatefulWidget {
  const MiniScaffold({
    super.key,
    required this.body,
  });

  final Widget body;

  static MiniScaffoldState of(BuildContext context) {
    return context.findAncestorStateOfType<MiniScaffoldState>()!;
  }

  static MiniScaffoldState? maybeOf(BuildContext context) {
    return context.findAncestorStateOfType<MiniScaffoldState>();
  }

  @override
  State<MiniScaffold> createState() => MiniScaffoldState();
}

class MiniScaffoldState extends State<MiniScaffold>
    with TickerProviderStateMixin {
  PersistentBottomSheetController? _currentBottomSheet;

  /// 面板所在的路由（面板不是路由，是这条路由里的一条 local history entry）。
  /// 关掉面板之后要把焦点还给这一层上"打开面板时待着的地方"。
  Route<dynamic>? _route;

  void _closeCurrentBottomSheet() {
    if (_currentBottomSheet != null) {
      if (!_currentBottomSheet!.isLocalHistoryEntry) {
        _currentBottomSheet!.close();
      }
      assert(() {
        _currentBottomSheet?.completer.future.whenComplete(() {
          assert(_currentBottomSheet == null);
        });
        return true;
      }());
    }
  }

  /// 面板关掉之后把焦点还给"打开面板时待着的那个控件"。
  ///
  /// 面板和页面**共用同一个 scope**，框架不会替我们恢复——它只在路由被拆掉的
  /// 时候做这件事。所以要自己还：等下一帧（那一帧面板才真的从树上下去，
  /// 现在送焦点会被面板自己抢掉），而且得确认没有新面板开着。
  void _restoreFocus() {
    final route = _route;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _currentBottomSheet != null) return;
      TvFocusReturn.restore(route);
    });
  }

  PersistentBottomSheetController _buildBottomSheet(
    WidgetBuilder builder, {
    required AnimationController animationController,
    BoxConstraints? constraints,
    bool? enableDrag,
    bool shouldDisposeAnimationController = true,
  }) {
    final completer = Completer<void>();
    final bottomSheetKey = GlobalKey<StandardBottomSheetState>();
    late StandardBottomSheet bottomSheet;

    var removedEntry = false;
    var doingDispose = false;

    void removeCurrentBottomSheet() {
      removedEntry = true;
      if (_currentBottomSheet == null) {
        return;
      }
      assert(_currentBottomSheet!.widget == bottomSheet);
      assert(bottomSheetKey.currentState != null);

      bottomSheetKey.currentState!.close();

      completer.complete();
    }

    final LocalHistoryEntry entry = LocalHistoryEntry(
      onRemove: () {
        if (!removedEntry &&
            _currentBottomSheet?.widget == bottomSheet &&
            !doingDispose) {
          removeCurrentBottomSheet();
        }
      },
    );

    void removeEntryIfNeeded() {
      if (!removedEntry) {
        entry.remove();
        removedEntry = true;
      }
    }

    bottomSheet = _StandardBottomSheet(
      key: bottomSheetKey,
      animationController: animationController,
      enableDrag: enableDrag ?? true,
      onClosing: () {
        if (_currentBottomSheet == null) {
          return;
        }
        assert(_currentBottomSheet!.widget == bottomSheet);
        removeEntryIfNeeded();
      },
      onDismissed: () {
        if (bottomSheet == _currentBottomSheet?.widget) {
          _currentBottomSheet = null;
          if (mounted) {
            setState(() {});
          }
        }
        _restoreFocus();
      },
      onDispose: () {
        doingDispose = true;
        removeEntryIfNeeded();
        if (shouldDisposeAnimationController) {
          animationController.dispose();
        }
      },
      builder: builder,
      isPersistent: false,
      constraints: constraints,
    );

    // 面板是往**当前路由**里插的一条 local history entry（不是新路由）。
    // 优先问 `ModalRoute.of`：`Get.routing.route` 是 GetX 自己记的"当前路由"，
    // 有弹层叠着的时候不一定指得准。
    (ModalRoute.of(context) ?? Get.routing.route! as ModalRoute)
        .addLocalHistoryEntry(entry);

    return PersistentBottomSheetController(
      bottomSheet,
      completer,
      entry.remove,
      (VoidCallback fn) {
        bottomSheetKey.currentState?.setState(fn);
      },
      true,
    );
  }

  PersistentBottomSheetController showBottomSheet(
    WidgetBuilder builder, {
    BoxConstraints? constraints,
    bool? enableDrag,
    AnimationController? transitionAnimationController,
    AnimationStyle? sheetAnimationStyle,
  }) {
    _closeCurrentBottomSheet();
    // 打开面板前记下焦点在哪张卡上：面板关掉时还给它（见 [_restoreFocus]）
    _route = ModalRoute.of(context);
    TvFocusReturn.remember(_route);
    final AnimationController controller =
        (transitionAnimationController ??
              BottomSheet.createAnimationController(
                this,
                sheetAnimationStyle: sheetAnimationStyle,
              ))
          ..forward();
    setState(() {
      _currentBottomSheet = _buildBottomSheet(
        // 面板自己立一个 scope（[TvPanelScope]）：不立的话它和页面共用一个
        // scope，焦点还停在底下的卡片上，方向键就在底下那页里转，看着像张画
        (context) => TvPanelScope(child: builder(context)),
        animationController: controller,
        constraints: constraints,
        enableDrag: enableDrag,
        shouldDisposeAnimationController: transitionAnimationController == null,
      );
    });
    return _currentBottomSheet!;
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetLayout(
      body: widget.body,
      bottomSheet: _currentBottomSheet?.widget,
    );
  }
}

class _StandardBottomSheet extends StandardBottomSheet {
  const _StandardBottomSheet({
    super.key,
    required super.animationController,
    super.enableDrag,
    required super.onClosing,
    required super.onDismissed,
    required super.builder,
    super.isPersistent,
    super.constraints,
    super.onDispose,
  });

  @override
  StandardBottomSheetState createState() => _StandardBottomSheetState();
}

class _StandardBottomSheetState extends StandardBottomSheetState {
  @override
  Widget build(BuildContext context) {
    final child = BottomSheet_(
      animationController: widget.animationController,
      enableDrag: widget.enableDrag,
      onDragStart: handleDragStart,
      onDragEnd: handleDragEnd,
      onClosing: widget.onClosing!,
      builder: widget.builder,
      constraints: widget.constraints,
    );
    if (widget.enableDrag) {
      return AnimatedBuilder(
        animation: widget.animationController,
        builder: (context, child) => Align(
          alignment: AlignmentDirectional.topStart,
          heightFactor: animationCurve.transform(
            widget.animationController.value,
          ),
          child: child,
        ),
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: widget.animationController,
      builder: (context, child) => Opacity(
        opacity: widget.animationController.value,
        child: child,
      ),
      child: child,
    );
  }
}
