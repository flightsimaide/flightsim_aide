#!/usr/bin/env bash
# Task 4.12 check, shared by tools/platform/mac/task_4.12_plugin_build.sh and
# tools/platform/linux/task_4.12_plugin_build.sh. Run one of those, not this.
#
#   plugin_build_check.sh <Darwin|Linux> [--sdk <X-Plane SDK folder>]
#
# 1. configure, build and ctest the core (no X-Plane SDK needed);
# 2. with --sdk (or $XPLANE_SDK): build the X-Plane shell target and check the file;
# 3. write a short result to plugin/build/4.12-<os>/result.txt (build/ is not committed).
# Builds in plugin/build/4.12-<os>/, so it never disturbs another build folder.
set -u

want="${1:-}"; shift || true
case "$want" in Darwin|Linux) ;; *) echo "usage: $0 <Darwin|Linux> [--sdk <folder>]" >&2; exit 2 ;; esac
sdk="${XPLANE_SDK:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --sdk) sdk="${2:-}"; shift ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
os="$(uname -s)"
tag="$(printf '%s' "$want" | tr 'A-Z' 'a-z')"
out="$REPO_ROOT/plugin/build/4.12-$tag"
result="$out/result.txt"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$os" = "$want" ] || die "this check is for $want (found $os)"
for tool in cmake git; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is not installed or not on PATH"
done
if [ "$want" = Darwin ]; then
  command -v clang++ >/dev/null 2>&1 || die "no C++ compiler: run 'xcode-select --install'"
else
  command -v g++ >/dev/null 2>&1 || die "g++ is not installed (sudo apt install build-essential cmake)"
fi
gen=()
command -v ninja >/dev/null 2>&1 && gen=(-G Ninja)

mkdir -p "$out"
: > "$result"
log() { printf '%s\n' "$*" | tee -a "$result"; }
step() {   # step <label> <command...>: runs it, records PASS or FAIL
  local label="$1"; shift
  printf '\n== %s ==\n+ %s\n' "$label" "$*"
  if "$@"; then log "PASS  $label"; return 0; fi
  log "FAIL  $label"; return 1
}

log "Task 4.12 on $os $(uname -m), $(date '+%Y-%m-%d %H:%M')"
log "repo $(git -C "$REPO_ROOT" rev-parse --short HEAD), cmake $(cmake --version | head -1 | awk '{print $3}')"

fail=0
step "configure core and tests" cmake -S "$REPO_ROOT/plugin" -B "$out/tests" "${gen[@]}" \
  -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTS=ON || fail=1
if [ $fail = 0 ]; then
  step "build core and tests" cmake --build "$out/tests" || fail=1
fi
if [ $fail = 0 ]; then
  step "ctest" ctest --test-dir "$out/tests" --output-on-failure || fail=1
fi

if [ -n "$sdk" ]; then
  [ -f "$sdk/CHeaders/XPLM/XPLMDefs.h" ] || die "--sdk must hold CHeaders/XPLM/XPLMDefs.h (unpack the X-Plane SDK and pass its SDK folder)"
  if [ $fail = 0 ]; then
    step "configure X-Plane shell" cmake -S "$REPO_ROOT/plugin" -B "$out/shell" "${gen[@]}" \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DXPLANE_SDK="$sdk" || fail=1
  fi
  if [ $fail = 0 ]; then
    step "build X-Plane shell" cmake --build "$out/shell" --target flightsim_aide || fail=1
  fi
  if [ $fail = 0 ]; then
    xpl="$(find "$out/shell" -name flightsim_aide.xpl -type f | head -1)"
    if [ -n "$xpl" ]; then
      log "PASS  produced $xpl"
      if [ "$want" = Darwin ]; then
        archs="$(lipo -archs "$xpl" 2>&1)"
        log "      architectures: $archs"
        case "$archs" in *arm64*x86_64*|*x86_64*arm64*) ;; *) log "WARN  not universal (x86_64 and arm64 expected)" ;; esac
      else
        file "$xpl" | tee -a "$result"
      fi
    else
      log "FAIL  flightsim_aide.xpl was not produced"; fail=1
    fi
  fi
else
  log "SKIP  X-Plane shell (no --sdk or XPLANE_SDK)"
fi

echo
if [ $fail = 0 ]; then
  log "RESULT: PASS. Paste this into the 4.12 line of Documentation/Testing/MANUAL_TEST.md (plugin task 4.12) once the $os run is recorded."
else
  log "RESULT: FAIL. Send $result (and the output above) back to the PC session."
fi
echo "Saved: $result"
exit $fail
