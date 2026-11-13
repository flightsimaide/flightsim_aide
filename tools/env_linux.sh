#!/usr/bin/env bash
# Sets DEV and PKG for Linux desktop development and checks the toolchain.
# Usage (from the repo root, note "source"):   source tools/env_linux.sh
# Nothing is installed. Only "flutter config --enable-linux-desktop" is run (idempotent).

if ! (return 0 2>/dev/null); then echo "Source this file instead:  source tools/env_linux.sh"; exit 1; fi

export DEV=linux
export PKG=flightsim_aide
if [ -f pubspec.yaml ]; then
  _n=$(grep -E '^name:' pubspec.yaml | head -1 | awk '{print $2}')
  [ -n "$_n" ] && export PKG="$_n"
fi

_fails=0
_ok()   { printf '  ok    %s\n' "$1"; }
_fail() { printf '  FAIL  %s\n' "$1"; _fails=$((_fails+1)); }
_warn() { printf '  warn  %s\n' "$1"; }

echo "FlightSim Aide env: DEV=$DEV PKG=$PKG"
[ "$(uname -s)" = "Linux" ] && _ok "running on Linux" || _fail "this script is for Linux (found $(uname -s)); use env_macos.sh or env_windows.ps1"

if command -v flutter >/dev/null 2>&1; then
  _ok "flutter found: $(command -v flutter)"
  flutter config --enable-linux-desktop >/dev/null 2>&1 && _ok "linux desktop enabled"
  if flutter devices 2>/dev/null | grep -Eq 'linux-(x64|arm64)'; then _ok "flutter lists a linux device"
  else _fail "flutter devices does not list linux (run: flutter doctor -v)"; fi
else
  _fail "flutter not on PATH"
fi
command -v dart  >/dev/null 2>&1 && _ok "dart found"  || _warn "dart not on PATH (it ships inside the flutter SDK)"
for t in clang cmake ninja pkg-config git; do
  command -v "$t" >/dev/null 2>&1 && _ok "$t found" || _fail "$t missing (sudo apt install clang cmake ninja-build pkg-config git)"
done
if command -v pkg-config >/dev/null 2>&1; then
  pkg-config --exists gtk+-3.0 && _ok "GTK 3 dev files found" || _fail "GTK 3 dev files missing (sudo apt install libgtk-3-dev)"
fi
for t in grep awk sed; do command -v "$t" >/dev/null 2>&1 || _fail "$t missing (needed by tools/*.sh)"; done

if [ $_fails -eq 0 ]; then echo "ENV OK"; _rc=0; else echo "ENV INCOMPLETE: $_fails problem(s)"; _rc=1; fi
unset -f _ok _fail _warn; unset _fails _n
return $_rc
