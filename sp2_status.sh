#!/bin/bash
# sp2_status.sh - one-shot status summary of the Speedport Plus 2.
cd "$(dirname "$0")" && . ./sp2_lib.sh
sp2_login || exit 1

P="Device.DeviceInfo.ProductClass
Device.DeviceInfo.SoftwareVersion
Device.DeviceInfo.HardwareVersion
Device.DeviceInfo.SerialNumber
Device.DeviceInfo.UpTime
Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason
Device.Time.CurrentLocalTime
Device.IP.Interface.1.IPv4Address.1.IPAddress
Device.Ethernet.Interface.1.Status
Device.WiFi.SSID.1.SSID
Device.WiFi.SSID.2.SSID
Device.WiFi.AccessPoint.1.AssociatedDeviceNumberOfEntries
Device.WiFi.AccessPoint.2.AssociatedDeviceNumberOfEntries
Device.DHCPv4.Server.Pool.1.LeaseTime"

sp2_dm $P | while IFS=$'\t' read -r k v; do
    case "$k" in
        Device.DeviceInfo.UpTime)
            d=$((v / 86400)); h=$((v % 86400 / 3600)); m=$((v % 3600 / 60))
            printf '%-52s %s (%dd %02dh %02dm)\n' "$k" "$v" "$d" "$h" "$m" ;;
        *)  printf '%-52s %s\n' "$k" "$v" ;;
    esac
done
