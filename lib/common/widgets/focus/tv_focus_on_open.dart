import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// 弹层内容：打开之后把焦点送到里面**第一项**。
///
/// `showModalBottomSheet` / `showDialog` 都是独立路由，框架把焦点挪到
/// **弹层自己的 scope** 上就算完事（`ModalRoute` 只做 `focusScopeNode` 的交接），
/// 里面一项都没选中。表现是"菜单弹出来了，按确定没反应"——得先瞎按一下方向键
/// 才知道自己停在哪儿。
///
/// 顺带说一句框架已经做好的部分：弹层 scope 之外的东西（底下的卡片）不在这个
/// scope 的 `traversalDescendants` 里，所以面板打开期间方向键不会跑到底下去；
/// 面板关掉时框架也会把焦点还给打开它的那个控件。
///
/// 用法就是套在弹层内容外面：
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   builder: (_) => TvFocusOnOpen(child: Column(children: [...])),
/// );
/// ```
///
/// 送的是第一项而不是"上次选中的那一项"：弹层的内容各不相同，记位置没有意义。
/// 面板里第一项如果是个不能聚焦的东西（分割线、装饰），会被自动跳过——
/// `traversalDescendants` 本身就是"能停的节点"的序列。
/// `Pref.tvFocus` 关掉时什么都不做，弹层行为完全退回改动前。
class TvFocusOnOpen extends StatefulWidget {
  const TvFocusOnOpen({super.key, required this.child});

  final Widget child;

  @override
  State<TvFocusOnOpen> createState() => _TvFocusOnOpenState();
}

class _TvFocusOnOpenState extends State<TvFocusOnOpen> {
  FocusScopeNode? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 弹层里的第一个 Focus 祖先是路由自己的 scope
    // （用 `FocusScope.of`：`Focus.of` 不允许拿到 scope 本身）
    _scope = FocusScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    if (!Pref.tvFocus) return;
    // 等第一帧：懒加载的列表项得先建出来才找得到
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nodes = _scope?.traversalDescendants;
      if (nodes == null || nodes.isEmpty) return;
      nodes.first.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 同上，但给**不走路由**的弹层用（`SmartDialog.show` 这类）。
///
/// 路由弹层（`showDialog` / `showModalBottomSheet`）有自己的 `FocusScope`，
/// 里面的焦点怎么走都不影响底下那页。`SmartDialog` 只是往 overlay 里插一层
/// 控件，和页面**共用同一个 scope**，于是有两件事不对：
///
/// 1. 焦点还停在打开它的那张卡片上，方向键就在底下那页里转，弹层像张画；
/// 2. `TvFocusOnOpen` 送焦点的目标是"当前 scope 的第一项"——这里会送到
///    底下那页的第一张卡片上去，等于没送。
///
/// 所以这里先立一个自己的 [FocusScope]（`autofocus` 会直接把焦点落到
/// 里面第一项上），把弹层和页面隔开，再把"第一项"这件事交给 [TvFocusOnOpen]
/// 兜底（比如弹层里第一帧还没建出可聚焦项的情况）。
/// `Pref.tvFocus` 关掉时什么都不做。
class TvOverlayScope extends StatelessWidget {
  const TvOverlayScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Pref.tvFocus) return child;
    return FocusScope(autofocus: true, child: TvFocusOnOpen(child: child));
  }
}
