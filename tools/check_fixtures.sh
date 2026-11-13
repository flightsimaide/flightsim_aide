#!/usr/bin/env bash
# Proves each fixture actually exercises what it is supposed to exercise.
set -u
cd "$(dirname "$0")/.."
F=testing/fixtures
fail=0
STRICT=0; [ "${1:-}" = "--strict" ] && STRICT=1   # --strict: all four fixtures must exist
have() { [ -s "$F/$1.txt" ]; }
need() { # description file grep-args...
  local desc=$1 file=$2; shift 2
  if ! grep -qE "$@" "$file" 2>/dev/null; then echo "FIXTURE FAIL [$file]: $desc"; fail=1; fi
}
for f in minimal messy lookalike_aircraft; do
  if ! have $f; then
    if [ $STRICT -eq 1 ]; then echo "FIXTURE MISSING/EMPTY: $F/$f.txt"; fail=1; else echo "(skipping $f.txt - not created yet)"; fi
  fi
done

# minimal: tiny and clean
if have minimal; then
[ "$(wc -l < $F/minimal.txt)" -le 12 ] || { echo "FIXTURE FAIL [minimal]: more than 12 lines"; fail=1; }
need "has a checklist" $F/minimal.txt '^sw_checklist:'
need "has an item"     $F/minimal.txt '^sw_item:'
if grep -qE '^(#|//|@)' $F/minimal.txt; then echo "FIXTURE FAIL [minimal]: must have no comments or @"; fail=1; fi
fi

# messy: must contain every awkward case from PLAN.md section 2
if have messy; then
if ! grep -qU $'\r' $F/messy.txt; then echo "FIXTURE FAIL [messy]: no CRLF line endings"; fail=1; fi
need "blank line"                 $F/messy.txt '^[[:space:]]*\r?$'
need "# or // comment"            $F/messy.txt '^[[:space:]]*(#|//)'
need "leading @"                  $F/messy.txt '^[[:space:]]*@'
need "space after colon"          $F/messy.txt '^[[:space:]]*@?sw_checklist: '
need "dataref suffix on an item"  $F/messy.txt 'sw_item:[^|]*\|[^:]*:[^:]+'
need "item without pipe"          $F/messy.txt '^[[:space:]]*@?sw_item:[^|]*\r?$'
need "sw_itemvoid"                $F/messy.txt 'sw_itemvoid:'
need "unknown keyword"            $F/messy.txt '^[[:space:]]*@?(sw_unknown|bogus_keyword):'
need "mixed-case keyword"         $F/messy.txt '^[[:space:]]*@?(SW_ITEM|Sw_Item|SW_CHECKLIST):'
first_checklist=$(grep -nE '^[[:space:]]*@?sw_checklist:' $F/messy.txt | head -1 | cut -d: -f1)
first_item=$(grep -nE '^[[:space:]]*@?sw_item:' $F/messy.txt | head -1 | cut -d: -f1)
if [ -n "$first_checklist" ] && [ -n "$first_item" ] && [ "$first_item" -gt "$first_checklist" ]; then
  echo "FIXTURE FAIL [messy]: needs an sw_item BEFORE the first sw_checklist"; fail=1
fi
fi

# lookalike_aircraft: hand-written, shaped like a real file
if have lookalike_aircraft; then
n_cl=$(grep -cE '^[[:space:]]*@?sw_checklist:' $F/lookalike_aircraft.txt)
n_it=$(grep -cE '^[[:space:]]*@?sw_item:' $F/lookalike_aircraft.txt)
[ "$n_cl" -ge 3 ]  || { echo "FIXTURE FAIL [lookalike_aircraft]: only $n_cl checklists (need >= 3)"; fail=1; }
[ "$n_it" -ge 20 ] || { echo "FIXTURE FAIL [lookalike_aircraft]: only $n_it items (need >= 20)"; fail=1; }
fi

# conditions: every case has its values and expected files, indexes exist, JSON parses
if [ -d $F/conditions ] && ls $F/conditions/*.txt >/dev/null 2>&1; then
  dart run tools/check_condition_fixtures.dart $F/conditions || fail=1
fi

[ $fail -eq 0 ] && echo "fixtures OK"
exit $fail
