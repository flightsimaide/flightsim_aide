#!/usr/bin/env bash
# Writes datarefs in a running X-Plane 12 through its web API (port 8086), so a
# manual test can set sim state from a script instead of by hand.
#   tools/sim_set.sh sim/cockpit2/switches/beacon_on=1 "sim/cockpit2/electrical/battery_on[0]=1"
# Prints "<name>=<value> http <status>" per argument; 200 means it was written.
# Read a value back:  tools/sim_set.sh --get sim/flightmodel/controls/parkbrake
set -u
base=${SIM_API:-http://127.0.0.1:8086}
id_of() { curl -s "$base/api/v2/datarefs?filter%5Bname%5D=$1" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
if [ "${1:-}" = "--get" ]; then
  shift
  for full in "$@"; do
    name=${full%%\[*}; idx=""
    [[ "$full" == *"["* ]] && { idx=${full#*[}; idx=${idx%]}; }
    id=$(id_of "$name"); url="$base/api/v2/datarefs/$id/value"; [ -n "$idx" ] && url="$url?index=$idx"
    echo "$full -> $(curl -s "$url")"
  done
  exit 0
fi
for kv in "$@"; do
  full=${kv%%=*}; v=${kv##*=}
  name=${full%%\[*}; idx=""
  [[ "$full" == *"["* ]] && { idx=${full#*[}; idx=${idx%]}; }
  id=$(id_of "$name")
  [ -n "$id" ] || { echo "$full: not found"; continue; }
  url="$base/api/v2/datarefs/$id/value"; [ -n "$idx" ] && url="$url?index=$idx"
  curl -s -X PATCH -H 'Content-Type: application/json' -d "{\"data\":$v}" "$url" -o /dev/null -w "$full=$v http %{http_code}\n"
done
