#!/bin/bash
# sp2_public_ip.sh - print the router's WAN IPv4 (and IPv6 when present), with a CG-NAT hint.
#
#   SP2_HOST=192.168.1.1 SP2_PASS=... ./sp2_public_ip.sh
#
# Replaces the old Speedport Plus get_public_ip.sh (which read /data/INetIP.json).
# Note: the TR-069 ExternalIPAddress parameters are not populated on this build;
# the WAN address lives on the TR-181 IP.Interface tree.

cd "$(dirname "$0")" && . ./sp2_lib.sh
sp2_login || exit 1

v4=$(sp2_dm_get Device.IP.Interface.1.IPv4Address.1.IPAddress)
v6=$(sp2_dm_get Device.IP.Interface.1.IPv6Address.1.IPAddress)

[ -n "$v4" ] || { echo "no IPv4 WAN address (check the session / DM)"; exit 1; }

case "$v4" in
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) kind="CG-NAT (100.64.0.0/10)" ;;
    10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*|192.168.*)        kind="private / behind NAT" ;;
    *)                                                            kind="public" ;;
esac

echo "$v4"
[ -n "$v6" ] && echo "$v6" >&2
echo "$v4 is $kind" >&2
