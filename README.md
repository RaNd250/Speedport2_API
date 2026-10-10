# Speedport Plus 2 (Cosmote/OTE) API scripts

Bash + `curl` (+ `python3` for JSON parsing) helpers for the **Cosmote Speedport Plus 2** —
Sercomm **VD4224B** on Broadcom **BCM63178**, RDK-B firmware. Credentials are always taken
from the environment, so nothing secret lives in the repo.

| var | default | meaning |
|---|---|---|
| `SP2_HOST` | `192.168.1.1` | router address |
| `SP2_USER` | `admin` | GUI account |
| `SP2_PASS` | *(required)* | GUI password |
| `SP2_SCHEME` | `https` | `https` (HTTP 301-redirects to HTTPS) |

## Scripts

| script | what it does |
|---|---|
| `sp2_status.sh` | product class, firmware/hardware version, serial, uptime, WAN IP, last reboot reason, clock, Wi-Fi client counts |
| `sp2_public_ip.sh` | WAN IPv4/IPv6 + CG-NAT classification |
| `sp2_devices.sh` | associated Wi-Fi clients; `--watch` prints `joined:` / `left:` against a state file; `--ports` adds LAN port link status |
| `sp2_reboot.sh` | real reboot (dry run unless `--yes`) |
| `sp2_get.sh <x.json>` | raw fetch of any of the 223 shipped endpoints |
| `sp2_lib.sh` | the shared login/JSON-RPC helpers |

```bash
export SP2_PASS='...'
./sp2_status.sh
./sp2_public_ip.sh
./sp2_devices.sh --watch --ports
```

## Reboot

The reboot is **not** `Device.DeviceInfo.DeviceRestart` (that returns `404 parameter not found`).
The web UI writes two parameters, in this order:

```
SET Device.DeviceInfo.X_RDKCENTRAL-COM_UI_ACCESS          = reboot_device
SET Device.X_CISCO_COM_DeviceControl.RebootDevice         = Device,delay=3
```

Both answer `SCM_SUCCESS`; measured, the router was unreachable for **~65 s** and came
back with `Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason = gui-reboot` (factory reset is
`Device.X_CISCO_COM_DeviceControl.FactoryReset = All`).

## The API (reverse engineered from firmware 2.9.003.4)

lighttpd routes **every** `.json` and `.cgi` request to a single binary,
`/usr/www-sc/data/data.cgi` (`setup.cgi` is a symlink to it), so the page endpoints are CGI
output rather than files, and `*.html` is rewritten to `/setup.cgi?next_file=$0` — that is what
injects the CSRF token.

1. `GET /login.html` → the page contains `var csrf_token = 'HK…';`
2. `POST /data/login.json?_=<ts>&csrf_token=<T>` with
   `LoginName=<user>&LoginPWD=<lowercase hex sha256(password)>`
   → body `"1"` = ok, `"2"`/`"6"` = a session is already active (`"6"`: re-post **without**
   `LoginConfirm` to take it over), `"3"` = wrong credentials;
   on success it returns `Set-Cookie: session_id=…;path=/;HttpOnly`.
   The password never travels in clear text (over HTTP the UI instead sends
   `HMAC(sys_encryption_key, HMAC('$1$SERCOMM$', sha256(pw)))`).
3. Every later request must carry **both** `Cookie: session_id=…` and `&csrf_token=<T>`.
   Fetching an HTML page rotates the token, so the helpers stay on JSON only.

**Live values come from JSON-RPC 2.0 over TR-069/DM parameter paths**, not from the page JSON:

```bash
curl -sk -H "Cookie: $SESSION" -H 'Content-Type: application/json' \
  --data '[{"jsonrpc":"2.0","method":"GET","params":"Device.DeviceInfo.SerialNumber","id":1}]' \
  "https://$SP2_HOST/data/data.cgi?_=1&csrf_token=$TOKEN"
```

Parameters the DM does not know answer `"N/A"`.

## Verified-live parameters

```
Device.DeviceInfo.ProductClass                        VD4224BDTP
Device.DeviceInfo.SoftwareVersion                     2.9.003.4
Device.DeviceInfo.HardwareVersion                     02/F0
Device.DeviceInfo.SerialNumber                        <serial number>
Device.DeviceInfo.UpTime                              seconds
Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason   e.g. kernel-crash
Device.Time.CurrentLocalTime                          router clock
Device.IP.Interface.1.IPv4Address.1.IPAddress         WAN IPv4
Device.Ethernet.Interface.1.Status                    Up/Down
Device.WiFi.SSID.1.SSID / .2.SSID                     2.4 / 5 GHz SSIDs
Device.WiFi.SSID.1.BSSID
Device.WiFi.AccessPoint.<1|2>.AssociatedDeviceNumberOfEntries
Device.WiFi.AccessPoint.<1|2>.AssociatedDevice.<n>.MACAddress
Device.DHCPv4.Server.Pool.1.LeaseTime
```

Deliberately **not** used: the `/data/<page>.json` endpoints. On this build most of them return
the UI's bundled **sample payload** (e.g. `192.168.21.11`, `Ali Sony Vaio`,
`sys_firmware_version = 20.02.12`) or `[ ]`, not live values — which is exactly what the old
Speedport Plus scripts get wrong when reused as-is.

## Files

* `sp2_lib.sh` — login + `sp2_page` / `sp2_dm` / `sp2_dm_get` / `sp2_set`
* `endpoints_list.txt` — the 223 `/data/*.json` endpoints found in the firmware image
* `dm_params.txt` — the parameter probe list above, one per line
* `FIRMWARE.md` — **where the firmware came from** plus the full reverse-engineering notes
  (container format, platform, `data.cgi`, why the API looks like this)
* `FIRMWARE_package_tree.txt`, `rootfs_listing.tsv`, `analysis/` — the raw evidence

## Firmware reference

Analysed image: `VD4224BDT_RDKB_OTE_2.9.003.4_REL_RDK.pkgtb`, taken from the Greek ISP firmware
archive [`k-marios/Gr_ISP_Router_Firmware`](https://github.com/k-marios/Gr_ISP_Router_Firmware)
(`Cosmote/Sercomm/Speedport_Plus_2/`, branch `main`) — `FIRMWARE.md` has the URL, the `sha256` and the
proof that this is the build the units run. The original
[nikolas-n/Speedport-Plus-Cosmote-Router-hacks](https://github.com/nikolas-n/Speedport-Plus-Cosmote-Router-hacks)
documents the **first** Speedport Plus and its assumptions do not hold here.

## Caveats

* **One GUI session at a time.** Logging in takes the session over, so a script run will log out
  a browser that is sitting on the web UI (and vice versa).
* Self-signed certificate (`CN=otenet.gr`, `OU=Speedport Plus 2`) — hence `curl -k`. It is the same
  generic Cosmote certificate on every unit, so it cannot identify a router; use the serial number.
* **No shell access.** No `sshd`/`dropbear`/`telnetd` binary is shipped (port 22 refused, only 443
  answers) and there is no UART access, so this API is currently the only remote path.
* Unknown DM parameters answer `"N/A"` instead of erroring, and most page-level `/data/*.json`
  endpoints return bundled sample data — trust only the DM paths in `dm_params.txt`.

