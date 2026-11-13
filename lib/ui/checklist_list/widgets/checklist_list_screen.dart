import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/checklist/checklist_progress_repository.dart';
import '../../../data/repositories/checklist/checklist_repository.dart';
import '../../../routing/routes.dart';
import '../../connection/widgets/connection_status_indicator.dart';
import '../../core/widgets/error_banner.dart';
import '../../core/widgets/loading_indicator.dart';
import '../../core/widgets/warnings_banner.dart';
import '../cubit/checklist_list_cubit.dart';
import '../cubit/checklist_list_state.dart';
import 'checklist_list_tile.dart';

/// Lists the loaded document's checklists, with live progress.
class ChecklistListScreen extends StatelessWidget {
  /// Creates the list screen; its cubit is built from the repositories above.
  const ChecklistListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChecklistListCubit>(
      create: (context) => ChecklistListCubit(
        checklistRepository: context.read<ChecklistRepository>(),
        progressRepository: context.read<ChecklistProgressRepository>(),
      )..load(),
      child: const _ChecklistListView(),
    );
  }
}

class _ChecklistListView extends StatelessWidget {
  const _ChecklistListView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChecklistListCubit, ChecklistListState>(
      builder: (context, state) {
        final title = switch (state) {
          ChecklistListLoaded(:final sourceName) when sourceName.isNotEmpty =>
            sourceName,
          _ => 'Checklists',
        };
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [const ConnectionStatusIndicator()],
          ),
          body: switch (state) {
            ChecklistListLoading() => const LoadingIndicator(),
            ChecklistListFailure(:final message) => Align(
              alignment: Alignment.topCenter,
              child: ErrorBanner(message: message),
            ),
            final ChecklistListLoaded loaded => _LoadedBody(state: loaded),
          },
        );
      },
    );
  }
}

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({required this.state});

  final ChecklistListLoaded state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!state.warningsDismissed)
          WarningsBanner(
            warnings: state.warnings,
            onDismiss: context.read<ChecklistListCubit>().dismissWarnings,
          ),
        Expanded(
          child: ListView.builder(
            itemCount: state.items.length,
            itemBuilder: (context, index) {
              final summary = state.items[index];
              return ChecklistListTile(
                summary: summary,
                onTap: () => context.push(Routes.detailPath(summary.name)),
              );
            },
          ),
        ),
      ],
    );
  }
}
