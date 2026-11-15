import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, ScrollCacheExtent;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../data/repositories/flight_sim/flight_sim_repository.dart';
import '../../../data/repositories/settings/settings_repository.dart';
import '../../../routing/routes.dart';
import '../../connection/widgets/connection_status_indicator.dart';
import '../../core/themes/status_colors.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/loading_indicator.dart';
import '../../core/widgets/status_pill.dart';
import '../cubit/checklist_detail_cubit.dart';
import '../cubit/checklist_detail_state.dart';
import 'checklist_app_bar_title.dart';
import 'checklist_item_tile.dart';

/// One checklist with tappable rows, progress and a reset action.
class ChecklistDetailScreen extends StatelessWidget {
  /// Creates the screen for the checklist called [checklistName].
  const ChecklistDetailScreen({required this.checklistName, super.key});

  /// Name of the checklist to show, as found in the document.
  final String checklistName;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChecklistDetailCubit>(
      create: (context) => ChecklistDetailCubit(
        checklistName: checklistName,
        checklistRepository: context.read<ChecklistRepository>(),
        progressRepository: context.read<ChecklistProgressRepository>(),
        flightSim: _optional<FlightSimRepository>(context),
        settings: _optional<SettingsRepository>(context),
      )..load(),
      child: const _ContinueListener(child: _ChecklistDetailView()),
    );
  }

  static T? _optional<T>(BuildContext context) {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

/// The snackbar text shown when the last item is checked and all are green.
const completeNoticeText = 'Checklist is complete.';

/// The snackbar text shown when an untick in Auto mode switches to Manual.
const manualNoticeText =
    'Unticking an item in Auto mode switches this checklist to Manual mode.';

/// Finds the red dialog for a tick against the aircraft, for tests.
const tickWarningDialogKey = ValueKey<String>('tick-warning-dialog');

/// Finds the icon in that dialog, for tests.
const tickWarningIconKey = ValueKey<String>('tick-warning-icon');

/// Finds the dialog's Acknowledge button (keeps the tick), for tests.
const tickWarningAcknowledgeKey = ValueKey<String>('tick-warning-acknowledge');

/// Finds the dialog's Cancel button (backs out of the tick), for tests.
const tickWarningCancelKey = ValueKey<String>('tick-warning-cancel');

/// Shows the red dialog when the user ticks an item the aircraft says is not
/// set (D-71).
class _ContinueListener extends StatefulWidget {
  const _ContinueListener({required this.child});

  final Widget child;

  @override
  State<_ContinueListener> createState() => _ContinueListenerState();
}

class _ContinueListenerState extends State<_ContinueListener> {
  StreamSubscription<TickWarning>? _warnings;
  StreamSubscription<void>? _notices;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<ChecklistDetailCubit>();
    _warnings = cubit.tickWarnings.listen((warning) {
      if (!mounted) return;
      unawaited(_showWarning(warning));
    });
    _notices = cubit.manualNotices.listen((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(manualNoticeText)));
    });
  }

  Future<void> _showWarning(TickWarning warning) async {
    final cubit = context.read<ChecklistDetailCubit>();
    final theme = Theme.of(context);
    final red =
        theme.extension<StatusColors>()?.error ?? theme.colorScheme.error;
    final keep = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: tickWarningDialogKey,
        icon: Icon(Icons.error, key: tickWarningIconKey, color: red, size: 36),
        title: Text(warning.message, style: TextStyle(color: red)),
        actions: [
          TextButton(
            key: tickWarningCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: tickWarningAcknowledgeKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Acknowledge'),
          ),
        ],
      ),
    );
    if (keep == false) {
      cubit.cancelTick(warning);
    } else {
      cubit.acknowledgeTick();
    }
  }

  @override
  void dispose() {
    unawaited(_warnings?.cancel());
    unawaited(_notices?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ChecklistDetailView extends StatelessWidget {
  const _ChecklistDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChecklistDetailCubit, ChecklistDetailState>(
      // When the last item is checked and every item is green (none skipped,
      // none against the aircraft), say so.
      listenWhen: (before, after) =>
          before is ChecklistDetailLoaded &&
          after is ChecklistDetailLoaded &&
          before.name == after.name &&
          !before.isComplete &&
          after.isComplete &&
          after.skipped == 0 &&
          after.disagreedCount == 0,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text(completeNoticeText)));
      },
      builder: (context, state) => switch (state) {
        ChecklistDetailLoading() => Scaffold(
          appBar: AppBar(
            title: const Text('Checklist'),
            actions: [const ConnectionStatusIndicator()],
          ),
          body: const LoadingIndicator(),
        ),
        ChecklistDetailFailure(:final message) => Scaffold(
          appBar: AppBar(
            title: const Text('Checklist'),
            actions: [const ConnectionStatusIndicator()],
          ),
          body: _FailureBody(message: message),
        ),
        final ChecklistDetailLoaded loaded => Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: ChecklistAppBarTitle(title: loaded.title),
            actions: [const ConnectionStatusIndicator()],
          ),
          body: _LoadedBody(state: loaded),
        ),
      },
    );
  }
}

/// Goes on to [target], from Continue or from the button row. When items were
/// skipped, are still unchecked or disagree with the aircraft it first shows
/// an amber caution dialog naming each non-zero count, with Cancel (stay) and
/// Continue (go on); with none of them it goes straight on.
Future<void> _continue(
  BuildContext context,
  ChecklistDetailLoaded state,
  NextChecklist target,
) async {
  final router = GoRouter.of(context);
  if (state.skipped > 0 || state.disagreedCount > 0 || state.unchecked > 0) {
    final theme = Theme.of(context);
    final amber =
        theme.extension<StatusColors>()?.caution ?? theme.colorScheme.error;
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: continueCautionDialogKey,
        icon: Icon(Icons.warning, color: amber, size: 36),
        title: Text('Continue with caution?', style: TextStyle(color: amber)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.unchecked > 0)
              Text(
                state.unchecked == 1
                    ? '1 checklist item is not checked'
                    : '${state.unchecked} checklist items are not checked',
              ),
            if (state.skipped > 0)
              Text(
                state.skipped == 1
                    ? '1 checklist item has been skipped'
                    : '${state.skipped} checklist items have been skipped',
              ),
            if (state.disagreedCount > 0)
              Text(
                state.disagreedCount == 1
                    ? '1 checklist item disagrees with the aircraft state'
                    : '${state.disagreedCount} checklist items disagree '
                          'with the aircraft state',
              ),
          ],
        ),
        actions: [
          TextButton(
            key: continueCautionCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: continueCautionContinueKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }
  unawaited(router.pushReplacement(Routes.detailPath(target.name)));
}

/// Asks, then clears every tick of the open checklist.
Future<void> _confirmReset(BuildContext context) async {
  final cubit = context.read<ChecklistDetailCubit>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reset checklist?'),
      content: const Text('This clears every check in this checklist.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  if (confirmed ?? false) cubit.reset();
}

/// Finds the Auto / Manual toggle in the bottom row, for tests.
const autoToggleKey = ValueKey<String>('auto-toggle-button');

/// Finds the Skip button in the bottom row, for tests.
const skipKey = ValueKey<String>('skip-button');

/// Finds the caution dialog shown by Continue when items were skipped or
/// disagree with the aircraft, for tests.
const continueCautionDialogKey = ValueKey<String>('continue-caution-dialog');

/// Finds that dialog's Cancel button, for tests.
const continueCautionCancelKey = ValueKey<String>('continue-caution-cancel');

/// Finds that dialog's Continue button, for tests.
const continueCautionContinueKey = ValueKey<String>(
  'continue-caution-continue',
);

/// Finds the Check button in the bottom row, for tests.
const checkKey = ValueKey<String>('check-button');

/// Finds the bottom Reset button, for tests.
const bottomResetKey = ValueKey<String>('bottom-reset-button');

/// Finds the Continue button, for tests.
const continueButtonKey = ValueKey<String>('continue-button');

/// Tells the user that some items cannot be checked by the app (the sim cannot
/// give the value they need), so they stay manual. Amber with a warning icon:
/// can continue, degraded.
class ManualItemsNotice extends StatelessWidget {
  /// Creates the notice for [count] items.
  const ManualItemsNotice({required this.count, super.key});

  /// How many items stay manual.
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caution = theme.extension<StatusColors>()?.caution;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.warning, color: caution, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 item stays manual'
                      : '$count items stay manual',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureBody extends StatelessWidget {
  const _FailureBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ErrorBanner(message: message),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(Routes.list),
              child: const Text('Back'),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadedBody extends StatefulWidget {
  const _LoadedBody({required this.state});

  final ChecklistDetailLoaded state;

  @override
  State<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends State<_LoadedBody> {
  /// One key per row, so the next item can be scrolled into view. The list is
  /// built ahead (`cacheExtent`), so every row has a context.
  final Map<int, GlobalKey> _keys = {};
  final _scroll = ScrollController();

  /// The row the pilot last acted on (a tap, Check or Skip). When auto-check
  /// then ticks several items in a row, the list never scrolls past it, so the
  /// pilot keeps their place and can read what auto checked. Null until the
  /// pilot acts.
  int? _anchor;

  /// Whether the pilot acted since the pointer last moved.
  bool _acted = false;

  /// When the pointer last moved, to tell a burst of auto ticks from a pointer
  /// that had been waiting (auto stopped on a false dataref).
  DateTime? _pointerMovedAt;

  /// A pointer that stood still this long counts as the pilot's place.
  static const _restingTime = Duration(seconds: 1);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scrollToNext();
  }

  @override
  void didUpdateWidget(_LoadedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.resets != widget.state.resets) {
      // A reset: back to the top, not to the next item.
      _anchor = null;
      _acted = false;
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
      return;
    }
    final next = _nextIndex(widget.state);
    final before = _nextIndex(oldWidget.state);
    if (next != before) {
      final now = DateTime.now();
      final moved = _pointerMovedAt;
      // Auto stopped at `before` (a dataref was false) and now moves on, for
      // example after a switch was flipped in the sim: keep `before` on screen.
      if (!_acted &&
          before != null &&
          (moved == null || now.difference(moved) > _restingTime)) {
        _anchor = before;
      }
      _acted = false;
      _pointerMovedAt = now;
    }
    if (next == null && _nextIndex(oldWidget.state) != null) {
      // The last open item was just checked (often several at once in auto
      // mode): show the end of the list, with the last items and the
      // checklist buttons.
      _scrollToEnd();
    } else if (_nextIndex(oldWidget.state) != next) {
      _scrollToNext();
    }
  }

  /// Scrolls to the end of the list. The end is only estimated until the rows
  /// below have been laid out, so it tries again until it is reached.
  void _scrollToEnd([int tries = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scroll.hasClients) return;
      await _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      if (mounted &&
          _scroll.hasClients &&
          tries < 3 &&
          _scroll.position.pixels < _scroll.position.maxScrollExtent) {
        _scrollToEnd(tries + 1);
      }
    });
  }

  /// The row the list follows: the pointer item, the one auto-check and the
  /// Check button work on (the first open check item at or after the cursor),
  /// or null when none is left. Not the first open item of the list: after a
  /// tick in the middle, items above it may stay open.
  static int? _nextIndex(ChecklistDetailLoaded state) => state.pointer;

  /// Where the next item lands when the list has to scroll: this fraction of
  /// the viewport height from the top, so the items after it show too.
  static const _scrollAlignment = 1 / 3;

  /// Does nothing while the next item is fully visible. Otherwise scrolls so
  /// that the item sits a third of the way down the viewport.
  void _scrollToNext() {
    final next = _nextIndex(widget.state);
    if (next == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _keys[next]?.currentContext;
      if (!mounted || target == null || !target.mounted) return;
      if (!_scroll.hasClients) return;
      final object = target.findRenderObject();
      if (object == null) return;
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) return;
      final position = _scroll.position;
      final topAligned = viewport.getOffsetToReveal(object, 0).offset;
      final bottomAligned = viewport.getOffsetToReveal(object, 1).offset;
      final pixels = position.pixels;
      if (pixels >= bottomAligned - 0.5 && pixels <= topAligned + 0.5) {
        return; // already fully visible
      }
      var destination = viewport
          .getOffsetToReveal(object, _scrollAlignment)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      // Do not scroll the pilot's own row off the top of the screen.
      final anchorObject = _anchor == null
          ? null
          : _keys[_anchor]?.currentContext?.findRenderObject();
      if (anchorObject != null) {
        final anchorTop = viewport.getOffsetToReveal(anchorObject, 0).offset;
        if (anchorTop >= pixels - 0.5 && destination > anchorTop) {
          destination = anchorTop.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
        }
      }
      if ((destination - pixels).abs() < 0.5) return;
      unawaited(
        _scroll.animateTo(
          destination,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<ChecklistDetailCubit>();
    return Column(
      children: [
        Semantics(
          label: 'Progress',
          value: '${state.done + state.skipped} of ${state.total}',
          child: LinearProgressIndicator(
            value: state.total == 0
                ? 0
                : (state.done + state.skipped) / state.total,
          ),
        ),
        _StatusRow(state: state),
        if (state.stayManual > 0) ManualItemsNotice(count: state.stayManual),
        Expanded(
          child: ListView(
            controller: _scroll,
            // A checklist has a few dozen rows. Building them all gives every
            // row a context, so the pointer item far below can be scrolled to.
            scrollCacheExtent: const ScrollCacheExtent.pixels(100000),
            children: [
              for (var i = 0; i < state.rows.length; i++)
                ChecklistItemTile(
                  key: _keys.putIfAbsent(i, GlobalKey.new),
                  item: state.rows[i].item,
                  checked: state.rows[i].checked,
                  autoChecked: state.rows[i].autoChecked,
                  disagreed: state.rows[i].disagreed,
                  skipped: state.rows[i].skipped,
                  autoOn: state.auto,
                  enabled: state.rows[i].enabled,
                  optionOn: state.rows[i].optionOn,
                  colours: state.colours,
                  onTap: () {
                    _anchor = i;
                    _acted = true;
                    cubit.toggle(state.rows[i].index);
                  },
                  onSwitch: () {
                    _anchor = i;
                    _acted = true;
                    cubit.toggleOption(state.rows[i].index);
                  },
                ),
              if (state.checklists.length > 1)
                _ChecklistButtons(
                  state: state,
                  onOpen: (target) =>
                      unawaited(_continue(context, state, target)),
                ),
            ],
          ),
        ),
        if (state.continueTo case final target? when state.showContinue)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: continueButtonKey,
                onPressed: () => unawaited(_continue(context, state, target)),
                child: Text('Continue: ${target.title}'),
              ),
            ),
          ),
        _ButtonRow(
          auto: state.auto,
          onToggleAuto: () => unawaited(cubit.toggleAuto()),
          onReset: state.done + state.skipped == 0
              ? null
              : () => _confirmReset(context),
          onCheck: state.pointer == null
              ? null
              : () {
                  _anchor = state.pointer;
                  _acted = true;
                  cubit.checkNext();
                },
          onSkip: state.canSkip
              ? () {
                  _anchor = state.pointer;
                  _acted = true;
                  cubit.skipNext();
                }
              : null,
        ),
      ],
    );
  }
}

/// The bottom row: a fixed Reset, then Auto/Manual, Skip and Check sharing the rest.
/// Reset clears every tick (after a confirm) and goes to manual mode; the
/// second button toggles auto and manual; Check ticks the next item (the
/// pointer item, also in manual mode); Skip marks the next open item as
/// skipped (task 0.24). Every colour comes from the theme: Check is success, Skip caution, Auto/Manual
/// info; Reset has the theme's button colours.
class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.auto,
    required this.onToggleAuto,
    required this.onReset,
    required this.onCheck,
    required this.onSkip,
  });

  /// Whether auto-check is on; the second button shows the mode.
  final bool auto;

  /// Switches between auto and manual mode.
  final VoidCallback onToggleAuto;

  /// Null when there is nothing to clear.
  final VoidCallback? onReset;

  /// Ticks the next item; null when none is left.
  final VoidCallback? onCheck;

  /// Skips the next open item; null when none is left.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).extension<StatusColors>();
    final scheme = Theme.of(context).colorScheme;
    // Skip is yellow (caution) and Check green (good), from the theme.
    final skip = status?.cautionBackground ?? scheme.tertiary;
    final check = status?.success ?? scheme.primary;
    // Auto/Manual is information (cyan) in both modes; the label tells which.
    final mode = status?.info ?? scheme.secondary;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: _button('Reset', null, onReset, key: bottomResetKey),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _button(
                auto ? 'Auto' : 'Manual',
                mode,
                onToggleAuto,
                key: autoToggleKey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _button('Skip', skip, onSkip, key: skipKey)),
            const SizedBox(width: 12),
            Expanded(child: _button('Check', check, onCheck, key: checkKey)),
          ],
        ),
      ),
    );
  }

  Widget _button(
    String label,
    Color? colour,
    VoidCallback? onPressed, {
    Key? key,
  }) => FilledButton(
    key: key,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      // Null keeps the theme's own button colours.
      backgroundColor: colour,
      foregroundColor: colour == null ? null : readableOn(colour),
      minimumSize: const Size.fromHeight(48),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    child: Text(label),
  );
}

/// The top row: "2/3", and after "3/3" a green "Complete".
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state});

  final ChecklistDetailLoaded state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: state.isComplete
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('${state.done}/${state.total}', style: style),
                  if (state.isComplete) ...[
                    const SizedBox(width: 12),
                    StatusPill(
                      status: PillStatus.good,
                      text: 'Complete',
                      style: style,
                    ),
                  ],
                  if (state.skipped > 0) ...[
                    const SizedBox(width: 12),
                    StatusPill(
                      status: PillStatus.caution,
                      text: '${state.skipped} skipped',
                      style: style,
                    ),
                  ],
                  if (state.disagreedCount > 0) ...[
                    const SizedBox(width: 12),
                    StatusPill(
                      status: PillStatus.warning,
                      text: '${state.disagreedCount} overridden',
                      style: style,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Finds the row of checklist buttons at the end of the list, for tests.
const checklistButtonsKey = ValueKey<String>('checklist-buttons');

/// Finds the button for the checklist called [name], for tests.
ValueKey<String> checklistButtonKey(String name) =>
    ValueKey<String>('checklist-button-$name');

/// The last entry of the list: one outlined chip for each checklist of the
/// document. The current one is selected and centered; the row scrolls
/// sideways when the chips do not fit, and an edge fade shows at each end that
/// has more to scroll to. A margin below keeps it clear of the bottom row.
class _ChecklistButtons extends StatefulWidget {
  const _ChecklistButtons({required this.state, required this.onOpen});

  final ChecklistDetailLoaded state;
  final ValueChanged<NextChecklist> onOpen;

  @override
  State<_ChecklistButtons> createState() => _ChecklistButtonsState();
}

class _ChecklistButtonsState extends State<_ChecklistButtons> {
  static const _fadeWidth = 28.0;

  final _current = GlobalKey();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// The checklist to centre and highlight: the next one in the file once this
  /// one is complete, otherwise the open one.
  String? get _focusName {
    final state = widget.state;
    return state.isComplete && state.nextInFile != null
        ? state.nextInFile!.name
        : state.name;
  }

  @override
  void didUpdateWidget(_ChecklistButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.state;
    final now = widget.state;
    if (old.isComplete != now.isComplete ||
        old.nextInFile?.name != now.nextInFile?.name) {
      _centre();
    }
  }

  @override
  void initState() {
    super.initState();
    _centre();
  }

  void _centre() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _current.currentContext;
      if (!mounted) return;
      // The extent is known after the first layout: show the fades.
      setState(() {});
      if (context == null || !context.mounted) return;
      // Not Scrollable.ensureVisible: it scrolls every scrollable above the
      // button too, which moved the whole list to its end on opening. Only the
      // sideways row is wanted, so move its own controller.
      final object = context.findRenderObject();
      if (object == null || !_scroll.hasClients) return;
      final viewport = RenderAbstractViewport.maybeOf(object);
      if (viewport == null) return;
      final position = _scroll.position;
      final target = viewport
          .getOffsetToReveal(object, 0.5)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (position.pixels == target) return;
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: ListenableBuilder(
        listenable: _scroll,
        builder: (context, child) {
          final position = _scroll.hasClients ? _scroll.position : null;
          final fadeStart =
              position != null &&
              position.pixels > position.minScrollExtent + 1;
          final fadeEnd =
              position != null &&
              position.pixels < position.maxScrollExtent - 1;
          if (!fadeStart && !fadeEnd) return child!;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final f = (_fadeWidth / bounds.width).clamp(0.0, 0.5);
              return LinearGradient(
                colors: [
                  fadeStart ? Colors.transparent : Colors.black,
                  Colors.black,
                  Colors.black,
                  fadeEnd ? Colors.transparent : Colors.black,
                ],
                stops: [0, f, 1 - f, 1],
              ).createShader(bounds);
            },
            child: child,
          );
        },
        child: NotificationListener<ScrollMetricsNotification>(
          // Rebuilds the fades when the size of the row changes.
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() {});
            });
            return false;
          },
          child: SingleChildScrollView(
            key: checklistButtonsKey,
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in state.checklists)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: c.name == state.name
                        ? ChoiceChip(
                            key: checklistButtonKey(c.name),
                            selected: true,
                            // Selected, not tappable: it is the open checklist.
                            onSelected: null,
                            padding: _chipPadding,
                            shape: _chipShape,
                            label: Container(
                              key: _focusName == c.name ? _current : null,
                              child: Text(c.title),
                            ),
                          )
                        : ActionChip(
                            key: checklistButtonKey(c.name),
                            onPressed: () => widget.onOpen(c),
                            padding: _chipPadding,
                            shape: _chipShape,
                            // The next checklist, once this one is complete.
                            backgroundColor: _focusName == c.name
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            label: Container(
                              key: _focusName == c.name ? _current : null,
                              child: Text(
                                c.title,
                                style: _focusName == c.name
                                    ? TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _chipPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );
  static final _chipShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
}
