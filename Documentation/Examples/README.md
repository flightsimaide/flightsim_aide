# Examples

A place for example checklist files (the XChecklist format, see `Documentation/Reference/GRAMMAR.md`) that you want to keep next to the documentation. **Git ignores everything in this folder except this README**, so nothing you put here can be committed by accident.

The author keeps a PC-12 checklist here (`Thranda_PC12_clist.txt`, for the Thranda PC-12/47 in X-Plane 12). It is not part of the repository. The commands guide in `Documentation/Reference/checklist_docs/xchecklist_commands.md` takes some of its example lines from it; the other examples come from `testing/fixtures/`.

To use a checklist with X-Plane, copy it into the aircraft's folder, next to the `.acf` file, named after that file with `_clist.txt` added (for example `Cessna_172SP_clist.txt`).

Thranda, Pilatus and X-Plane are trademarks of their owners. FlightSim Aide is not affiliated with, or endorsed by, any of them.

When you write or change a checklist file, keep the result after `|` short (one or two words: the state to reach), put the rest in an `sw_item_details:` line under the item, and run the file through the app's parser to confirm it still reads with no new warnings.
