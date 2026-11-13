#!/usr/bin/env bash
# Runs the real checker over every checklist file in external/aircraft plus the reference files
# in external/xchecklist, and saves the output to external/checker_results/ (git-ignored). Run build_checker.sh first.
#   results/<file>.out   full checker output (paths made relative)
#   results/summary.txt  one line per file: checklists, errors, warnings
#   results/errors.txt   every ERROR/WARNING line, prefixed by file name
# Compare errors.txt with our parser's warnings.
# Pass a second argument to forward the checker's debug bit field, e.g. 4 = print checklists.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RAW="$ROOT/external"
BIN="$RAW/checker_build/checker"
RES="$RAW/checker_results"
[ -x "$BIN" ] || { echo "run build_checker.sh first"; exit 1; }
rm -rf "$RES" && mkdir -p "$RES"
: > "$RES/summary.txt"; : > "$RES/errors.txt"
for f in "$RAW"/aircraft/*.txt "$RAW/xchecklist/Thranda_PC12_clist.txt" "$RAW/xchecklist/checker/clist.txt"; do
  [ -f "$f" ] || continue
  rel="${f#$RAW/}"; name="$(basename "$f")"
  [ "${rel#xchecklist/checker/}" != "$rel" ] && name="repo_checker_$name"
  timeout 60 "$BIN" "$f" ${1:+$1} 2>&1 | sed "s#$RAW/##g" > "$RES/$name.out"
  n=$(grep -c 'New checklist' "$RES/$name.out")
  tail=$(grep -E '^Encountered' "$RES/$name.out" || echo "Encountered ? errors and ? warnings.")
  printf '%-40s %3s checklists  %s\n' "$name" "$n" "$tail" >> "$RES/summary.txt"
  grep -E '\* (ERROR|WARNING) \*' "$RES/$name.out" | sed "s#^#$name: #" >> "$RES/errors.txt"
done
cat "$RES/summary.txt"
