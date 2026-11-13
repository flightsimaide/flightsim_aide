import 'checklist.dart';
import 'checklist_document.dart';

/// The checklist that ends a flight (D-22): the last one in the file.
///
/// Kept in one place so the rule can change without touching its callers. It
/// is used only by the progress repository, to tell whether the last
/// checklist of a flight was finished.
Checklist? shutdownChecklistOf(ChecklistDocument document) =>
    document.checklists.isEmpty ? null : document.checklists.last;
