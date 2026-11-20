# Checklist file grammar

Frozen from `PLAN.md` section 2, adjusted by a survey of real checklist files (not published) and by probing the real Xchecklist parser (`Documentation/Testing/real_checker/`).

**Status column**

- **Confirmed** means seen in real files (a survey of 27 files, not published) or observed in the real checker. The survey section is named.
- **Assumed** means not seen in the corpus. It is either a design choice or a safety net and is kept on purpose.

The viewer shows labels, results and notes. Dataref text is kept on the item line and parsed into a condition (section 8). The parser keeps colours (markers and the `sw_define_colour` palette) and `sw_continue` links in the model; the UI shows them. The voice rows (`sw_challenge`, section 5d) mark which rows are read as a challenge and a response (D-84), and `sw_show` is ignored (D-70).

## Example

```
sw_checklist:Prepare:Prepare for flight
sw_itemvoid:----- Prepare -----
sw_item:Parking brake|SET
sw_item:Batteries|ON
sw_item:Flight plan|loaded
```

## 1. Text and lines

| # | Rule | Status | Evidence |
|---|---|---|---|
| T1 | A line ends at `\r\n`, `\n` or a lone `\r`. All three are normalized to `\n` before parsing. Line numbers in warnings are 1-based and count every physical line, including skipped ones. | **Confirmed** | 0.10: CRLF in most files, LF in 3, lone CR in 2 (Thranda, DWSim F-16C), mixed CRLF and LF in 3 |
| T2 | A leading UTF-8 byte-order mark is removed. | **Confirmed** | 0.10: 6 files |
| T3 | Text is UTF-8. If decoding fails, fall back to Latin-1 instead of failing. | **Assumed** | 0.10: all 27 files are valid UTF-8; the fallback is a safety net from the plan's risk list |
| T4 | Each line is trimmed, and each extracted value is trimmed. | **Confirmed** (padding is common) | 0.8, 0.9. The real plugin does not trim; this is a deliberate cleanup |
| T5 | Blank lines are ignored. | **Confirmed** | 0.6 |
| T6 | A line whose first non-blank character is `#` is a comment and is skipped without a warning. | **Confirmed** | 0.6: 26 of 27 files, 762 lines |
| T7 | `//` and `;` do **not** start comments. A line starting with either is an unrecognized line (warning). | **Confirmed** | 0.6: 0 occurrences; real checker skips such text as unrecognized (probes `q2`, `q3`) |
| T8 | A `#` that is not at the start of the line is ordinary text. | **Confirmed** (rare) | 0.6: real checker keeps `Hash #1` (probe `q9`); one occurrence in the corpus, in an upstream test file |
| T9 | A single `@` directly before a keyword is removed (it means "do not speak"). It has no effect in the viewer. | **Confirmed** | 0.7: 4 lines, 2 files |
| T10 | A line with no `:` after the prefix handling is an unrecognized line (warning). | **Confirmed** | 0.6: stray `4` in `ERJ_clist.txt` |

## 2. Keywords

The keyword is the text before the first `:`, trimmed.

| # | Rule | Status | Evidence |
|---|---|---|---|
| K1 | Keywords are matched ignoring case (`SW_ITEM` works). | **Assumed** | 0.6: the real plugin is case sensitive and rejects `SW_ITEM`; no upper-case keyword appears in any real file. Tolerance is kept deliberately |
| K2 | Parsed: `sw_checklist`, `sw_item`, `sw_item_c`, `sw_itemvoid`, `sw_itemvoid_c`, `sw_iteminfo`, `sw_remark`, and the app's own extensions `sw_item_heading`, `sw_item_heading_c`, `sw_item_details`, `sw_item_details_c` (section 5a), and `sw_switch`, `sw_if`, `sw_else`, `sw_end` (section 5b), and `sw_table`, `sw_row`, `sw_table_end`, `sw_calculate` (section 5c), and `sw_challenge` (section 5d). | **Confirmed** | 0.5 census |
| K3 | Valid but ignored with **no warning**: `sw_rcolsize` only. | **Confirmed** | 0.5: 81 lines |
| K5 | Parsed into the model: `sw_define_colour` (section 6), `sw_continue` (section 7). | **Confirmed** | 0.5: 201 and 395 lines |
| K6 | `sw_show` is **ignored like a comment**: the line is skipped with no warning and no effect (D-70). It does not end a checklist and does not affect a bare `sw_continue` look-ahead. | **Confirmed** (keyword); the decision is the user's | 0.5: 50 lines, dataref conditions |
| K4 | Any other keyword gives the warning `Line N: unknown keyword "<keyword>"` and the line is skipped. The checklist stays open. This covers the typos `ssw_item_c` and `sw_itemvoid_c_c` found in real files. | **Confirmed** (typos seen) | 0.5: 3 + 3 lines |

## 3. Checklist lines

| # | Rule | Status | Evidence |
|---|---|---|---|
| H1 | `sw_checklist:Name[:Menu text]` starts a new checklist. Name is the text up to the first `:`. Menu text is everything after it, so extra colons stay in the menu text. Both are trimmed. | Name and Menu: **Confirmed**. Extra colons: **Assumed** | 0.9: 181 name-only, 455 with menu text, 0 with extra colons |
| H2 | The display title is the menu text if it is not empty, otherwise the name. | **Assumed** (design choice) | 0.9: in the real plugin the first part is the window heading and the second is the menu entry; our list screen takes the role of the menu |
| H3 | An empty name becomes `Untitled checklist N` with the warning `Line N: checklist has no name`. | **Assumed** | 0.9: 0 empty names in the corpus; the real checker rejects them (D-11) |
| H4 | A name that already exists is renamed `Name (2)`, `Name (3)` and a warning is added. | **Assumed** | 0.9: duplicates only in the upstream test file (D-2) |
| H5 | A checklist with no items is dropped with a warning. | **Assumed** | |
| H6 | A file with no checklists is a load failure, not an empty success. | **Assumed** | D-6 |

## 4. Item lines

An item is `sw_item`, `sw_item_c` or `sw_iteminfo`. Everything after the first `:` that belongs to the dataref part is dropped.

| # | Rule | Status | Evidence |
|---|---|---|---|
| I1 | An item or note with no open checklist is skipped with the warning `Line N: item before any checklist`. | **Assumed** | 0.6: no such line in the corpus |
| I2 | Find the first `\|` and the first `:` in the value. If a `\|` exists and comes before the first `:` (or there is no `:`), the **label** is the text before the `\|`, and the **result** is the text after the `\|` up to the next `:`. | **Confirmed** | 0.8: 1853 lines |
| I3 | Otherwise (a `:` comes first, or there is no `\|`) the **label** is the text before the first `:`, the **result** is empty, and the rest is dropped. A `\|` after the first `:` is part of a dataref expression, not a separator. | **Confirmed** | 0.8: 67 + 3 lines with a colon and no leading pipe; 14 lines have a pipe after the colon |
| I4 | An item with neither `\|` nor `:` has the whole value as label and an empty result. | **Confirmed** | 0.8: 66 lines |
| I5 | Further `\|` characters in the result part stay in the result (`A\|B\|C` gives result `A\|B\|C`, cut at the first `:`). | **Assumed** | 0.8: the real checker reports a syntax error; the case never occurs in real aircraft files |
| I6 | An empty label (after trimming and colour removal) skips the line with the warning `Line N: item has no label`. | **Confirmed** (real checker errors) | probe `q12` |
| I7 | `sw_item` and `sw_item_c` create a **check** item. `sw_iteminfo` creates a **note** with label and result, using the same splitting. | **Confirmed** for the shape; the note choice is a design decision | 0.5: ChangeLog 1.07 says info items are not user checkable |

## 5. Note lines

| # | Rule | Status | Evidence |
|---|---|---|---|
| N1 | `sw_itemvoid:Text[\|Text2]` and `sw_itemvoid_c` create a **note**. The label is the text before the first `\|` and the result is the text after it. Colons are **not** special in notes. | **Confirmed** | 0.5: 395 note lines contain a `\|` |
| N2 | `sw_remark:Text` creates a note whose label is the whole value and whose result is empty. | **Confirmed** | 0.5: 90 lines |
| N3 | An empty note is skipped with the warning `Line N: empty note`. | **Assumed** | probe `q13`: the real checker accepts it silently (D-11) |

## 5a. App extensions: headings and details

These four keywords are not in XChecklist; the real plugin does not know them, so a file that uses them is for this app only (the plugin warns about an unknown keyword). Colour markers work on the plain and the `_c` form alike (C1).

| # | Rule | Status | Evidence |
|---|---|---|---|
| E1 | `sw_item_heading:Text[\|j]` and `sw_item_heading_c` create a **heading** item: bold text on a darker band, no marker, not checkable. `j` is `left`, `center` (or `centre`) or `right`, any case; single letters are not accepted. With no `j` the heading is centred. If the text after the last `\|` is not one of those words, the whole value is the heading. A `:` is part of the text; a heading has no condition. | **Design** (user request) | `heading_details_parser_test.dart` |
| E2 | An empty heading is skipped with the warning `Line N: heading has no text`. | **Design** | same |
| E3 | `sw_item_details:Text` and `sw_item_details_c` create a **details** line: the whole value is the text (colons and bars included), shown under the item above it, indented to start under that item's label, on a darker band, in a dimmer colour. It is not checkable, has no condition, and keeps its place in file order. An empty text is skipped with `Line N: details has no text`. | **Design** (user request) | same |
| E4 | A heading or details line is a non-check item, so it is skipped by auto-check, the pointer and the Check, Skip and Reset buttons, like a note. It counts in the item list and in the fingerprint (type indexes 2 and 3). | **Design** | |

## 5b. App extension: switches and blocks

`sw_switch`, `sw_if`, `sw_else` and `sw_end` are not in XChecklist. A **switch** is a named on/off position the pilot sets once; the **blocks** that follow it show one group of items while it is on and another while it is off, for example the items that apply only with a ground power unit. A file that uses them is for this app only; the real plugin is expected to warn about the unknown keywords and show every item (not run, see the status column).

```
sw_switch:Use GPU|gpu|OFF       the switch row: label, id, default
sw_item:GPU|CONNECT             shown while gpu is ON
sw_item:GPU power|ON
sw_else
sw_item:Unplug|CHECK            shown while gpu is OFF
sw_end

sw_if|gpu|ON                    no row; the same switch, in any checklist
sw_item:Disconnect GPU|DONE     shown while gpu is ON
sw_else
sw_item:Nothing to do|OK        shown while gpu is OFF
sw_end
```

| # | Rule | Status | Evidence |
|---|---|---|---|
| G1 | `sw_switch:Label\|id\|state` creates a **switch row** (item type `option`) with the label, the id and the default position `ON` or `OFF` (any case). The state may be left out: the default is **OFF**. The id is a name, trimmed and lower-cased; it is shared by the whole file. The row has no result and no condition. It is an item like a manual one: it has a check circle, counts in the total, can be ticked or skipped, and auto-check stops at it until the pilot ticks it. Its switch (on or off) and its tick are separate: a tap on the row ticks it, a tap on the switch moves it. A bad state word warns `Line N: sw_switch state must be ON or OFF; OFF assumed`; more than three parts warn `Line N: sw_switch has extra parts; ignored`. | **Design** (user request) | `enable_block_parser_test.dart` |
| G2 | The switch row opens a **block**. The items up to `sw_else` (or up to `sw_end` when there is no `sw_else`) are the ON branch: they are shown while the switch is on. The items between `sw_else` and `sw_end` are the OFF branch: they are shown while it is off. `sw_else` and `sw_end` make no item and may be written with or without a trailing `:`. A block may be empty, so a switch can be defined in one place and used only by `sw_if` blocks. Keywords ignore case (K1). | **Design** | same |
| G3 | `sw_if\|id\|state` opens a block on the switch `id` and shows **no row**: only the switch row of `sw_switch` turns the switch, so there is one place to set it. The state is the position in which the branch before `sw_else` is shown, `ON` or `OFF`; left out it is `ON` (`sw_if\|gpu\|OFF` shows its first branch while the switch is off). `sw_if` ends at `sw_end` and may have a `sw_else`. A `sw_if` may come before its `sw_switch` in the file, or in an earlier checklist; ids are resolved once the whole file is read. A bad state word warns `Line N: sw_if state must be ON or OFF; ON assumed`. `sw_if_else` is not defined (a possible later extension). | **Design** | same |
| G4 | Every item between the lines of a block (check items, notes, headings and details lines) belongs to its branch: the parser sets its `gate` to the switch and the position. `gate` is internal to the model and is not part of the file syntax. Items outside any block have no gate. A block lies inside one checklist; there may be any number of blocks in a checklist. | **Design** | same |
| G5 | An item whose branch is **not** the current one is **hidden**: it is not shown, not counted in the total or in the checked count, and auto-check, the pointer, Check and Skip pass over it. The switch row itself is never hidden and is always counted. So the total of a checklist changes when a switch moves. Turning a switch clears the checks, skips, auto marks and red marks of the items it hides, in every checklist. The switch starts at its default; Reset keeps the positions, and the reset of every checklist (a new flight) puts them back at the defaults (D-82, which also has the rules for the cursor and for saving). The parser only builds the model. | **Design** | D-82 |
| G6 | A block cannot nest. A `sw_switch` or `sw_if` inside a block is ignored (no row, no gate) with `Line N: <keyword> inside another block; ignored`; its own `sw_else` and `sw_end` are ignored with it, and the outer block carries on. A block still open at the next `sw_checklist` or at the end of the file is closed there, with `Line N: <keyword> has no sw_end; closed at the end of the checklist` (N is the line of the start). | **Design** | same |
| G7 | `sw_end` with no open block warns `Line N: sw_end without sw_if or sw_switch`; `sw_else` with no open block warns `Line N: sw_else without sw_if or sw_switch`; a second `sw_else` in one block warns `Line N: second sw_else in a block; ignored` (the items stay in the OFF branch). Each does nothing else. | **Design** | same |
| G8 | A start with no label (`sw_switch:\|id`, or the bare keyword), or with no id, is skipped with `Line N: sw_switch has no label; ignored` or `Line N: <keyword> has no switch id; ignored`; its items are not gated and its `sw_end` is taken with it. A second `sw_switch` with an id already defined warns `Line N: duplicate switch "id"; first definition kept, no switch row` and its block is gated on the first switch like a `sw_if\|id\|ON`. A `sw_if` naming an id no `sw_switch` defines warns `Line N: sw_if names the unknown switch "id"; its items are always shown`. Any of these lines before any checklist gives `Line N: item before any checklist`. | **Design** | same |
| G9 | A `sw_continue` followed by `sw_switch` or `sw_if` counts as followed by an item (F3). | **Design** | same |

## 5c. App extension: lookup tables and calculated values

`sw_table`, `sw_row`, `sw_table_end` and `sw_calculate` are not in XChecklist. A **table** holds numbers the pilot would otherwise read from a chart in the flight manual; a **calculate line** shows one value out of it for the aircraft's state right now, for example the torque to set for maximum cruise power at the current altitude, temperature and weight. A file that uses them is for this app only; the real plugin is expected to warn about the unknown keywords and skip the lines (not run, see the status column).

```
sw_item:Max cruise power|SET
sw_calculate:maxcruise|torque|Torque|psi|0.1     under the item it belongs to
sw_calculate:maxcruise|ff_lb|Fuel flow|lb/h|1

sw_table:maxcruise|isa={sim/cockpit2/temperature/outside_air_temp_degc}-(15-0.00198*{sim/flightmodel2/position/pressure_altitude}), alt=sim/flightmodel2/position/pressure_altitude, w=sim/flightmodel/weight/m_total|torque, ff_lb
sw_row:-40,0,3175|36.9,601
sw_row:-40,0,3629|36.9,601
sw_table_end
```

| # | Rule | Status | Evidence |
|---|---|---|---|
| L1 | `sw_table:name\|inputs\|outputs` starts a table. The name and every column name are lower-cased and use only letters, digits and `_`. **Inputs** are `column=source` pairs separated by commas, where `column` may be `name(Label, unit)` to say what the pilot sees in a message (`alt(Altitude, ft)`; both parts are optional, the label defaults to the name and the unit to nothing) (a comma inside brackets or a function call does not split): the source is a dataref (`sim/x`, `sim/x[2]`) or an arithmetic expression of `{datarefs}` (section 8.4). **Outputs** are plain column names separated by commas. One to four inputs and at least one output; a column name may appear only once in the table. | **Design** | D-83; `test/data/parsers/lookup_table_parser_test.dart` |
| L2 | `sw_row:in,in\|out,out` is one row of the table above it: the input values, then the output values, as numbers, in the order of the columns. A row with the wrong count or a value that is not a number warns `Line N: sw_row ...; row skipped`. `sw_table_end` ends the table. Tables are file-level: they may stand anywhere (at the end of the file by convention), belong to no checklist and are never shown. | **Design** | same |
| L3 | The rows must form a **complete grid**: every combination of the distinct values of the input columns has exactly one row, in any order. Otherwise the table is ignored with `Line N: sw_table "name" has no row for (a,b)`, `... has two rows for (a)` or `... has no rows` (N is the `sw_table` line). At most 20,000 rows. | **Design** | same |
| L4 | A start line that cannot be read (wrong number of parts, a bad or repeated column name, an unreadable source, more than four inputs) or a second table with a name already used is ignored with its warning, and its `sw_row` and `sw_table_end` lines are skipped with no further warning. The first definition of a name is kept. | **Design** | same |
| L5 | Only `sw_row` and `sw_table_end` belong inside a table. Any other line closes it with `Line N: sw_table "name" has no sw_table_end; closed there` (N is the `sw_table` line) and is then read as usual; a table still open at the end of the file is closed there. A `sw_row` outside a table warns `Line N: sw_row outside sw_table; ignored`, and `sw_table_end` without a table `Line N: sw_table_end without sw_table`. | **Design** | same |
| L6 | `sw_calculate:table\|column\|label\|unit\|step` belongs to the **check item or `sw_item_heading` above it** (`sw_item_details` lines may stand between); an item or heading may have several, shown in file order. A heading with calculations shows the band under its title, so one item can offer more than one set of values (for example maximum and long range cruise). `table` and `column` (an output column) are required; the label is the column name when left out, the unit is empty, and the shown value is rounded to a multiple of `step` (`0.1`, `1`, `10`; default `1`). Not under a check item or heading: `Line N: sw_calculate is not under a check item or heading; ignored`. A table or column that does not exist (checked once the whole file is read): `Line N: sw_calculate names the unknown table "x"; ignored` or `Line N: table "x" has no output column "y"; sw_calculate ignored`. A step that is not a number above 0 warns and `1` is used. The line adds no item, is not counted and takes the gate of its item. | **Design** | same |
| L7 | The value is looked up **live** from the current values of the input sources and is never saved or frozen. It is a **multilinear interpolation** between the grid points around the inputs: on each input column the two row values either side of the input are used, and the corner values are weighted by how near the input is to each. An input exactly on a row value gives that row's output. | **Design** | D-83; `test/domain/use_cases/calculate/calculate_line_value_use_case_test.dart` |
| L8 | An input beyond the first or last row value of its column is **held at that edge** (the value is the edge's, not an extrapolation) and the result names each such input with its value now, the edge used and the side (`LimitExceeded`). A column with a single row value matches only that value; any other input is outside. The display says it as `Altitude 32,000 ft is above the 30,000 ft limit: using 30,000 ft.` (the label and unit of L1, or the column name). | **Design** | same; `test/ui/checklist_detail/calculated_lines_band_test.dart` |
| L9 | An input with no value (the dataref is unavailable, the link is down or stale, or the number is not finite) gives **no value** (N4); so does an expression that divides to infinity. The result is the number rounded to a multiple of the line's `step`, with no floating point noise (`36.9`, not `36.900000000000006`). A calculated value never ticks an item and never changes the progress. | **Design** | same |
| L10 | The `sw_calculate` lines of an item are shown in one **band** under it, in the colour of the details lines. It is not an item: not counted, no check circle, no tap, no skip, and not in the saved progress. A warning for each input beyond the table (L8) comes first, on an amber pill with the caution icon; then the **first** line large (the number, then its unit and label small); then each other line as a row, label on the left and number and unit on the right. A line with no value shows `no data` (the large line shows an em dash and `<label> · no data`). Numbers have thousands separators and as many decimals as the line's step has. With no sim connected every line has no value. | **Design** | D-83; `test/ui/checklist_detail/calculated_lines_band_test.dart` |

## 5d. App extension: challenge-response rows

`sw_challenge` is not in XChecklist. It marks rows to be read as a **challenge and a response** by the voice (D-84): the app reads the item, the pilot answers, and a dataref (if the item has one) verifies it. Rows outside a block are **flow** rows: the voice reads the next item and waits for the pilot to do it. The text of the rows is the same in both kinds. A file that uses it is for this app only; the real plugin is expected to warn about the unknown keyword and show every item (not run).

```
sw_checklist:Before start:Before start
sw_item:Parking brake|SET            a flow row
sw_challenge: ON
sw_item:Beacon|ON                    challenge rows
sw_item:Fuel quantity|CHECK
sw_challenge: OFF
sw_item:Flaps|SET                    a flow row again
```

| # | Rule | Status | Evidence |
|---|---|---|---|
| C1 | `sw_challenge: ON` opens a block and `sw_challenge: OFF` closes it; the value is `ON` or `OFF` in any case and the line makes no item. Every row between them (check items, switch rows, notes, headings and details lines) is a challenge row; the model carries this as a flag on the row, which is not part of the file syntax. Keywords ignore case (K1). | **Design** | D-84 |
| C2 | A block lies inside one checklist; there may be any number in a checklist. A block still open at the next `sw_checklist` or at the end of the file is closed there with `Line N: sw_challenge: ON has no OFF; closed at the end of the checklist` (N is the line of the start). | **Design** | same |
| C3 | `sw_challenge: OFF` with no open block warns `Line N: sw_challenge: OFF without ON`; `sw_challenge: ON` inside an open block warns `Line N: sw_challenge: ON inside a challenge block; ignored`. Each does nothing else. | **Design** | same |
| C4 | A value other than `ON` or `OFF`, or none, warns `Line N: sw_challenge needs ON or OFF; ignored`. | **Design** | same |
| C5 | A challenge block and a switch block (section 5b) may nest, in either order, if the inner one ends before the outer one. A challenge block that opens inside a switch branch is closed at that branch's `sw_else` or `sw_end`, and a switch block that opens inside a challenge block ends before it, with `Line N: sw_challenge crosses a switch block; closed at the block boundary` when they cross. | **Design** | same |
| C6 | For a `sw_continue` look-ahead (F3) the line is skipped like a comment: it is not an item. | **Design** | same |

## 6. Colour markers

| # | Rule | Status | Evidence |
|---|---|---|---|
| C1 | In `sw_item_c` and `sw_itemvoid_c` a colour marker `\name\` is removed. The text between markers stays in the plain `label`/`result`. The same text is also kept as ordered colour runs: a marker colours the text after it until the next marker (several colours per label), and the label and the result are coloured independently (the colour does not carry across the `\|`). Text before the first marker has no colour. The real plugin reads markers **only** in `_c` lines (the manual says so, and the lexer enters its colour state only for them); on `sw_item`, `sw_itemvoid`, `sw_iteminfo` and `sw_remark` it shows the backslashes literally. We read markers on all of them, a deliberate tolerance (K1 style): the one such line in the corpus is `sw_itemvoid:\magenta\About 1000' AGL`. | **Confirmed** for `_c`; the tolerance is **Assumed** | 0.8: 5796 colour lines; user manual (colour section); `chkl.l` states `CDESC`/`CVOID` |
| C2 | A marker is a backslash, one or more characters other than `\`, `:` and `\|`, and a closing backslash. | **Assumed** (exact pattern) | the real lexer takes any text between two backslashes |
| C3 | `\\` (two backslashes) is a return marker, **not** an escaped backslash. Markers form a stack: each `\name\` pushes its colour and `\\` pops it, so the following text returns to the colour before the last marker, or to the default colour if the stack is empty. Example: `\a\x\b\y\\z` gives x in a, y in b, z in a. The stack starts empty for each label and each result. A lone backslash that is not part of a marker is literal text. Both `\\` and `\name\` are removed from the plain text. | **Confirmed** | `chkl.l` (`TOKEN_BACKSLASH`), `parser.cpp` `coloured_string::resolve_colours` ("back through the stack"). 0 uses in the corpus; the earlier "1 line" evidence was wrong |
| C4 | `_c` keywords without any marker are valid and are parsed like their plain forms. | **Confirmed** | 0.8: 51 lines |
| C5 | `sw_define_colour:name:r,g,b` stores `name` with three floats in a file-level palette. Spaces around values are trimmed. The **first** definition of a name wins; a repeat warns `Line N: duplicate colour "X"; first definition kept` (the plugin's name map does not overwrite). A component below 0 or above 1 is clamped to 0 or 1 with one warning per line, `Line N: colour component out of range; clamped` (as the plugin does). A malformed value (empty name, not exactly three numbers, or a non-finite number) warns `Line N: bad colour definition` and is skipped. | **Confirmed** (shape, first-wins and clamping from `parser.cpp`); warning texts are ours | 0.5: 201 lines; user manual: `sw_define_colour:red:1.0,0.0,0.0`; corpus has no repeats and no out-of-range values |
| C6 | A marker name that is never defined anywhere in the file warns `Line N: unknown colour "X"` (once per name per line) after the whole file is read. The run keeps the name and the UI uses the default colour. Names are matched exactly (case sensitive). A colour defined after its use is accepted (the plugin would not know it yet; we are more tolerant). | **Confirmed** (plugin warns `Unknown colour`); the tolerance is **Assumed** | `parser.cpp` `get_colour_index`; corpus: 2 undefined names, both in `ERJ_clist.txt` |

## 7. Continue links and order

| # | Rule | Status | Evidence |
|---|---|---|---|
| F1 | `sw_continue` belongs to the open checklist and adds a continue link. The value is the text before the next `:` (a dataref condition after it is dropped), trimmed. Several `sw_continue` lines may follow one another; the links keep file order. Bare means the next checklist. `sw_continue:Name` means the checklist whose `Name` matches exactly (not the menu text). | **Confirmed** | ChangeLog 1.12 and 1.16; 508 lines in the corpus: 126 bare, 382 named; runs of several in `ATR42_clist.txt` |
| F2 | `sw_continue` with no open checklist warns `Line N: item before any checklist` and is skipped. | **Assumed** | |
| F2a | A **named** `sw_continue` is valid if a checklist with that `Name` exists anywhere in the file, before or after it, so the parser collects all checklist names before checking. Its position inside the checklist does not matter. | **Confirmed** | 381 of 382 named lines resolve, including the 3 at end of file; the exception is `<<ENGINES START 2of2>>>` in `FlyJsim_Q4XP_clist.txt` |
| F2b | A **bare** `sw_continue` is valid only if the next significant line is a `sw_checklist`. Blank lines, `#` comments and further `sw_continue` lines are skipped when looking. If the next line is anything else (another `sw_` keyword, an unknown line) or the file ends, it is misplaced: dropped with a warning. | **Confirmed** (all 126 bare lines satisfy it); the rule is a design decision | corpus check |
| F3 | A valid named `sw_continue` should be at the end of its checklist. If an item or note line (`sw_item`, `sw_item_c`, `sw_itemvoid`, `sw_itemvoid_c`, `sw_iteminfo`, `sw_remark`, `sw_item_heading`, `sw_item_heading_c`, `sw_item_details`, `sw_item_details_c`) follows it, ignoring blank lines, comments and further `sw_continue` lines, the warning `Line N: sw_continue should be at the end of its checklist` is added. The link is kept and the items still belong to the checklist. | **Confirmed** (real checker accepts it); the warning is a design decision | probe: the real checker reports 0 errors and 0 warnings for `sw_continue:B` followed by items. No file in the corpus does this |
| F4 | Invalid links are dropped (the checklist and its items stay) with a warning: `Line N: continue target "X" not found` for an unknown name, and `Line N: sw_continue without a name is not followed by a checklist` for a misplaced bare one. A checklist dropped for having no items is not a valid target, so a bare `sw_continue` directly before one also warns `Line N: continue target "X" not found`. Loops are not an error (branches may go back); the sequence helper guards against them. | **Assumed** | |
| F5 | File order is not flight order. `ChecklistDocument.checklists` stays in file order; a pure domain helper follows the continue links to give the sequence. | **Assumed** (design) | files list pages in any order |

## 8. Conditions

Where this section says **Confirmed**, the rule was checked in the source of the real parser and plugin (`external/xchecklist/src/`: `chkl.l`, `chkl.y`, `parser.cpp`, `Xchecklist.cpp`) and, where a fixture is named, run through the real checker in `Documentation/Testing/real_checker/`. Fixtures are in `testing/fixtures/conditions/`. **Assumed** means a design choice of this app, or a case the checker cannot evaluate. A *condition* is the text after the dataref colon; an *atom* is one comparison inside it. Counts are from a census of the surveyed files (not published) (5315 conditions, 8825 atoms in the 27 files).

### 8.1 Where a condition appears

| # | Rule | Status | Evidence |
|---|---|---|---|
| W1 | On `sw_item`, `sw_item_c` and `sw_iteminfo` lines the condition is the text after the first `:` that follows the label and the optional `\|result` (the split of I2 and I3). A colon with nothing after it, or no colon, means no condition and no warning. | **Confirmed** | `chkl.y` 183 to 207; census 5221 lines; fixture `malformed` (empty condition accepted) |
| W2 | `sw_show:CONDITION` has a condition and no label. A `sw_show` with no condition is a syntax error. | **Confirmed** | `chkl.y` 235; census 50 lines in 8 files |
| W3 | `sw_continue:Name:CONDITION` has the condition after the second colon. `sw_continue` and `sw_continue:Name` have none (an unconditional link). | **Confirmed** | `chkl.y` 239 to 252; census 44 of 521 lines |
| W4 | `sw_itemvoid`, `sw_remark` and `sw_checklist` take no condition; colons there are not condition separators (N1, H1). | **Confirmed** | `chkl.y` rules for those lines |
| W5 | An `sw_iteminfo` condition has the same grammar. In the plugin such an item cannot be ticked by the user and is checked by its condition. In this app `sw_iteminfo` is a note (I7), so its condition is parsed but not evaluated. | Grammar **Confirmed**; not evaluating is **Assumed** (design) | `parser.cpp` `chk_item(..., false)`; census 38 lines |

### 8.2 Structure of a condition

| # | Rule | Status | Evidence |
|---|---|---|---|
| X1 | A condition is atoms joined by `&&` (and) and `\|\|` (or). `&&` binds tighter than `\|\|`, so `a \|\| b && c` is `a \|\| (b && c)`. | **Confirmed** | `chkl.y` 315 to 328; fixture `logic` (precedence cases agree with the checker) |
| X2 | An atom may be wrapped in parentheses and groups nest without limit: `((a)\|\|(b))&&(c)`. The corpus goes two deep (16 conditions). | **Confirmed** | `chkl.y` 325 to 328; fixture `logic`; census |
| X3 | Blanks between tokens are skipped: `(a:1) && (b:2)` is valid (70 corpus conditions use it). Blanks inside a dataref name belong to the name; this app trims them. | Skipping **Confirmed**; trimming **Assumed** | `chkl.l` (`<*>[[:blank:]]+`, `DATAREF` allows blanks); fixture `logic` (`spaces around and`) |
| X4 | There is **no logical not**. A `!` in front of a value means "not equal" (O2), never "not true". | **Confirmed** | `chkl.y` `rel_operation`; census (`!` 183, `!=` 11) |
| X5 | A condition may start with a second `:` and then use `(expression OP expression)` groups, with `&&` and `\|\|`, where both sides are expressions and no dataref name stands on the left: `:({a}=={b})`. Rare (2 lines, both in the upstream test file). | **Confirmed** | `chkl.y` 295 to 314; fixture `logic` (the two `a OP b` cases agree) |
| X6 | A number may stand where the dataref name goes: `1:closer_than({a},{b},2)` compares the constant 1 with the function (28 atoms). | **Confirmed** | `chkl.y` 344 (`dataref_name: TOKEN_NUMBER`); fixture `plain_values` (`closer_than` cases agree) |

### 8.3 Comparisons

| # | Rule | Status | Evidence |
|---|---|---|---|
| O1 | `name:V`, `name:=V` and `name:==V` mean equal. Equal means `abs(x - V) < 1e-6` (absolute, in double). So 0.1 + 0.2 equals 0.3, a single-precision 0.1 equals 0.1, 1.0000009 equals 1 and 1.0000011 does not. | **Confirmed** | `parser.cpp` 476 to 482 (`operator==`); fixture `plain_equal` (13 items, all agree except "no value yet") |
| O2 | `name:!V` and `name:!=V` mean not equal, which is the negation of O1. | **Confirmed** | `parser.cpp` 530 to 532; fixture `plain_not_equal` |
| O3 | `<`, `>`, `<=`, `>=` compare the two doubles directly, **with no tolerance**: `<=10` is false for 10.0000001. | **Confirmed** | `parser.cpp` 536 to 547; fixture `plain_order` (at, just below and just above the bound) |
| O4 | `name:A\|B` means inside the range: `A <= x <= B`, both ends included. With `A > B` it is never true. Blanks around the bar are allowed. | **Confirmed** | `parser.cpp` 548 to 551; fixture `plain_range`; census 271 atoms |
| O5 | `name:A:B` is a **crossing** and needs memory. If `A < B` (rising): the condition arms when `x <= A`, becomes true when it is armed and `x >= B`, and stays true until `x <= A` again. If `A >= B` (falling) the same with the directions swapped (arms at `x >= A`, true at `x <= B`). A value that starts between A and B and never goes beyond A is never true. | **Confirmed** | `parser.cpp` 484 to 521 (`checkTrig`); fixture `crossing` (6 cases agree); `regres_test1.txt` item 006; census 90 atoms |
| O6 | `+>n`, `-<n` and `><n` are changes against a **baseline**: `x - base > n`, `base - x > n`, `abs(x - base) > n`, all strict. The baseline is the value at the first evaluation after the condition was reset, so that first evaluation compares the value with itself and is not met (for `n >= 0`). With no value at the baseline moment there is no baseline and the condition is not met. | **Confirmed** | `parser.cpp` 555 to 585; fixture `change` (14 cases agree); census 542 atoms in 19 files |
| O7 | The plugin **latches** a met item condition: when the condition holds for the current item, the item is checked and the plugin moves on; the condition is not looked at again, so a value that returns does not uncheck the item. | **Confirmed** | `parser.cpp` 810 to 850 (`chk_item::do_processing`, state `PROCESSING`); fixture `change` (`latched`: the checker reports the item checked at the second step) |
| O8 | The plugin evaluates only the **current item**, the first item not yet done; later items are not looked at until they become current, and their baseline starts then (`chk_item::activate` resets the condition). This app does the same since D-71: it evaluates only the pointer item (the first unchecked check item at or after the checklist's cursor) and a change or crossing baseline starts when the item first becomes the pointer item. The pointer also follows the pilot's manual ticks, which the plugin has no equivalent of. | Plugin **Confirmed**; the app's pointer rule **Confirmed** on a live run beside XChecklist 1.52 (five states, same ticks; change operators not exercised live) | `parser.cpp` 795 to 806, 919 to 957; D-71; `Documentation/Testing/MANUAL_TEST.md` AC-47 |
| O9 | In the plugin each atom keeps its own state, and `&&` and `\|\|` stop at the first decisive atom, so an atom behind it is not evaluated (and its baseline or crossing state does not start) until then. This app evaluates every atom at every step. The difference can show only with `+>`, `-<`, `><` or `a:b` atoms inside a longer condition, for example `(x:><0)\|\|(y:><0)`; 104 corpus conditions combine one of them with `&&` or `\|\|`. | Plugin **Confirmed**; the app's rule is **Assumed** (design) | `parser.cpp` 1202 to 1210 |

### 8.4 Right side

| # | Rule | Status | Evidence |
|---|---|---|---|
| V1 | A number is an optional sign, digits, an optional fraction and an optional exponent: `5`, `+5`, `-5`, `.5`, `0.75`, `1.0e-3`, `1e2`. Corpus: 7438 integers, 1247 decimals, 4 exponents. | **Confirmed** | `chkl.l` number rules; fixtures `plain_equal`, `plain_values` |
| V2 | The right side may be arithmetic: `+ - * / **` (`**` is power) with the usual precedence (`**` first, then `* /`, then `+ -`), parentheses and unary `+` and `-`: `((1+2)*3)**4`. | **Confirmed** | `chkl.y` 370 to 413; fixture `plain_values` (seven arithmetic cases agree); census 38 atoms |
| V3 | `{name}` or `{name[n]}` is another dataref's current value (23 atoms): `x:>{y}`. | **Confirmed** | `chkl.l` (`<NUM>\{...\}`); fixture `plain_values` |
| V4 | Functions: `round(x)` (nearest integer), `step(x)` (1 when `x >= 0`, else 0) and `closer_than(a,b,eps)` (1 when `abs(a-b) < eps`, else 0). Any other name is an error (`Function X not supported!`) and the condition is never true. Corpus: `closer_than` 66, `round` 5, `step` 1. | **Confirmed** | `parser.cpp` 1309 to 1383; fixture `plain_values` (`round`, `step`, `closer_than` agree); fixture `malformed` (unknown function) |
| V5 | A cast `(int)`, `(float)` or `(double)` in front of a primary changes its type: `int` truncates toward zero, `float` rounds to single precision. The dataref on the left is read with the type of the first right-side value (double unless a cast says otherwise). Corpus: 3 atoms, all in the upstream test file. | **Confirmed** | `parser.cpp` 1398 to 1411, 345 to 359; fixture `plain_values` (`int cast`) |
| V6 | Every value is a double. A float dataref is widened (0.1f becomes 0.10000000149), which is why O1 has a tolerance. | **Confirmed** | `Xchecklist.cpp` 1708 to 1733 |
| V7 | There are **no string comparisons**. The grammar has no string value and no corpus line compares text. A string or byte-array dataref cannot be used in a condition. | **Confirmed** | `chkl.y`; census (no non-numeric right side) |

### 8.5 Names, arrays and missing values

| # | Rule | Status | Evidence |
|---|---|---|---|
| N1 | A dataref name is the text up to the `:`, with no `: \| [ ] ( ) &` in it, optionally followed by `[n]` where `n` is a whole number (an array element). 2577 corpus atoms use it; none uses a name or a computed index. | **Confirmed** | `chkl.l` (`DATAREF`), `chkl.y` 344 to 358; census |
| N2 | An array element is read as an element of a float array or an int array, whichever the dataref has (a float array when the right-side type is float or double). A name that is not an array dataref is looked up again as the full name `name[n]` (the Carenado style). | **Confirmed** | `Xchecklist.cpp` 1797 to 1831; `parser.cpp` 403 to 435 |
| N3 | In the plugin a dataref that does not exist, or an array index past the end, **reads as 0.0** and the condition is evaluated with that value. A warning is logged once. So `x:0` is met for a dataref that is not there. | **Confirmed** | `parser.cpp` 319 to 328 (`d = 0.0; return true`); `Xchecklist.cpp` 1735 to 1749 (`!= 1` gives 0.0); the checker agrees: every "unknown" fixture case is evaluated with 0 |
| N4 | **This app does not use N3.** A condition that needs a value the app does not have (`unknown_name`, an index past the end, no value yet, stale stream) is `unknown`: it is never met, never suggests a checklist and never ticks an item. A condition is never partly evaluated: one missing value makes the whole condition `unknown`, even when another atom is decisive (`(a:1)\|\|(b:1)` with `a` = 1 and `b` missing is `unknown`). | **Assumed** (design, plan 4.1; decision D-63) | fixtures `plain_equal`, `arrays`, `logic` (the `unknown` cases differ from the checker on purpose) |
| N5 | **App extension, not in XChecklist:** the left side may be an array range `name[a..b]` (whole numbers, `a <= b`, at most 128 elements). The rest of the atom (operator and value, `a\|b`, `a:b`, `+>`) is applied to each element and the results are and-ed: all elements must hold. `x[0..2]:0` is `(x[0]:0)&&(x[1]:0)&&(x[2]:0)`; `x[3..3]` is `x[3]`. A backwards range, or one with more than 128 elements, is a malformed condition (M2). A range is not allowed on the right side `{...}`. An index past the real end of the array reads as no value (N4), so the whole condition is `unknown`; `tools/clist_snapshot.dart` lists such an item as `PAST END`. On the wire the data layer sends consecutive elements as one range subscription (D-79, `PROTOCOL.md` section 10); the parser itself only expands. The real XChecklist plugin does not understand the form, so a file that uses it is for this app only. | **Design** (user request) | `condition_expression_parser_test.dart` (array ranges) |
| N6 | **App extension, not in XChecklist:** a name may be **quoted**, with `"` or `'`, and then holds anything except its own quote character and square brackets: `"A:GENERAL ENG MASTER ALTERNATOR:1, bool":1`. The text between the quotes, trimmed, is the name as it goes on the wire; it is not read for `:`, `\|`, `&`, `(`, `)` or `,`. A quote counts only where a name begins (the left side of an atom, the right side of a comparison, inside `{...}`, and in a `sw_table` input source after the `=`); a quote anywhere else (`Pilot's seat`, a label such as `Pilot's OAT`) is plain text. A quoted name stands on its own as a value (`x:>"L:y"`, `{"L:y"}` and `"L:y"` all read the same). There are no escapes and no array index or range on a quoted name: any index is part of the text, and a `[` or `]` inside the quotes is `square brackets in a quoted name`. An unterminated quote is `unterminated quote`, a blank name `empty name in quotes`, and a quoted name with no `:` after it `missing ":" after the name` (M2). In a `sw_table` line a quoted name may hold a comma but not a `\|`. Unquoted names are read exactly as before (N1). The first use is a simulator whose variable names hold colons and commas (MSFS: `L:NAME`, `A:NAME:1, bool`). The real XChecklist plugin does not understand the form, so a file that uses it is for this app only. | **Design** (user request, D-85) | `condition_expression_parser_test.dart`, `aircraft_workflow_parser_conditions_test.dart`, `lookup_table_parser_test.dart` (quoted names) |
| N7 | **Microsoft Flight Simulator: a missing L-variable reads 0 (exception to N4).** SimConnect has no error for an `L:` variable that does not exist: it reads `0`, the same as one that is 0 (D-86). The companion cannot report it, so an item whose condition expects the value 0 of a misspelled L-variable is met at once; an item that expects another value never ticks. A `Z:` variable (a variable private to the aircraft's model, for example a door handle) reads `0` the same way when it does not exist, so N7 covers it too. A misspelled A-variable or B-variable is `unknown_name` and follows N4. `tools/msfs_lvar_check.dart` checks the `L:` names of a checklist against the aircraft's own files. L-variable names are case-insensitive, so `L:Foo` and `L:FOO` are one variable. | **Measured** (D-86, D-88) | `plugin/PROTOCOL.md` section 11 |

### 8.6 `sw_show`

| # | Rule | Status | Evidence |
|---|---|---|---|
| S1 | `sw_show` is **not an item and hides nothing**. It adds a condition to the checklist it stands in. Every item of that checklist is shown whatever the condition says. | **Confirmed** | `parser.cpp` 712 to 731 and 1092 (`show_item::getDesc` returns false: it is not drawn); manual ("allows a checklist to pop up"); real checker, fixture `show` (the items of every checklist run) |
| S2 | A checklist's show condition is all its `sw_show` lines **and-ed**. They may stand anywhere in the checklist, in any number. A checklist with no `sw_show` never pops up. | **Confirmed** | `parser.cpp` 736 to 756; ChangeLog 1.06; fixture `show` (`two lines`, `at the end`) |
| S3 | While no checklist is displayed, the plugin opens ("pops up") the first checklist whose show condition holds. Once it has opened a checklist it does not open it again until that checklist's condition has been false and true again. Opening a checklist resets its conditions. | **Confirmed** | `parser.cpp` 758 to 790 (`do_processing`), 953 to 960, 736 to 756 (`trigger_block`); the checker walkthrough opens exactly the true ones: `Show combined`, `Show with a check condition`, `Show at the end`, never `Show false`, `Show unknown` or `Show two lines` |
| S4 | A missing dataref makes the plugin's show condition false in the usual case (`x:1` with `x` read as 0). | **Confirmed** | N3; fixture `show` (`Show unknown` is never opened) |
| S5 | In this app `sw_show` is **not supported**: the parser ignores the line like a comment (no warning, no model data, no effect), so nothing is suggested and no checklist opens by itself. | **Superseded** (design; D-70 replaces the earlier suggested-marker rule, D-57) | decision D-70 |

### 8.7 `sw_continue`

| # | Rule | Status | Evidence |
|---|---|---|---|
| J1 | The `sw_continue` lines of a checklist form one list in file order. Their position among the items does not matter: a link placed before the last item behaves as one at the end (the items still run first). | **Confirmed** (plugin and live in the app, manual test AC-38 Case 4) | `parser.cpp` 1158 to 1161, 919 to 957; fixture `continue` (`Misplaced`: the checker runs both items and then follows the link) |
| J2 | The list is evaluated **once**, when the last item of the checklist is done, top to bottom. The first link with no condition, or whose condition holds, is followed. | **Confirmed** (plugin and live in the app, manual test AC-38 Cases 1 to 3: the first matching link wins, the unconditional last) | `parser.cpp` 934 to 944; manual 509 to 530; fixture `continue` (`Order test` follows the first of two true links; `Second` skips a false link and follows the unconditional one) |
| J3 | Each condition is reset just before it is evaluated, so the change operators `+>`, `-<`, `><` and the crossing `a:b` can never hold in a link (O6, O5). | **Confirmed** | `parser.cpp` 938; manual ("always evaluate false"); fixture `continue` (`After none`) |
| J4 | When no link matches, the plugin does not jump by itself. Its Next action then goes to the next checklist **in file order**. | **Confirmed** | `parser.cpp` 690 to 706 (`next_checklist`); fixture `continue` (`Last hit` is followed by `After none`) |
| J5 | A bare `sw_continue` goes to the next checklist in file order and an unknown target label warns and also goes to the next one. This app drops an unknown target with a warning instead (F4). | **Confirmed** (plugin); the app's rule is **Assumed** | `parser.cpp` 690 to 706; fixture `continue` (`Bare`) |
| J6 | A link whose condition is `unknown` is not followed (N4). | **Assumed** | plan 6.4 |

### 8.8 Malformed conditions

| # | Rule | Status | Evidence |
|---|---|---|---|
| M1 | A syntax error makes the real plugin reject the **whole file**; the checker prints every error. The error recovery can also swallow the next line. | **Confirmed** | `parser.cpp` 1106 to 1130 (`errors_found`); fixture `malformed` (27 errors from the malformed lines) |
| M2 | This app keeps the file. An item whose condition cannot be parsed stays a manual item and the document gets the warning `Line N: condition not supported: <reason>` (N counts physical lines, T1). Reasons: `unbalanced parentheses`, `missing value`, `unexpected ")"`, `unexpected text "X"`, `unknown function "X"`, `missing condition after "&&"` (or `"\|\|"`), `missing ":" after the name`. A condition that does not parse is never partly used. | **Assumed** (design; the wording is ours) | fixture `malformed` (the expected file lists the warnings) |
| M3 | Some malformed text is accepted by the real parser: an unknown character such as `~` is skipped, so `x:~5` is read as `x:5`, and text after a complete value (`1 foo`) is a syntax error but the part before it is kept. This app warns in both cases and keeps the item manual. | **Confirmed** (plugin); the app's rule is **Assumed** | fixture `malformed` (`unknown operator`, `stray text`) |
| M4 | Three corpus lines are rejected by `chkl.y` (an empty value, a label pasted into a condition, `(a:1):(b:2)`) and get an M2 warning; the other 5312 are accepted. | **Confirmed** | the survey census (not published; unparsed rows) |

## Changelog: where reality differed from the plan

Each entry names the plan text that was edited to match (`Documentation/Plan/PLAN.md`).

1. **Comments.** The plan treated `#` and `//` as comments. Only `#` is used and only `#` is a comment (T6, T7). `//` and `;` lines are unrecognized lines with a warning. Plan section 2 and parser step 2.2 edited. The `//` line in `messy.txt` now produces an "unrecognized line" warning.
2. **Dataref and no-pipe items.** The plan's rule (result = text before the first `:` after the pipe) is confirmed for items with a pipe (I2). Items whose first `:` comes before any `|` were not covered. They take their label from the text before the first colon, and the result is empty (I3). Plan section 2 edited. `sw_item:Time: now|OK` gives label `Time`, not `Time: now`, because keeping the colon text would show dataref text and break acceptance criterion 4.
3. **More keywords.** The plan listed three keywords. The corpus has 13 (K2, K3, K4). `sw_item_c` is the most common item keyword. Plan section 2 edited. Colour markers and the colour, info and remark variants were added to the parser.
4. **Notes can have a result.** `sw_itemvoid` takes `Text|Text2` (N1), so a note is not always label-only. Plan section 2 changed.
5. **`@` is confirmed.** It means "do not speak" and is stripped (T9). No plan change.
6. **Case.** The plan matched keywords case-insensitively. The real plugin is case sensitive, and no real file uses upper case. The tolerance is kept as an extension (K1).
7. **Latin-1.** No real file needs it (T3). The fallback is kept as a safety net.
8. **Whitespace.** The real plugin keeps padding; we trim (T4), as the plan said.
9. **Title.** The plugin shows the first part of `sw_checklist` as the window heading and the second as the menu entry. Our list screen is the menu, so the plan's "menu text is the title" rule stays (H2).
10. **Line endings.** Lone CR files exist in the corpus (T1), confirming the plan's normalization step. Whether the real checker counts a lone CR as one line is unverified (see `real_checker/README.md`).
11. **Colours, continue and show.** The plan and the first grammar ignored `sw_define_colour`, `sw_continue` and `sw_show` and removed colour markers without keeping them. Now colours are kept as runs plus a palette (C1, C5, C6), `sw_continue` is parsed into an ordered list of continue links, validated against all checklist names (F1 to F5), so the sequence does not depend on file order, `sw_show` warns as unsupported (K6) and only `sw_rcolsize` is ignored silently (K3). Plan sections 2, 5 and 6 and ARCHITECTURE section 6 edited.
12. **Colour details checked against the manual and the plugin source.** `\\` is a return marker on a colour stack, not an escaped backslash (C3). The first definition of a colour wins and out-of-range components are clamped with a warning (C5). An unknown colour name warns (C6). Only `_c` keywords read markers in the real plugin; we keep reading them everywhere (C1).

13. **Conditions.** Section 8 pins the whole condition grammar against the real parser, plugin and checker. Two plan assumptions were wrong: `sw_show` is a condition on a whole checklist that pops it up, it does not hide items (S1 to S5), and a missing dataref reads as 0 in the plugin, not unknown (N3, N4). Plan sections 4.1, 5, 6.4 and decisions D-54, D-57 are amended.
