# Reference

- `checklist_docs/`: a guide to the checklist commands (`sw_*`) that the app understands, with pictures of how the app shows each one.
  - `xchecklist_commands.md` is the guide. `Documentation/Reference/GRAMMAR.md` is the formal grammar behind it.
  - `images/` holds the pictures. They are renderings of the app's own screens, made from an invented sample ("Example twin turboprop").
  - `tools/make_checklist_images.dart` makes the pictures again. Run it from the repository root: `flutter test Documentation/Reference/checklist_docs/tools/make_checklist_images.dart`. It is not part of the test suite.
- `datarefs/`: a place for dataref lists read from your own running X-Plane, for looking names up when writing conditions in a checklist. **Git ignores everything in this folder except its README**, so the lists stay on your machine. `datarefs/README.md` says how to make them.
