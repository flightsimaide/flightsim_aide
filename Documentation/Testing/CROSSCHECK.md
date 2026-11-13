# Parser cross-check

Tasks 3.26 and 3.34. Counts from `grep` (independent of the parser) next to the counts from `tools/parse_cli.dart`, one file per block. Reproduce with `tools/crosscheck.sh <file>` from the project root. `colours`, `continues` and `show` are the number of `sw_define_colour`, `sw_continue` and `sw_show` lines; the CLI shows the colours defined, the continue links kept and the `sw_show` lines skipped.

```text
== testing/fixtures/minimal.txt
grep: checklists=1 checks=3 notes=1 colours=0 continues=0 show_ignored=0
cli:  checklists=1 checks=3 notes=1 warnings=0 colours=0 continues=0
== testing/fixtures/messy.txt
grep: checklists=3 checks=5 notes=1 colours=4 continues=1 show_ignored=1
cli:  checklists=2 checks=5 notes=1 warnings=9 colours=2 continues=0
== testing/fixtures/lookalike_aircraft.txt
grep: checklists=7 checks=33 notes=10 colours=3 continues=6 show_ignored=1
cli:  checklists=7 checks=33 notes=9 warnings=1 colours=3 continues=6
== testing/fixtures/sample_checklist.txt
grep: checklists=2 checks=10 notes=1 colours=0 continues=0 show_ignored=0
cli:  checklists=2 checks=10 notes=1 warnings=0 colours=0 continues=0
```

## Why the numbers differ

| File | Difference | Explanation |
|---|---|---|
| `messy.txt` | checklists 3 vs 2 | `sw_checklist:Empty` (line 13) has no items and is dropped (warning, task 3.16) |
| `messy.txt` | checks 5 vs 5 | same total, different lines: grep misses upper-case `SW_ITEM` (line 10) and counts the orphan on line 1, which the parser skips |
| `messy.txt` | colours 4 vs 2 | line 16 repeats `red` (ignored, duplicate warning) and line 18 is malformed (bad definition warning); `red` and `blue` are defined (the 2 on line 17 is clamped) |
| `messy.txt` | continues 1 vs 0 | `sw_continue:Nowhere` (line 22) names no checklist, so the link is dropped with a warning |
| `messy.txt` | warnings 9 | the nine listed in `EXPECTED.md` (the `sw_show` on line 21 no longer warns) |
| `lookalike_aircraft.txt` | notes 10 vs 9 | the bare `sw_itemvoid:` on line 10 is an empty note and is skipped (`Line 10: empty note`) |
| `lookalike_aircraft.txt` | show_ignored 1 | the `sw_show` on line 39 is ignored like a comment: no warning, no effect (D-70) |
| `minimal.txt`, `sample_checklist.txt` | none | clean files |

All differences match the hand-computed values in `testing/fixtures/EXPECTED.md`.
