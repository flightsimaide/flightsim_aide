import 'package:flutter/material.dart';

import '../../core/themes/status_colors.dart';

/// One labelled specimen: the widget's name, the colours it takes, the widget.
class _Specimen extends StatelessWidget {
  const _Specimen(this.name, this.uses, this.child);

  final String name;
  final String uses;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: name, style: theme.textTheme.titleSmall),
                TextSpan(
                  text: '   uses: $uses',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Every widget the theme styles, each labelled with its name and the colours
/// it takes, so a colour change can be seen on all of them.
class ThemeSpecimens extends StatefulWidget {
  /// Creates the specimens.
  const ThemeSpecimens({super.key});

  @override
  State<ThemeSpecimens> createState() => _ThemeSpecimensState();
}

class _ThemeSpecimensState extends State<ThemeSpecimens> {
  bool _checked = true;
  bool _switched = true;
  int _nav = 0;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).extension<StatusColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Specimen(
          'Page / Scaffold',
          'background',
          Container(
            height: 40,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: const Text('body text on the page'),
          ),
        ),
        _Specimen(
          'AppBar',
          'background, text',
          AppBar(title: const Text('Title'), actions: const [Icon(Icons.menu)]),
        ),
        const _Specimen(
          'Card',
          'surface, text, mutedText',
          Card(
            child: ListTile(
              title: Text('Card title'),
              subtitle: Text('Secondary line (mutedText)'),
            ),
          ),
        ),
        _Specimen(
          'ListTile (checklist row)',
          'surface, text, accent',
          Card(
            child: CheckboxListTile(
              value: _checked,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: const Text('BATTERY .............. ON'),
            ),
          ),
        ),
        _Specimen(
          'FilledButton',
          'accent, text on accent',
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Reload')),
              const FilledButton(onPressed: null, child: Text('Disabled')),
            ],
          ),
        ),
        _Specimen(
          'OutlinedButton',
          'accent, outline',
          OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
        ),
        _Specimen(
          'TextButton',
          'accent',
          TextButton(onPressed: () {}, child: const Text('Retry')),
        ),
        const _Specimen(
          'TextField',
          'surface, outline, accent, mutedText',
          SizedBox(
            width: 280,
            child: TextField(
              decoration: InputDecoration(
                labelText: 'IP address',
                hintText: '192.168.1.10',
              ),
            ),
          ),
        ),
        _Specimen(
          'Switch',
          'accent, outline',
          Switch(
            value: _switched,
            onChanged: (v) => setState(() => _switched = v),
          ),
        ),
        const _Specimen(
          'Chip',
          'surface, outline, text',
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('Preflight')),
              Chip(label: Text('Taxi')),
            ],
          ),
        ),
        const _Specimen('Divider', 'outline', Divider()),
        _Specimen(
          'AlertDialog',
          'surface, text, accent',
          Builder(
            builder: (context) => FilledButton.tonal(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Reset progress?'),
                  content: const Text('This clears every tick.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
              child: const Text('Open dialog'),
            ),
          ),
        ),
        _Specimen(
          'SnackBar',
          'text (inverse surface)',
          Builder(
            builder: (context) => FilledButton.tonal(
              onPressed: () =>
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Saved'))),
              child: const Text('Show snackbar'),
            ),
          ),
        ),
        _Specimen(
          'NavigationBar',
          'surface, accent (selected), text, mutedText',
          NavigationBar(
            selectedIndex: _nav,
            onDestinationSelected: (i) => setState(() => _nav = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(
                icon: Icon(Icons.checklist),
                label: 'Lists',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
        _Specimen(
          'Status icons',
          'success, caution, error, info (each with an icon)',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  status.successIcon,
                  const SizedBox(width: 8),
                  const Text('Good: the data agrees'),
                ],
              ),
              Row(
                children: [
                  status.cautionIcon,
                  const SizedBox(width: 8),
                  const Text('Caution: item skipped'),
                ],
              ),
              Row(
                children: [
                  status.errorIcon,
                  const SizedBox(width: 8),
                  const Text('Warning: the data disagrees'),
                ],
              ),
              Row(
                children: [
                  status.infoIcon,
                  const SizedBox(width: 8),
                  const Text('Information: Auto / Manual mode'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
