#!/bin/bash
# sp2_reboot.sh - reboot the router over the API (equivalent of the old reboot.sh).
#
#   ./sp2_reboot.sh            dry run: prints what would be written
#   ./sp2_reboot.sh --yes      actually reboot
#
# The reboot is NOT a plain TR-069 write of DeviceRestart. The web UI writes two parameters,
# in this order (from pageLoadFunctions.js -> StatusAndSupportRestartDevice):
#   Device.DeviceInfo.X_RDKCENTRAL-COM_UI_ACCESS            = "reboot_device"
#   Device.X_CISCO_COM_DeviceControl.RebootDevice           = "Device,delay=3"
# Both answer SCM_SUCCESS and the router drops for ~65s; afterwards
# Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason reads "gui-reboot".
# Writing Device.DeviceInfo.DeviceRestart instead returns 404 "parameter not found".
set -u
cd "$(dirname "$0")" && . ./sp2_lib.sh
sp2_login || exit 1

UI_ACCESS=Device.DeviceInfo.X_RDKCENTRAL-COM_UI_ACCESS
REBOOT=Device.X_CISCO_COM_DeviceControl.RebootDevice

before=$(sp2_dm_get Device.DeviceInfo.UpTime)
echo "uptime now: ${before}s"
echo "would SET $UI_ACCESS=reboot_device"
echo "would SET $REBOOT=Device,delay=3"

if [ "${1:-}" != "--yes" ]; then
    echo "dry run (pass --yes to reboot)"
    exit 0
fi

echo "reply UI_ACCESS:    $(sp2_set "$UI_ACCESS" reboot_device)"
echo "reply RebootDevice: $(sp2_set "$REBOOT" 'Device,delay=3')"
echo "the router drops the LAN for ~1 minute; TR-069 may also re-provision it."
