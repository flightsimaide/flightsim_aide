import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/settings/appearance.dart';
import '../../connection/widgets/connection_status_indicator.dart';
import '../cubit/theme_cubit.dart';
import '../cubit/theme_state.dart';
import 'color_picker_dialog.dart';
import 'theme_specimens.dart';

/// Appearance: dark, light or system; the ten colours of each theme; Restore
/// defaults, always available.
class AppearanceScreen extends StatefulWidget {
  /// Creates the page.
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  Brightness? _editing;

  @override
  Widget build(BuildContext context) {
    final editing = _editing ?? Theme.of(context).brightness;
    final cubit = context.read<ThemeCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: [
          TextButton(
            key: const Key('restore-defaults'),
            onPressed: cubit.restoreDefaults,
            child: const Text('Restore defaults'),
          ),
          const ConnectionStatusIndicator(),
        ],
      ),
      body: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, state) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Theme', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SegmentedButton<AppearanceMode>(
              key: const Key('mode-buttons'),
              segments: const [
                ButtonSegment(
                  value: AppearanceMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: AppearanceMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: AppearanceMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {state.appearance.mode},
              onSelectionChanged: (s) => cubit.setMode(s.first),
            ),
            const SizedBox(height: 24),
            Text('Colours', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            SegmentedButton<Brightness>(
              key: const Key('editing-buttons'),
              segments: const [
                ButtonSegment(value: Brightness.light, label: Text('Light')),
                ButtonSegment(value: Brightness.dark, label: Text('Dark')),
              ],
              selected: {editing},
              onSelectionChanged: (s) => setState(() => _editing = s.first),
            ),
            for (final which in ThemeColor.values)
              _ColorField(
                key: ValueKey('${editing.name}.${which.name}'),
                label: which.label,
                value: state.colorOf(editing, which),
                onPreview: (c) => cubit.previewColor(editing, which, c),
                onChanged: (c) => cubit.setColor(editing, which, c),
              ),
            const SizedBox(height: 24),
            Text('Preview', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const ThemeSpecimens(),
          ],
        ),
      ),
    );
  }
}

/// A swatch (opens the picker), a name and a hex field (`RRGGBB`) that
/// applies when valid.
class _ColorField extends StatefulWidget {
  const _ColorField({
    required this.label,
    required this.value,
    required this.onPreview,
    required this.onChanged,
    super.key,
  });

  final String label;
  final Color value;
  final ValueChanged<Color> onPreview;
  final ValueChanged<Color> onChanged;

  @override
  State<_ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<_ColorField> {
  late final TextEditingController _controller = TextEditingController(
    text: _hex(widget.value),
  );

  static String _hex(Color c) =>
      (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  @override
  void didUpdateWidget(_ColorField old) {
    super.didUpdateWidget(old);
    // Restored or previewed from elsewhere: show it, unless it is what was
    // typed.
    final typed = int.tryParse(_controller.text, radix: 16);
    if (typed == null || (0xFF000000 | typed) != widget.value.toARGB32()) {
      _controller.text = _hex(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String text) {
    if (text.length != 6) return;
    final rgb = int.tryParse(text, radix: 16);
    if (rgb != null) widget.onChanged(Color(0xFF000000 | rgb));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          InkWell(
            key: Key('swatch-${widget.label}'),
            onTap: () => showColorPickerDialog(
              context,
              title: widget.label,
              initial: widget.value,
              onChanged: widget.onPreview,
              onApplied: widget.onChanged,
            ),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.value,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.label)),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _controller,
              maxLength: 6,
              decoration: const InputDecoration(
                prefixText: '#',
                counterText: '',
                isDense: true,
              ),
              onChanged: _apply,
            ),
          ),
        ],
      ),
    );
  }
}
