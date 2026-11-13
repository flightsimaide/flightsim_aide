import 'package:flutter/material.dart';

/// Opens a small colour picker (hue, saturation, brightness and a hex field).
///
/// [onChanged] is called live while the user drags, so the page behind shows
/// the result (the barrier is transparent). Apply calls [onApplied] with the
/// final colour; Cancel calls [onChanged] with [initial] to put it back.
Future<void> showColorPickerDialog(
  BuildContext context, {
  required String title,
  required Color initial,
  required ValueChanged<Color> onChanged,
  required ValueChanged<Color> onApplied,
}) async {
  final applied = await showDialog<Color>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (_) => _ColorPickerDialog(
      title: title,
      initial: initial,
      onChanged: onChanged,
    ),
  );
  if (applied != null) {
    onApplied(applied);
  } else {
    onChanged(initial);
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initial,
    required this.onChanged,
  });

  final String title;
  final Color initial;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(widget.initial),
  );

  static String _hexOf(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    final color = hsv.toColor();
    _hex.text = _hexOf(color);
    widget.onChanged(color);
  }

  void _typed(String text) {
    final rgb = text.length == 6 ? int.tryParse(text, radix: 16) : null;
    if (rgb == null) return;
    final color = Color(0xFF000000 | rgb);
    setState(() => _hsv = HSVColor.fromColor(color));
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: color,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            _Slider(
              label: 'Hue',
              value: _hsv.hue,
              max: 360,
              onChanged: (v) => _set(_hsv.withHue(v)),
            ),
            _Slider(
              label: 'Saturation',
              value: _hsv.saturation,
              max: 1,
              onChanged: (v) => _set(_hsv.withSaturation(v)),
            ),
            _Slider(
              label: 'Brightness',
              value: _hsv.value,
              max: 1,
              onChanged: (v) => _set(_hsv.withValue(v)),
            ),
            TextField(
              controller: _hex,
              maxLength: 6,
              decoration: const InputDecoration(
                prefixText: '#',
                counterText: '',
                labelText: 'Hex',
              ),
              onChanged: _typed,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _hsv.toColor()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
