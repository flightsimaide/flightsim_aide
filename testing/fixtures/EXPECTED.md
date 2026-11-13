# Fixture oracle

What the parser must produce for each fixture. The **raw** numbers come from `grep`, not from the parser. Run the command next to a number to re-check it. A **parsed** number is the raw number adjusted by hand using the rule in `Documentation/Reference/GRAMMAR.md` that is named beside it.

The raw counts run on the fixtures with CR stripped (`tr -d '\r'`), because Git Bash `grep` hides CR in text mode:

```bash
c() { tr -d '\r' < "testing/fixtures/$1.txt" | grep -cE "$2"; }   # c <fixture> <regex>
CL='^[[:space:]]*@?sw_checklist:'
IT='^[[:space:]]*@?sw_item(_c)?:'
NT='^[[:space:]]*@?sw_(itemvoid|itemvoid_c|iteminfo|remark):'
```

## Summary

| Fixture | Checklist lines (raw) | Checklists (parsed) | Check items (raw) | Check items (parsed) | Note lines (raw) | Notes (parsed) | Warnings |
|---|---:|---:|---:|---:|---:|---:|---:|
| `minimal.txt` | 1 | 1 | 3 | 3 | 1 | 1 | 0 |
| `messy.txt` | 3 | 2 | 5 | 5 | 1 | 1 | 9 |
| `lookalike_aircraft.txt` | 7 | 7 | 33 | 33 | 10 | 9 | 1 |

Raw commands, one per cell: `c <fixture> "$CL"`, `c <fixture> "$IT"`, `c <fixture> "$NT"`.

## `minimal.txt`

| What | Value | Command |
|---|---:|---|
| checklist lines | 1 | `c minimal "$CL"` |
| check items | 3 | `c minimal "$IT"` |
| note lines | 1 | `c minimal "$NT"` |
| warnings | 0 | clean file, no rule fires |

Checklist title (H2, menu text wins): `Prepare for flight`. Items: `Parking brake` = `SET`, `Batteries` = `ON`, `Flight plan` = `loaded`. Note: `----- Prepare -----`.

## `messy.txt`

| What | Raw | Command | Parsed | Why they differ |
|---|---:|---|---:|---|
| checklist lines | 3 | `c messy "$CL"` | 2 | line 13 `Empty` has no items and is dropped (H5, task 3.16); `Preliminary` and `Colours` survive |
| check items | 5 | `c messy "$IT"` | 5 | grep counts lines 1, 7, 8, 19 and 20. The parser skips line 1 (I1, orphan) and accepts line 10 `SW_ITEM` (K1, case-insensitive). Different lines, same total |
| note lines | 1 | `c messy "$NT"` | 1 | line 9, no change |

Raw case-sensitive count of the upper-case keyword (shows grep misses it): `grep -cE '^SW_ITEM:' testing/fixtures/messy.txt` gives 1.

Checklist title: `Preliminary` (menu text; the leading `@` is stripped, T9). Parsed items, in order:

| Line | Label | Result | Note |
|---:|---|---|---|
| 7 | `Parking brake` | `SET\|set` | I2 cuts at the first `:`; the second `\|` stays in the result (I5) |
| 8 | `Item with no pipe` | (empty) | I4 |
| 10 | `Upper case keyword` | `OK` | K1 |

Parsed note: line 9, label `----- Preliminary -----`.

Lines 14 to 22 (appended in task 3.34) are the second checklist `Colours`, which exercises the colour and link rules. Its parsed items:

| Line | Label | Result | Runs |
|---:|---|---|---|
| 19 | `Red plain` | `ON` | label: `Red` in red, ` plain` in the default colour (the `\\` returns to the default, C3); result: `ON` in blue |
| 20 | `Ghost colour` | `OK` | label: `Ghost colour` in `ghost` (never defined, C6) |

Palette: `red` = (1, 0, 0) (the repeat on line 16 is ignored, C5) and `blue` = (1, 0, 0) (the 2 on line 17 is clamped, C5). `bad` (line 18) is not defined. The `sw_continue` on line 22 has no checklist called `Nowhere`, so it is dropped and `Colours` has no links (F4).

### Expected warnings (exactly these nine, in the order the parser reports them)

| # | Line | Text in file | Expected warning | Rule |
|---:|---:|---|---|---|
| 1 | 1 | `sw_item:Orphan item\|before any checklist` | `Line 1: item before any checklist` | I1 |
| 2 | 4 | `// not a comment` | `Line 4: unrecognized line` | T7, T10 (no `:`) |
| 3 | 11 | `bogus_keyword:whatever` | `Line 11: unknown keyword "bogus_keyword"` | K4 |
| 4 | 16 | `sw_define_colour:red:0,1,0` | `Line 16: duplicate colour "red"; first definition kept` | C5 |
| 5 | 17 | `sw_define_colour:blue:2,0,0` | `Line 17: colour component out of range; clamped` | C5 |
| 6 | 18 | `sw_define_colour:bad:1,2` | `Line 18: bad colour definition` | C5 |
| 7 | 20 | `sw_item_c:\ghost\Ghost colour\|OK` | `Line 20: unknown colour "ghost"` | C6 (checked after the whole file is read) |
| 9 | 13 | `sw_checklist:Empty` | `Line 13: checklist "Empty" has no items; dropped` | H5, task 3.16 |
| 10 | 22 | `sw_continue:Nowhere` | `Line 22: continue target "Nowhere" not found` | F4 (checked after the whole file is read) |

Lines with **no** warning, on purpose: 2, 5, 12 (blank, T5), 3 (`#` comment, T6), 6 (`@` stripped, T9), 10 (upper-case keyword accepted, K1).

Wording of warnings 1 to 3 is from `GRAMMAR.md` I1, T10 (task 3.3) and K4. Warnings 4 to 8 and 10 are from tasks 3.28 to 3.32; warning 9 is from task 3.16. Warnings 8 to 10 come after the line-by-line ones because they need the whole file.

## `lookalike_aircraft.txt`

Hand-written lookalike (see `Documentation/Testing/FIXTURE_SOURCES.md`). Small enough to check every value by hand, so parser-level tests (invariants, golden snapshot) use this one. It is license-free.

| What | Raw | Command | Parsed | Why they differ |
|---|---:|---|---:|---|
| checklist lines | 7 | `c lookalike_aircraft "$CL"` | 7 | every checklist has at least one item |
| check items | 33 | `c lookalike_aircraft "$IT"` | 33 | 28 `sw_item` plus 5 `sw_item_c`; none skipped |
| note lines | 10 | `c lookalike_aircraft "$NT"` | 9 | line 10 is a bare `sw_itemvoid:`, skipped (N3). `sw_iteminfo` (line 26) is counted as a note by both (I7) |
| warnings | | | 1 | `Line 10: empty note` (N3). The `sw_show` on line 39 is ignored like a comment and does not warn (K6, D-70) |

Plain `sw_item` count (cross-check): `c lookalike_aircraft '^sw_item:'` gives 28. Not counted as items: `sw_define_colour` (3, palette), `sw_continue` (6, links, all kept), `sw_rcolsize` (1, ignored with no warning, K3) and `sw_show` (1, ignored like a comment, K6).

### Checklists in order

| # | Line | Title | Check items | Notes |
|---:|---:|---|---:|---:|
| 1 | 6 | `EXAMPLE TWIN TURBOPROP - NORMAL PROCEDURES` | 1 | 3 |
| 2 | 17 | `EXTERIOR PREFLIGHT` | 6 | 2 |
| 3 | 30 | `COCKPIT PREPARATION` | 9 | 2 |
| 4 | 47 | `ENGINE START` | 7 | 1 |
| 5 | 60 | `BEFORE TAKEOFF` | 5 | 0 |
| 6 | 70 | `LANDING` | 3 | 1 |
| 7 | 78 | `CRUISE` | 2 | 0 |

The line numbers come from `grep -nE "$CL"`. The items and notes per checklist come from an awk count over the same file and add up to 33 and 9.

### Colours, links and flight order (task 3.34)

Palette: `white` (0.9, 0.9, 0.9), `grey` (0.6, 0.6, 0.6), `amber` (1.0, 0.75, 0.0), from lines 2 to 4.

Continue links (`grep -nE '^sw_continue'`), all valid and kept: line 14 bare (to `EXTERIOR PREFLIGHT`, which follows after comment lines), line 27 to `COCKPIT PREPARATION`, line 44 to `ENGINE START`, line 57 to `BEFORE TAKEOFF`, line 67 to `CRUISE`, line 82 to `LANDING`.

The file order is not the flight order: `LANDING` (line 70) comes before `CRUISE` (line 78) in the file, but `BEFORE TAKEOFF` continues to `CRUISE` and `CRUISE` continues to `LANDING`. So the flight order is the six checklists above in order up to `ENGINE START`, then `BEFORE TAKEOFF`, `CRUISE`, `LANDING`.

Line 75 (`LANDING`, the last item) is `sw_item_c:\white\Speed\grey\, final\\ approach|VREF`: label `Speed, final approach` in three runs, `Speed` in white, `, final` in grey and ` approach` back in white (the `\\` pops the grey marker, C3).

### Labels and results with a dataref suffix (AC-4: no `sim/` text and no dataref `:` may reach the UI)

| Line | Label | Result |
|---:|---|---|
| 33 | `Battery` | `ON` |
| 34 | `Avionics master` | `ON` |
| 35 | `Beacon light` | `ON` (colour markers removed, C1) |
| 37 | `Parking brake` | `SET` |
| 53 | `Oil pressure, both engines` | `IN GREEN` |

Find them again with: `tr -d '\r' < testing/fixtures/lookalike_aircraft.txt | grep -nE '^sw_item(_c)?:.*:'`.

Other expectations: line 13 `sw_item_c:CONTINUE TO CHECKLISTS| ` (in checklist 1) is the item `CONTINUE TO CHECKLISTS` with an empty result (trailing space trimmed, T4). The `sw_iteminfo` on line 26 is a note: label `Fuel quantity limit`, result `3200 LBS`.
