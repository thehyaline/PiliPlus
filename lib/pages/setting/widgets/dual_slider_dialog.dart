import 'package:PiliPlus/utils/extension/num_ext.dart';
import 'package:material_ui/material_ui.dart';

/// 单个滑块项的配置
class SliderConfig {
  const SliderConfig({required this.description, required this.value});

  final Widget description;
  final double value;
}

/// 多滑块对话框：滑块数量由 [sliders] 决定，确定后返回各滑块的值列表
class DualSliderDialog extends StatefulWidget {
  final List<SliderConfig> sliders;
  final Widget title;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final int precise;

  const DualSliderDialog({
    super.key,
    required this.sliders,
    required this.title,
    required this.min,
    required this.max,
    this.divisions,
    this.suffix = '',
    this.precise = 1,
  });

  @override
  State<DualSliderDialog> createState() => _DualSliderDialogState();
}

class _DualSliderDialogState extends State<DualSliderDialog> {
  late final List<double> _tempValues;

  @override
  void initState() {
    super.initState();
    _tempValues = widget.sliders.map((e) => e.value).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.title,
      contentPadding: const EdgeInsets.only(
        top: 20,
        left: 8,
        right: 8,
        bottom: 8,
      ),
      content: Column(
        mainAxisSize: .min,
        children: [
          for (var i = 0; i < widget.sliders.length; i++) ...[
            widget.sliders[i].description,
            Builder(
              builder: (context) {
                return Slider(
                  value: _tempValues[i],
                  min: widget.min,
                  max: widget.max,
                  divisions: widget.divisions,
                  label:
                      '${_tempValues[i].toStringAsFixed(widget.precise)}${widget.suffix}',
                  onChanged: (double value) {
                    _tempValues[i] = value.toPrecision(widget.precise);
                    (context as Element).markNeedsBuild();
                  },
                );
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: Text(
            '取消',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        TextButton(
          // 注意：List.unmodifiable 的工厂签名是 raw Iterable，推断结果恒为
          // List<dynamic>，与 showDialog<List<double>> 的路由期望类型不匹配，
          // debug 下 pop 会抛断言异常导致弹窗无法关闭。必须显式指定泛型。
          onPressed: () => Navigator.pop(
            context,
            List<double>.unmodifiable(_tempValues),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
