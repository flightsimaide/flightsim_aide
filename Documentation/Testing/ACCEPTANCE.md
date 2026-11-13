# Checklist viewer acceptance traceability

The six criteria come from section 16 of `Documentation/Plan/PLAN.md`. Each automated test carries a `// AC-n` comment; `tools/check_acceptance_tags.sh` fails if any criterion has none.

The app reads checklists from the plugin over the network, not from a file picker. The automated tests named here read fixture files directly, which is not the app's business. The manual checks on a real connection are in `Documentation/Testing/MANUAL_TEST.md` (AC-7 to AC-9 and later).

| # | Criterion | Automated tests (file: test name) |
|---|---|---|
| AC-1 | A checklist file shows all of its checklists with correct titles | `test/e2e_flow_test.dart`: open file, list, check two rows, back, reset (titles from the oracle)<br>`test/data/parsers/aircraft_workflow_parser_test.dart`: fixture minimal.txt / parses to the prepare checklist with no warnings; fixture messy.txt / only Preliminary and Colours survive; fixture oracle counts / `<fixture>` matches the oracle counts |
| AC-2 | Every item shows label and result; notes show as headers | `test/e2e_flow_test.dart`: open file, list, check two rows, back, reset (each row shows label and result)<br>`test/data/parsers/aircraft_workflow_parser_test.dart`: fixture minimal.txt / items are a note then three checks; fixture oracle counts / `<fixture>` matches the oracle counts |
| AC-3 | Tapping toggles items; progress and reset work | `test/e2e_flow_test.dart`: open file, list, check two rows, back, reset |
| AC-4 | Dataref text never appears on screen | `test/ui/dataref_never_visible_test.dart`: `<fixture>`: no dataref text on the list or any detail screen |
| AC-5 | A malformed file never crashes the app, and the app reports what was skipped | `test/e2e_bad_files_test.dart`: `<label>`: stays home with a readable error banner; messy.txt: opens the list with a skipped-lines banner<br>`test/data/repositories/checklist_repository_impl_test.dart`: a garbage file gives Error(ParseFailure) and never throws |
| AC-6 | All parser tests pass | `test/data/parsers/aircraft_workflow_parser_test.dart` (fixture minimal.txt, fixture messy.txt, oracle counts and independent regex counts); run `flutter test test/data/parsers` |
