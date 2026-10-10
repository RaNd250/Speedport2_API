#!/bin/bash
# sp2_devices.sh - list the Wi-Fi clients currently associated with the router, and (with a
# state file) report who joined / who left since the previous run.
#
#   ./sp2_devices.sh              just print the current Wi-Fi client MACs
#   ./sp2_devices.sh --watch      diff against $SP2_STATE and update it
#   ./sp2_devices.sh --ports      also print Ethernet LAN port link status
#
#   SP2_STATE=/var/lib/sp2/clients.state  (default: /tmp/sp2_clients.<host>.state)
#
# The old Speedport Plus used /data/ManagedDevice.json; on the Plus 2 the live client
# table is the TR-181 tree Device.WiFi.AccessPoint.<n>.AssociatedDevice.<m>.MACAddress.

cd "$(dirname "$0")" && . ./sp2_lib.sh
sp2_login || exit 1

SP2_STATE="${SP2_STATE:-/tmp/sp2_clients.$SP2_HOST.state}"
WATCH=0
PORTS=0
for a in "$@"; do
    [ "$a" = "--watch" ] && WATCH=1
    [ "$a" = "--ports" ] && PORTS=1
done

list=$(
    for ap in 1 2; do
        n=$(sp2_dm_get "Device.WiFi.AccessPoint.$ap.AssociatedDeviceNumberOfEntries")
        [ -n "$n" ] || continue
        for i in $(seq 1 "$n"); do
            mac=$(sp2_dm_get "Device.WiFi.AccessPoint.$ap.AssociatedDevice.$i.MACAddress")
            band=$([ "$ap" = 1 ] && echo 2.4GHz || echo 5GHz)
            [ -n "$mac" ] && printf '%s\t%s\n' "$mac" "$band"
        done
    done | sort -u
)

printf '%s\n' "$list" | grep -v '^$' || true

# The TR-098/TR-181 Hosts table is not populated on this build (HostNumberOfEntries = N/A),
# so wired clients cannot be listed by MAC. Ethernet per-port link status is the next best
# thing: it shows how many wired devices are attached.
if [ "$PORTS" = 1 ]; then
    for p in 1 2 3 4; do
        st=$(sp2_dm_get "Device.Ethernet.Interface.$p.Status")
        [ -n "$st" ] && printf 'lan-port-%s\t%s\n' "$p" "$st"
    done
fi

if [ "$WATCH" = 1 ]; then
    prev=$( [ -f "$SP2_STATE" ] && cat "$SP2_STATE" )
    printf '%s\n' "$list" | cut -f1 | sort > "$SP2_STATE.new"
    if [ -n "$prev" ]; then
        printf '%s\n' "$prev" | cut -f1 | sort > "$SP2_STATE.old"
        comm -13 "$SP2_STATE.old" "$SP2_STATE.new" | sed 's/^/joined: /' >&2
        comm -23 "$SP2_STATE.old" "$SP2_STATE.new" | sed 's/^/left:    /' >&2
    fi
    mv "$SP2_STATE.new" "$SP2_STATE"; rm -f "$SP2_STATE.old"
fi
