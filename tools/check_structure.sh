#!/usr/bin/env bash
# Verifies the folder layout from ARCHITECTURE.md section 5 (driven by tools/expected_dirs.txt).
set -u
cd "$(dirname "$0")/.."
fail=0
while IFS='|' read -r path kind; do
  case "$path" in ''|\#*) continue ;; esac
  if [ ! -d "$path" ]; then echo "MISSING DIR: $path"; fail=1; continue; fi
  if [ "$kind" = "PLACEHOLDER" ]; then
    if ! grep -qs '^Status:' "$path/README.md"; then echo "PLACEHOLDER LACKS 'Status:' README: $path"; fail=1; fi
    if find "$path" -name '*.dart' | grep -q .; then echo "PLACEHOLDER HAS CODE: $path"; fail=1; fi
  fi
done < tools/expected_dirs.txt
[ $fail -eq 0 ] && echo "structure OK"
exit $fail
