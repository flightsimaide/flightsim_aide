#!/usr/bin/env bash
# Single quality gate. Run from anywhere: tools/verify.sh [--no-test]
# Exit code 0 = everything green. Run it before every commit.
set -euo pipefail
cd "$(dirname "$0")/.."
step() { printf '\n==> %s\n' "$*"; }

step "folder structure";        tools/check_structure.sh
step "layer import rules";      tools/check_layers.sh
step "temporary-code isolation"; tools/check_temporary_isolation.sh
if [ -x tools/check_fixtures.sh ]; then step "fixtures"; tools/check_fixtures.sh; fi
step "acceptance tags";         tools/check_acceptance_tags.sh > /dev/null
step "dart format";             dart format --output=none --set-exit-if-changed lib test testing tools
step "flutter analyze";         flutter analyze --fatal-infos
if [ "${1:-}" != "--no-test" ]; then
  step "flutter test";          flutter test
fi
printf '\nVERIFY OK\n'
