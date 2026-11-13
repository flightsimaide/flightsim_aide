# Condition fixtures

Hand-written, license-free checklists that pin the XChecklist condition grammar (decision D-48, `Documentation/Reference/GRAMMAR.md` section 8). Every case is three files with the same base name:

| File | Content |
|---|---|
| `<name>.txt` | The checklist in XChecklist format, one form of condition per file or per small group. Dataref names are `fx/<name>/<case><letter>` so no two items share a value. |
| `<name>.values.json` | The dataref values. Either a flat object, dataref name to number: `{"fx/plain_equal/01a": 1, "fx/arrays/02a[3]": 1}`; or `{"steps": [ {...}, {...} ]}` for conditions that need history. A name that is absent means "no value" (unknown). An array element is `name[i]`. |
| `<name>.expected.json` | What the evaluator must produce for those values (shape below). |

## Steps

A file with `"steps"` is evaluated in order, **once per step**, by one evaluator whose per-item state starts empty before step 1. Step 1 is the activation moment: the first evaluation, which sets the baseline of `+>`, `-<`, `><` and arms or does not arm a crossing `a:b` (`GRAMMAR.md` O5, O6). The expected result is what the evaluator reports **after the last step**. A name absent from a step keeps its earlier value; `null` means the value is gone (no value) from that step on. A flat object is a single step.

## Expected file

```json
{
  "source": "where the expected results come from",
  "met":     [0, 1],
  "not_met": [2],
  "unknown": [3],
  "continue": { "<checklist name>": "<target checklist name>" },
  "warnings": ["Line 12: condition not supported: unbalanced parentheses"]
}
```

- `met`, `not_met`, `unknown`: item indexes counted over the **check items of the file** (`sw_item` and `sw_item_c` lines) from 0, in file order. An item with no condition, or whose condition could not be parsed, is in none of the lists.
- `continue`: for each checklist that has `sw_continue` lines, the checklist the links lead to when the checklist is finished, or `null` when no link matches (`GRAMMAR.md` J2). The names are `sw_checklist` names.
- `warnings`: the document warnings the parser must add, in file order, with the physical line number (`GRAMMAR.md` M2, F3).
- Results are `met`, `not_met` or `unknown`. `unknown` is the app's rule for a condition that needs a value it does not have (`GRAMMAR.md` N4); the real plugin reads such a value as 0.

## Where the expected results come from

Each file's `source` says so. For the item results the real XChecklist checker in `Documentation/Testing/real_checker/` was run on every case (`Documentation/Testing/real_checker/run_real_checker.py`): the results are recorded in `Documentation/Reference/GRAMMAR.md` section 8. The expected files agree with the checker except where the app deliberately differs (the `unknown` cases) and one checker limitation (its float arrays truncate to whole numbers); the early experiment write-up (not published) lists every difference.

## Files

| Name | Form |
|---|---|
| `plain_equal`, `plain_not_equal`, `plain_order`, `plain_range`, `plain_values` | comparisons, tolerance, ranges, the right side (arithmetic, other datarefs, casts, functions) |
| `change`, `crossing` | change since activation (`+>`, `-<`, `><`), crossing `a:b` |
| `arrays`, `logic` | `name[n]`, `&&`, `\|\|`, grouping, precedence, the `:(a OP b)` form, unknown inside a larger condition |
| `continue` | conditional and unconditional `sw_continue`, order, position, no match |
| `malformed` | unbalanced parentheses, missing operand, stray text, unknown function and so on; each adds a warning |

`tools/check_fixtures.sh` checks that every `.txt` has both sibling files, that the JSON parses and that every index and checklist name in an expected file exists in the checklist (`tools/check_condition_fixtures.dart`). `testing/fixtures/condition_fixtures.dart` (a helper, not a test) lists the cases and reads them; `test/testing/condition_fixtures_test.dart` checks that the files pair up and the JSON parses (task 1.7). AC-31 and AC-32 run every case.
