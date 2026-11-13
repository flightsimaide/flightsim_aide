#!/usr/bin/env bash
# Builds the real Xchecklist "checker" (the plugin's own parser as a command-line tool)
# from external/xchecklist (see README.md). Run inside WSL/Linux; needs g++, flex, bison.
# Mirrors checker/CMakeLists.txt without cmake. Output: external/checker_build/checker
# (external/ is git-ignored, so the binary is never committed).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SRC="$ROOT/external/xchecklist"
OUT="$ROOT/external/checker_build"
[ -d "$SRC/checker" ] || { echo "missing $SRC/checker: put the Xchecklist source in external/xchecklist (see README.md)"; exit 1; }
rm -rf "$OUT" && mkdir -p "$OUT"
cd "$SRC/checker"
bison -v -p chkl -r state --defines="$OUT/chkl_yacc.h" -o "$OUT/chkl_yacc.cpp" ../src/chkl.y
flex -P chkl -o "$OUT/chkl_lex.cpp" ../src/chkl.l
g++ -std=c++17 -fexceptions -O1 -w \
  -DXPLM200=1 -DXPLM210=1 -DXPLM300=1 -DXPLM301=1 -DCHECKER -DAPL=0 -DIBM=0 -DLIN=1 \
  -I../src/SDK/CHeaders/XPLM -I../src -I"$OUT" \
  main.cpp ../src/interface.cpp ../src/parser.cpp ../src/utils.cpp \
  "$OUT/chkl_yacc.cpp" "$OUT/chkl_lex.cpp" -o "$OUT/checker"
echo "built $OUT/checker"
