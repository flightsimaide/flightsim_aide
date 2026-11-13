#!/usr/bin/env bash
# Prints grep-based counts next to the parser CLI's counts for one file.
# Usage: tools/crosscheck.sh <file>   (run from the project root)
set -euo pipefail

file="${1:?usage: tools/crosscheck.sh <file>}"
CL='^[[:space:]]*@?sw_checklist:'
IT='^[[:space:]]*@?sw_item(_c)?:'
NT='^[[:space:]]*@?sw_(itemvoid|itemvoid_c|iteminfo|remark):'
DEF='^[[:space:]]*@?sw_define_colour'
CONT='^[[:space:]]*@?sw_continue'
SHOW='^[[:space:]]*@?sw_show'

# CR is stripped because Git Bash grep hides it in text mode.
count() { tr -d '\r' < "$file" | grep -cE "$1" || true; }

echo "== $file"
echo "grep: checklists=$(count "$CL") checks=$(count "$IT") notes=$(count "$NT") colours=$(count "$DEF") continues=$(count "$CONT") show_ignored=$(count "$SHOW")"
echo -n "cli:  "
dart run tools/parse_cli.dart "$file" | grep '^TOTAL' | sed 's/^TOTAL //'
