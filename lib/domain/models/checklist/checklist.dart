import 'package:equatable/equatable.dart';

import 'checklist_item.dart';
import 'continue_link.dart';

/// A named, immutable list of checklist items.
class Checklist extends Equatable {
  /// Creates a checklist; [items] and [continues] are copied into
  /// unmodifiable lists.
  Checklist({
    required this.name,
    required this.title,
    required List<ChecklistItem> items,
    List<ContinueLink> continues = const [],
  }) : items = List.unmodifiable(items),
       continues = List.unmodifiable(continues);

  /// Identifying name, used as the progress key.
  final String name;

  /// Display title.
  final String title;

  /// The checklist's items, in order.
  final List<ChecklistItem> items;

  /// Where to go next, from `sw_continue` lines, in file order.
  final List<ContinueLink> continues;

  @override
  List<Object?> get props => [name, title, items, continues];
}
