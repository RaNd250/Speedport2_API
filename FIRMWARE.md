# Firmware reference & reverse-engineering notes

Everything here was derived by taking the ISP firmware image apart — it is what makes the API
behaviour in `README.md` explicable rather than guesswork.

## Where the firmware came from

We did **not** pull it from the router; we used a community archive of Greek ISP firmware:

> **Ref:** [`k-marios/Gr_ISP_Router_Firmware`](https://github.com/k-marios/Gr_ISP_Router_Firmware)
> — “Various router firmware files from greek ISPs”
> path `Cosmote/Sercomm/Speedport_Plus_2/`, branch `main`

The exact file we analysed (the version the routers run):

```
https://github.com/k-marios/Gr_ISP_Router_Firmware/raw/main/Cosmote/Sercomm/Speedport_Plus_2/VD4224BDT_RDKB_OTE_2.9.003.4_REL_RDK.pkgtb
size   69,875,232 bytes
sha256 7dadb80bd285ada84de95bfefbff43826ffd893b07875dab8f209cb751821cab
```

Retrieved 2026-10-09 (URL re-verified live 2026-10-10). Note this is a **community archive**, not a
vendor portal — Cosmote pushes these images to the units over TR-069/OTA, so treat the archive as a
convenience copy and re-check `sha256` if you rely on it.

⚠️ The same archive has **two different Speedport Plus 2 images**, for two different ODMs, and they
do **not** cross-flash:

| ODM | archive path | image |
|---|---|---|
| **Sercomm** ← this repo | `Cosmote/Sercomm/Speedport_Plus_2/` | `VD4224BDT_RDKB_OTE_*.pkgtb` (2.8.060.0 … 2.9.003.4) |
| Arcadyan | `Cosmote/Arcadyan/Speedport_Plus_2/` | `VRV9518BAAX24-B-2G_v2.000.1x*.bin` |

The second reference repo we consulted is
[nikolas-n/Speedport-Plus-Cosmote-Router-hacks](https://github.com/nikolas-n/Speedport-Plus-Cosmote-Router-hacks),
which documents the **original** Speedport Plus (Dyalog firmware `09022001.xx_OTE5`) — a different API
generation, which is why its scripts do not work on the Plus 2.

## Proof that this image is what the routers actually run

* `version.txt` inside the squashfs: `VERSION=2.9.003.4`, `MACHINE_NAME=VD4224B`,
  `imagename:VD4224BDT_RDKB_OTE_2.9.003.4` — identical to the `?ver=2.9.003.4` the live UI requests.
* `usr/www-sc/index.html` in the image: **55 bytes, mtime 2025-09-23 21:50:20** (local, = 18:50:20 GMT)
  — byte-identical size and identical `Last-Modified: Tue, 23 Sep 2025 18:50:20 GMT` to the live router.
* The DM reports `Device.DeviceInfo.ProductClass = VD4224BDTP`, which is one of the board nodes in
  the image's own package tree (`conf_lx_VD4224BDTP`).

## Container format

`.pkgtb` is a **Broadcom BCA package-tree binary**: an FDT (DTB) manifest followed by the images, not a
plain filesystem dump. `analysis/fdt_dump.py` parses it; the full decoded tree is in
`FIRMWARE_package_tree.txt`. Layout:

| component | offset | size |
|---|---|---|
| DTB manifest | 0 | 988 |
| `atf` (BL31) | 988 | 127,196 |
| `uboot` | 128,184 | 1,480,164 |
| `kernel` (Linux 4.19, **lzo**) | 1,608,348 | 3,481,832 |
| ~20 board FDTs (`963178REF1/REF2/SV`, `VD4224BDTI`, `VD4224BDTP`, …) | 5,090,180 | 3,197,596 |
| **`images/rootfs` squashfs** | **8,287,776** | **61,587,456** |

The rootfs runs to end of file: `8,287,776 + 61,587,456 = 69,875,232`.
Extract with `dd if=<pkgtb> of=rootfs.sqsh bs=4M iflag=skip_bytes,count_bytes skip=8287776 count=61587456`.

**Rootfs:** SquashFS **4.0, XZ**, cluster 131072, created 2025-09-23 21:58:54, 5,828 entries
(475 dirs / 5,353 files, 160,866,591 bytes uncompressed). Full index: `rootfs_listing.tsv`.

## Platform

Sercomm **VD4224B** on Broadcom **BCM63178** (32-bit ARM, `armv7`-family), **RDK-B** userspace on
Linux 4.19 with **systemd**. Image id strings in the manifest:
`5042p1GWV_SERCOMM_VD4224B2661858`, BCA `5.04L.02p1`, `BDE_V2.0.1-002R-Broadband.021`.

Enabled services are the full RDK-B stack: `CcspPandMSsp`, `PsmSsp`, `RdkWanManager`,
`RdkXdslManager`, `RdkGponManager`, `CcspTr069PaSsp`, `CcspWebUI`, `Voice`, `secure-mcast` (×3), etc.
This is why the DM answers TR-181 paths with vendor subtrees (`X_RDKCENTRAL-COM_*`, `X_CISCO_COM_*`).

## Why the web API looks the way it does

`/etc/lighttpd.conf` in the image:

```
server.document-root        = "/usr/www-sc/"
server.network-backend      = "writev"
cgi.assign    = ( ".cgi"  => "/usr/www-sc/data/data.cgi",
                  ".json" => "/usr/www-sc/data/data.cgi", ... )
url.rewrite            = ( "^/.*\.html" => "/setup.cgi?next_file=$0" )
url.rewrite-if-not-file = ( "^/(.*)$"   => "/index.html" )
```

* Every `.json` **and** `.cgi` request is dispatched to **one** binary,
  `/usr/www-sc/data/data.cgi` (107,744-byte ARM ELF) — `setup.cgi` is a **symlink** to it
  (`lrwxrwxrwx`, 25 bytes). So page endpoints are CGI output, not files on disk.
* The `*.html` rewrite is what injects `var csrf_token = '…'` into each page — and because the token
  rotates on every HTML fetch, a script that mixes HTML and JSON requests keeps getting
  `302 → /login.html`.
* The catch-all rewrite explains the 55-byte `/index.html` returned for unknown paths.
* `/usr/www-sc/data/` contains exactly **223** `*.json` names (323,275 bytes total) — the authoritative
  endpoint list, mirrored in `endpoints_list.txt`. Most of them are UI templates carrying **sample**
  payloads, which is the trap when porting old Speedport scripts.

## data.cgi internals

Dynamically linked, stripped ARM ELF. NEEDED: `libjson-c`, **`libccsp_common`** (RDK/CCSP DM access),
**`libsyscfg`**, `libfactorydata`, `libxml2`, `libcrypto 1.1`, `libstdc++`, `libc`.

* Session state lives in **files**: `/var/websession/<user>/{sessionid,csrf_token,last_csrf_token}` —
  the source of `Set-Cookie: session_id=…;path=/;HttpOnly` and of the per-page token rotation.
* `check_username_password`, `Device.Users.User.3.Password`, `user_password_3` / `user_password_3_def`
  and the `$1$SERCOMM$` salt ⇒ there is a **hidden third account** in the DM besides `admin`.
* Config export/import: `openssl enc -{e,d} -aes256 -kfile /tmp/config_password`, i.e. the saved
  `.cfg` is AES-256 keyed by a **key file**, not by the GUI password.
* Shells out via `popen`/`system` with `%s` templates (e.g. `psmcli set dmsb.xdslmanager.atm.1.pvc '%s'`),
  so an authenticated command-injection path exists; we did not chase it.

## Shell access today: none

The rootfs ships **no `sshd`, no `dropbear`, no `telnetd`, no `vsftpd` binary** and enables no such unit
(only `getty.target`), even though `usr/bin/ssh` (client) and a `/etc/dropbear` bind-mount unit exist —
that combination is misleading if you only look at `/lib/systemd/system`. Port 22 is *connection refused*;
only **TCP 443** answers on the LAN (80 301-redirects).

The image is opkg-based (`usr/lib/opkg`, `var/lib/opkg`) with `/sbin/mount-copybind`, so
`opkg install dropbear` would be viable — but it needs a shell to run, and the console is serial.
**There is no UART access**, so for the moment the JSON-RPC API in this repo is the only remote
access path, and installing a daemon is a chicken-and-egg problem.

Inside a serial shell the useful tools are present: `dmcli`, `psmcli`, `sysevent`, `acs_cli2`,
`sc_logger`.

## Files in this repo that document the above

| file | what it is |
|---|---|
| `FIRMWARE_package_tree.txt` | decoded `.pkgtb` FDT manifest (all images, offsets, image id strings) |
| `rootfs_listing.tsv` | all 5,828 rootfs entries: path, type, size, mode, mtime |
| `analysis/fdt_dump.py` | the DTB parser used to produce the tree (no binwalk needed) |
| `analysis/sp2_scan.py` | harness that probed all 223 endpoints against a live router |
| `endpoints_list.txt` | the 223 endpoint names |
| `dm_params.txt` | the DM parameter paths that actually return live values |
