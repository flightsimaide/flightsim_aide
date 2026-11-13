# Fixture sources

Every fixture in this repository is either written by hand for this project or is a plain test input with no third-party text. No file is copied from another author's checklist, so no third-party licence applies to them.

Real aircraft checklists are not committed: their authors' terms differ and most are not stated. A developer who wants to run the parser against real files puts them in `external/` (git-ignored; see `BUILDING.md`), and `Documentation/Testing/real_checker/` shows how.

| Fixture | Origin |
|---|---|
| `testing/fixtures/minimal.txt` | Hand-written. The smallest file with a note and three check items. |
| `testing/fixtures/messy.txt` | Hand-written. Malformed lines on purpose (an item before any checklist, an empty checklist, upper-case keyword, repeated and bad colour definitions, a continue link to nowhere) so each warning can be checked. |
| `testing/fixtures/lookalike_aircraft.txt` | Hand-written lookalike for an invented "example twin turboprop", built from the patterns of real checklist files. No text copied from any downloaded file. 7 checklists, 33 check items. Every value can be checked by hand, so parser-level tests (invariants, golden snapshot) and the end-to-end tests use it. Its numbers are in `EXPECTED.md`. |
| `testing/fixtures/sample_checklist.txt` | Hand-written, two small checklists. |
| `testing/fixtures/empty.txt`, `Latin-1.txt`, `png.txt` | Hand-made inputs for the bad-file cases: an empty file, a Latin-1 encoded file, and a file that is not text. |
| `testing/fixtures/conditions/` | Hand-written, one case per condition form (three files per case; see its `README.md`). |
| `testing/fixtures/manual/` | Hand-written checklists for trying the app by hand against a live simulator. |
| `testing/fixtures/progress/` | Hand-written saved-progress file. |
| `testing/fixtures/protocol/` | Hand-written JSON and text for the plugin protocol. `becn_xp12.bin` is a 29-byte beacon packet modelled on one recorded from X-Plane 12, with the computer name replaced by `SIMPC`. |
