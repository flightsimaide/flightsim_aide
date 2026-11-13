import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../utils/ipv4.dart';
import '../cubit/connection_cubit.dart';
import '../cubit/known_address.dart';

/// What the user chose in the [ManualIpDialog].
sealed class ManualIpChoice {
  const ManualIpChoice();
}

/// Try this address.
final class ManualIpTry extends ManualIpChoice {
  /// Creates the choice.
  const ManualIpTry(this.address);

  /// The trimmed, valid address.
  final String address;
}

/// Go back to automatic discovery.
final class ManualIpClear extends ManualIpChoice {
  /// Creates the choice.
  const ManualIpClear();
}

/// Asks for the simulator's IPv4 address: a text box that lists the known
/// addresses when tapped and hides the list while the user types. Try is enabled only while the text is a usable
/// address; Erase saved IP is enabled only while an address is saved, and
/// returns to automatic discovery.
class ManualIpDialog extends StatefulWidget {
  /// Creates the dialog. [initial] is the saved address (pre-filled) and
  /// [known] the addresses to list.
  const ManualIpDialog({
    this.initial,
    this.known = const [],
    this.current,
    this.computerName,
    super.key,
  });

  /// The name of the computer X-Plane runs on, shown in the title, or null.
  final String? computerName;

  /// The address saved earlier, or null.
  final String? initial;

  /// The addresses to list, each with what is known about it.
  final List<KnownAddress> known;

  /// The address X-Plane is being reached at, shown in the title, or null.
  final String? current;

  @override
  State<ManualIpDialog> createState() => _ManualIpDialogState();
}

class _ManualIpDialogState extends State<ManualIpDialog> {
  /// With one address or none to pick from, a text box starts with the first
  /// three numbers of the first known address: on a local network only the
  /// last number is likely to differ.
  late final String _prefix = _networkPrefix(
    widget.known.isEmpty ? null : widget.known.first.address,
  );

  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? (_useList ? '' : _prefix),
  )..addListener(() => setState(() {}));

  bool get _useList => widget.known.length > 1;

  static String _networkPrefix(String? address) {
    if (address == null) return '';
    final parts = address.split('.');
    return parts.length == 4 ? '${parts.take(3).join('.')}.' : '';
  }

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _text => _controller.text.trim();

  /// The computer's name when the beacon gave one, else its address, else the
  /// plain question.
  String get _title {
    final name = widget.computerName;
    final address = widget.current;
    if (address == null) {
      return name == null || name.isEmpty
          ? 'X-Plane IP address'
          : 'X-Plane connected to $name';
    }
    return name == null || name.isEmpty
        ? 'X-Plane on IP $address'
        : 'X-Plane connected to $name on IP $address';
  }

  final MenuController _menu = MenuController();

  /// With exactly one known address there is no list to open, so what is known
  /// about it is written above the box; a tap puts the address in the box.
  /// Nothing is shown for the example address.
  Widget? _knownNote(BuildContext context) {
    if (widget.known.length != 1) return null;
    final known = widget.known.single;
    if (known.description == 'example') return null;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        key: const Key('known-computer'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.computer),
        title: Text(known.address),
        subtitle: Text(known.description, style: theme.textTheme.bodySmall),
        onTap: () => _controller
          ..text = known.address
          ..selection = TextSelection.collapsed(offset: known.address.length),
      ),
    );
  }

  /// The text box. With several known addresses, tapping it (or its arrow)
  /// opens their list; the list closes as soon as the user types, so it never
  /// covers the buttons.
  Widget _box(BuildContext context, bool showError) {
    final field = TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onTap: _useList ? _menu.open : null,
      onChanged: _useList ? (_) => _menu.close() : null,
      decoration: InputDecoration(
        labelText: 'IP address',
        hintText: exampleAddress,
        errorText: showError ? 'Enter four numbers like $exampleAddress' : null,
        suffixIcon: _useList
            ? IconButton(
                tooltip: 'Known addresses',
                icon: const Icon(Icons.arrow_drop_down),
                onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
              )
            : null,
      ),
    );
    if (!_useList) return field;
    return MenuAnchor(
      controller: _menu,
      crossAxisUnconstrained: false,
      style: const MenuStyle(
        maximumSize: WidgetStatePropertyAll(Size(320, 280)),
      ),
      menuChildren: [
        for (final known in widget.known)
          MenuItemButton(
            onPressed: () => _controller
              ..text = known.address
              ..selection = TextSelection.collapsed(
                offset: known.address.length,
              ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(known.address),
                Text(
                  known.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) {
    final valid = isUsableIpv4(_text);
    final showError = _text.isNotEmpty && !valid && _text != _prefix;
    final canErase = widget.initial != null;
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [?_knownNote(context), _box(context, showError)],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canErase
              ? () => Navigator.of(context).pop(const ManualIpClear())
              : null,
          child: const Text('Erase saved IP'),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(ManualIpTry(_text))
              : null,
          child: const Text('Try'),
        ),
      ],
    );
  }
}

/// Shows the [ManualIpDialog] pre-filled from the saved address and applies
/// the answer through the [ConnectionCubit] found in [context]. Completes
/// with true when an address was tried or erased, false when the user
/// cancelled.
Future<bool> showManualIpDialog(BuildContext context) async {
  final cubit = context.read<ConnectionCubit>();
  final saved = await cubit.savedManualIp();
  final known = await cubit.knownAddresses();
  final target = cubit.target;
  if (!context.mounted) return false;
  final choice = await showDialog<ManualIpChoice>(
    context: context,
    builder: (_) => ManualIpDialog(
      initial: saved,
      known: known,
      current: target?.host,
      computerName: target?.name,
    ),
  );
  switch (choice) {
    case ManualIpTry(:final address):
      await cubit.setManualIp(address);
      return true;
    case ManualIpClear():
      await cubit.clearManualIp();
      return true;
    case null:
      return false;
  }
}
