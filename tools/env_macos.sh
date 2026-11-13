#!/usr/bin/env bash
# Sets DEV and PKG for macOS desktop development and checks the toolchain.
# Usage (from the repo root, note "source"):   source tools/env_macos.sh
# Nothing is installed. Only "flutter config --enable-macos-desktop" is run (idempotent).

if ! (return 0 2>/dev/null); then echo "Source this file instead:  source tools/env_macos.sh"; exit 1; fi

export DEV=macos
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
[ "$(uname -s)" = "Darwin" ] && _ok "running on macOS" || _fail "this script is for macOS (found $(uname -s)); use env_linux.sh or env_windows.ps1"

if command -v flutter >/dev/null 2>&1; then
  _ok "flutter found: $(command -v flutter)"
  flutter config --enable-macos-desktop >/dev/null 2>&1 && _ok "macos desktop enabled"
  if flutter devices 2>/dev/null | grep -Eq 'darwin-(x64|arm64)'; then _ok "flutter lists a macos device"
  else _fail "flutter devices does not list macos (run: flutter doctor -v)"; fi
else
  _fail "flutter not on PATH"
fi
command -v dart >/dev/null 2>&1 && _ok "dart found" || _warn "dart not on PATH (it ships inside the flutter SDK)"
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version >/dev/null 2>&1 && _ok "Xcode found" || _fail "Xcode not configured (sudo xcode-select --switch /Applications/Xcode.app && sudo xcodebuild -runFirstLaunch)"
else
  _fail "xcodebuild missing (install Xcode)"
fi
command -v pod >/dev/null 2>&1 && _ok "CocoaPods found" || _fail "CocoaPods missing (brew install cocoapods)"
command -v git >/dev/null 2>&1 && _ok "git found" || _fail "git missing"
for t in grep awk sed; do command -v "$t" >/dev/null 2>&1 || _fail "$t missing (needed by tools/*.sh)"; done
# macOS ships BSD grep/sed. The tool scripts use only POSIX-compatible options, but note it:
_warn "BSD grep/sed in use; if a tool script behaves oddly try: brew install grep gnu-sed"

if [ $_fails -eq 0 ]; then echo "ENV OK"; _rc=0; else echo "ENV INCOMPLETE: $_fails problem(s)"; _rc=1; fi
unset -f _ok _fail _warn; unset _fails _n
return $_rc
