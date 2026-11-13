#!/usr/bin/env bash
# Enforces the import rules in ARCHITECTURE.md section 3.
# Allowed extra in domain: package:equatable (pure Dart). See Documentation/Architecture/ARCHITECTURE.md.
set -u
cd "$(dirname "$0")/.."
PKG=$(grep -E '^name:' pubspec.yaml | awk '{print $2}')
fail=0

check() { # dir regex message
  local dir=$1 re=$2 msg=$3 hits
  [ -d "$dir" ] || return 0
  hits=$(grep -rnE --include='*.dart' "^[[:space:]]*(import|export)[[:space:]]+'($re)" "$dir" || true)
  if [ -n "$hits" ]; then echo "LAYER VIOLATION: $msg"; echo "$hits"; echo; fail=1; fi
}

UPLAYERS="(data|ui|config|routing)"
check lib/domain \
  "dart:(io|ui|html)|package:http/|package:shared_preferences/|package:path_provider/|package:flutter/|package:flutter_bloc/|package:bloc/|package:go_router/|package:file_picker/|package:$PKG/$UPLAYERS/|(\.\./)+$UPLAYERS/" \
  "domain must be pure Dart (no Flutter/Bloc/io, no data/ui/config/routing)"

# domain may import only Dart core, equatable and itself (task 3):
# an allow-list on top of the deny-list above, so a new package cannot slip in.
if [ -d lib/domain ]; then
  hits=$(grep -rnE --include='*.dart' "^[[:space:]]*(import|export)[[:space:]]+'" lib/domain \
    | grep -vE "'(dart:(core|async|math|convert|collection|typed_data)|package:equatable/[^']*|package:$PKG/domain/[^']*|(\.\./|\./)[^']*|[a-z0-9_]+\.dart)'" || true)
  if [ -n "$hits" ]; then
    echo "LAYER VIOLATION: domain may import only Dart core, equatable and domain files"
    echo "$hits"; echo; fail=1
  fi
fi

check lib/data \
  "package:flutter/(widgets|material|cupertino|rendering|painting)\.dart|package:flutter_bloc/|package:bloc/|package:go_router/|package:$PKG/(ui|config|routing)/|(\.\./)+(ui|config|routing)/" \
  "data must not import ui, config, routing, Flutter widgets or Bloc"

check lib/ui \
  "dart:io|package:http/|package:shared_preferences/|package:path_provider/|package:file_picker/|package:$PKG/data/(services|parsers)/|package:$PKG/data/repositories/.*_(impl|local|remote)\.dart|package:$PKG/config/|(\.\./)+data/(services|parsers)/|(\.\./)+data/repositories/.*_(impl|local|remote)\.dart|(\.\./)+config/" \
  "ui may only use abstract repositories, domain, utils, routing"

check lib/routing \
  "dart:io|package:http/|package:shared_preferences/|package:path_provider/|package:file_picker/|package:$PKG/data/(services|parsers)/|package:$PKG/data/repositories/.*_(impl|local|remote)\.dart|package:$PKG/config/" \
  "routing may only use abstract repositories, ui, domain, utils"

check lib/utils \
  "dart:io|package:http/|package:shared_preferences/|package:path_provider/|package:flutter/|package:flutter_bloc/|package:$PKG/(data|ui|config|routing|domain)/" \
  "utils must be self-contained"

# IO packages (dart:io, http, shared_preferences, path_provider) belong in data/services only.
check lib/data/repositories \
  "dart:io|package:http/|package:shared_preferences/|package:path_provider/" \
  "repositories must not do IO themselves (use a service in data/services)"

check lib/data/parsers \
  "dart:io|package:http/|package:shared_preferences/|package:path_provider/|package:flutter/|package:flutter_bloc/" \
  "parsers are pure functions (no IO packages, no Flutter)"

[ $fail -eq 0 ] && echo "layers OK"
exit $fail
