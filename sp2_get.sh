#!/bin/bash
# sp2_get.sh <endpoint.json> - fetch any raw /data/<endpoint> page.
# The full list of the 223 endpoints shipped in the firmware is in endpoints_list.txt.
#
#   ./sp2_get.sh user_lang.json
#   ./sp2_get.sh statussupportwan_lan_leases.json
cd "$(dirname "$0")" && . ./sp2_lib.sh
[ $# -ge 1 ] || { echo "usage: $0 <endpoint.json> [more.json ...]" >&2; exit 2; }
sp2_login || exit 1
for e in "$@"; do
    printf '### %s\n' "$e"
    sp2_page "$e"
    echo
done
