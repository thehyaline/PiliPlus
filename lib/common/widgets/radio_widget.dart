import 'package:PiliPlus/common/widgets/focus/tv_radio_tile.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:material_ui/material_ui.dart';

class RadioWidget<T> extends StatefulWidget {
  final T value;
  final String title;
  final bool tristate;
  final EdgeInsetsGeometry? padding;
  final MainAxisSize mainAxisSize;

  /// 手柄方向键认哪几个方向。
  ///
  /// 默认四向都走（[WrapRadioOptionsGroup] 的 `Wrap` 排布横向真有邻居）；
  /// 自己把 [RadioWidget] 摆成竖排（`Column`）的调用方传
  /// [TvRadioAxis.vertical]，左右键就地吃掉不移动。
  final TvRadioAxis axis;

  const RadioWidget({
    super.key,
    required this.value,
    required this.title,
    this.tristate = false,
    this.padding,
    this.mainAxisSize = MainAxisSize.min,
    this.axis = TvRadioAxis.all,
  });

  @override
  State<RadioWidget<T>> createState() => RadioWidgetState<T>();
}

class RadioWidgetState<T> extends State<RadioWidget<T>> with RadioClient<T> {
  late final _RadioRegistry<T> _radioRegistry = _RadioRegistry<T>(this);

  @override
  final focusNode = FocusNode();

  @override
  T get radioValue => widget.value;

  bool get checked => radioValue == registry!.groupValue;

  @override
  bool get tristate => widget.tristate;

  @override
  bool get enabled => registry != null;

  @override
  void dispose() {
    registry = null;
    focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    registry = RadioGroup.maybeOf(context);
    assert(registry != null);
  }

  void _handleTap() {
    if (checked) {
      if (tristate) registry!.onChanged(null);
      return;
    }
    registry!.onChanged(radioValue);
  }

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: widget.mainAxisSize,
      children: [
        ExcludeFocus(
          child: Radio<T>(
            value: radioValue,
            groupRegistry: _radioRegistry,
            materialTapTargetSize: PlatformUtils.isDesktop
                ? .padded
                : .shrinkWrap,
          ),
        ),
        Text(widget.title),
      ],
    );
    // 手柄那条路交给 `tvRadioTile`（方向键只移动、确定键才选中，见它的文档）；
    // 触摸 / 鼠标还是原来那个 `onTap`。节点身份必须保留——它同时是
    // `RadioClient.focusNode`，`RadioGroup` 靠它认这一项。
    return tvRadioTile<T>(
      debugLabel: '单选',
      value: radioValue,
      toggleable: widget.tristate,
      // `Wrap` 排布：横向真有邻居（竖排的调用方自己传 [TvRadioAxis.vertical]）
      axis: widget.axis,
      focusNode: focusNode,
      builder: (focusNode) => InkWell(
        onTap: _handleTap,
        focusNode: focusNode,
        child: widget.padding == null
            ? child
            : Padding(padding: widget.padding!, child: child),
      ),
    );
  }
}

class WrapRadioOptionsGroup<T> extends StatelessWidget {
  final String groupTitle;
  final Map<T, String> options;
  final EdgeInsetsGeometry? itemPadding;

  const WrapRadioOptionsGroup({
    super.key,
    required this.groupTitle,
    required this.options,
    this.itemPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (groupTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              groupTitle,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            children: options.entries.map((entry) {
              return RadioWidget<T>(
                value: entry.key,
                title: entry.value,
                padding: itemPadding ?? const EdgeInsets.only(right: 10),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// A registry to controls internal [Radio] and hides it from [RadioGroup]
/// ancestor.
///
/// [RadioListTile] implements the [RadioClient] directly to register to
/// [RadioGroup] ancestor. Therefore, it has to hide the internal [Radio] from
/// participate in the [RadioGroup] ancestor.
class _RadioRegistry<T> extends RadioGroupRegistry<T> {
  _RadioRegistry(this.state);

  final RadioWidgetState<T> state;

  @override
  T? get groupValue => state.registry!.groupValue;

  @override
  ValueChanged<T?> get onChanged => state.registry!.onChanged;

  @override
  void registerClient(RadioClient<T> radio) {}

  @override
  void unregisterClient(RadioClient<T> radio) {}
}
