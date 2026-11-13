#!/usr/bin/env bash
# Guards the checklist source seam (ARCHITECTURE.md section 7): temporary code must be
# removable by deleting the temporary/ folders, one wiring file and one dependency.
set -u
cd "$(dirname "$0")/.."
fail=0
ALLOWED_WIRING="lib/config/dependencies_production.dart"
ALLOWED_HOME="lib/ui/home/widgets/home_screen.dart"

# 0. The temporary code is removed: no temporary/ folder may come back.
while IFS= read -r dir; do
  echo "ISOLATION VIOLATION (temporary folder): $dir"; fail=1
done < <(find lib test testing -type d -name temporary 2>/dev/null || true)

# 1. Who imports anything under temporary/ ?
while IFS= read -r line; do
  f=${line%%:*}
  case "$f" in
    */temporary/*) continue ;;                       # temporary code may use itself
    "$ALLOWED_WIRING"|"$ALLOWED_HOME"|test/config/dependencies_production_test.dart) continue ;;   # the permitted touch points and the wiring test
  esac
  echo "ISOLATION VIOLATION: $line"; fail=1
done < <(grep -rnE --include='*.dart' "^[[:space:]]*(import|export)[[:space:]]+'[^']*temporary/" lib test testing 2>/dev/null || true)

# 2. file_picker only inside lib/data/services/temporary/
while IFS= read -r line; do
  f=${line%%:*}
  case "$f" in lib/data/services/temporary/*|test/data/services/temporary/*) continue ;; esac
  echo "ISOLATION VIOLATION (file_picker): $line"; fail=1
done < <(grep -rnE --include='*.dart' "package:file_picker/" lib test testing 2>/dev/null || true)

# 3. dart:io only inside lib/data/services/ (network, stream and local storage services)
while IFS= read -r line; do
  f=${line%%:*}
  case "$f" in lib/data/services/*) continue ;; esac
  echo "ISOLATION VIOLATION (dart:io): $line"; fail=1
done < <(grep -rnE --include='*.dart' "^[[:space:]]*import[[:space:]]+'dart:io'" lib 2>/dev/null || true)

# 4. Bundled sample asset only referenced from temporary code, wiring, or pubspec
while IFS= read -r line; do
  f=${line%%:*}
  case "$f" in */temporary/*|"$ALLOWED_WIRING"|test/*) continue ;; esac
  echo "ISOLATION VIOLATION (sample asset): $line"; fail=1
done < <(grep -rn --include='*.dart' "sample_checklist.txt" lib 2>/dev/null || true)

[ $fail -eq 0 ] && echo "temporary isolation OK"
exit $fail
