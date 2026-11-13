#!/usr/bin/env bash
# Usage: flutter test --coverage && tools/check_coverage.sh
# Thresholds are line coverage % from coverage/lcov.info (no external lcov needed).
set -u
cd "$(dirname "$0")/.."
LCOV=coverage/lcov.info
[ -f "$LCOV" ] || { echo "No $LCOV - run: flutter test --coverage"; exit 1; }
fail=0
pct() { # path-regex
  awk -v re="$1" '
    /^SF:/ { f=substr($0,4); gsub(/\\/,"/",f); on=(f ~ re) }
    /^DA:/ && on { split(substr($0,4),a,","); t++; if (a[2]>0) h++ }
    END { if (t==0) print "-1"; else printf "%.1f", 100*h/t }' "$LCOV"
}
gate() { # label regex min
  local p; p=$(pct "$2")
  if [ "$p" = "-1" ]; then echo "COVERAGE FAIL: $1 - no lines found for /$2/"; fail=1; return; fi
  if awk -v p="$p" -v m="$3" 'BEGIN{exit !(p>=m)}'; then echo "coverage ok:   $1 ${p}% (min $3%)"
  else echo "COVERAGE FAIL: $1 ${p}% (min $3%)"; fail=1; fi
}
gate "parser"        '^lib/data/parsers/'                         95
gate "domain"        '^lib/domain/'                               95
gate "repositories"  '^lib/data/repositories/.*_impl\.dart$'      90
gate "cubits"        '^lib/ui/.*/cubit/.*_cubit\.dart$'           90
gate "text decoding" '^lib/utils/text_decoding\.dart$'            95
gate "services (flight_sim)" '^lib/data/services/flight_sim/'      85
gate "repositories (flight_sim, settings)" '^lib/data/repositories/(flight_sim|settings)/.*_(impl|remote)\.dart$' 90
gate "condition parser" '^lib/data/parsers/condition_expression_parser\.dart$' 95
gate "auto-check (evaluator, use case)" '^lib/domain/use_cases/autocheck/' 95
gate "dataref watching (hub)" '^lib/data/repositories/flight_sim/dataref_watch_hub\.dart$' 90
gate "settings options" '^lib/domain/models/settings/user_options\.dart$' 95
gate "detail cubit" '^lib/ui/checklist_detail/cubit/checklist_detail_cubit\.dart$' 90
exit $fail
