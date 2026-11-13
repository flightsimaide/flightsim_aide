#!/usr/bin/env bash
# Every acceptance criterion in Documentation/Plan/PLAN.md section 16 is a line
#   N. **AC-N [tag]** ...
#   [A] / [A + SIM]   needs an automated test tagged  // AC-N  (under test/)
#   [SIM] / [A + SIM] needs a "## AC-N" entry in Documentation/Testing/MANUAL_TEST.md
#   [retired]         is skipped
set -u
cd "$(dirname "$0")/.."
fail=0
PLAN=Documentation/Plan/PLAN.md
MANUAL=Documentation/Testing/MANUAL_TEST.md
[ -f "$PLAN" ] || { echo "missing $PLAN"; exit 1; }
count=0
while IFS= read -r line; do
  n=$(printf '%s' "$line" | sed -E 's/^[0-9]+\. \*\*AC-([0-9]+) \[.*/\1/')
  tag=$(printf '%s' "$line" | sed -E 's/^[0-9]+\. \*\*AC-[0-9]+ \[([^]]*)\].*/\1/')
  count=$((count + 1))
  case "$tag" in
    A*)
      if grep -rqE "//[[:space:]]*AC-$n\b" test 2>/dev/null; then
        echo "AC-$n automated test tagged"
      else
        echo "AC-$n has NO automated test tagged '// AC-$n'"; fail=1
      fi ;;
  esac
  case "$tag" in
    *SIM*)
      if grep -qE "^## AC-$n\b" "$MANUAL" 2>/dev/null; then
        echo "AC-$n has an entry in $MANUAL"
      else
        echo "AC-$n has NO entry in $MANUAL"; fail=1
      fi ;;
  esac
done < <(grep -E '^[0-9]+\. \*\*AC-[0-9]+ \[' "$PLAN")
[ "$count" -gt 0 ] || { echo "no criteria found in $PLAN"; exit 1; }
exit $fail
