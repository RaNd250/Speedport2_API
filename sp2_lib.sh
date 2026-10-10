#!/bin/bash
# sp2_lib.sh - shared helpers for the Cosmote/OTE Speedport Plus 2
#              (Sercomm VD4224B / Broadcom BCM63178, RDK-B firmware).
#
# Credentials are never hardcoded: export SP2_PASS, optionally SP2_HOST / SP2_USER.
#
#   SP2_HOST   router address          (default: 192.168.1.1)
#   SP2_USER   GUI account             (default: admin)
#   SP2_PASS   GUI password            (required)
#   SP2_SCHEME http | https            (default: https)
#
# API, reverse engineered from firmware 2.9.003.4 (see README.md):
#   * lighttpd routes every .json/.cgi request to ONE binary, /usr/www-sc/data/data.cgi
#     (setup.cgi is a symlink to it), so page endpoints are CGI output, not files.
#   * login:  POST /data/login.json  LoginName=<u>&LoginPWD=<lowercase hex sha256(password)>
#             body "1"=ok, "2"/"6"=session already active ("6" -> re-post without
#             LoginConfirm to take over), "3"=wrong credentials.
#             On success: Set-Cookie: session_id=...;path=/;HttpOnly
#   * a csrf token is injected into /login.html and must be echoed as ?csrf_token=<T> on
#     every later request. It rotates whenever an HTML page is fetched, so these helpers
#     never fetch HTML - they stay on the JSON endpoints.
#   * LIVE values come from JSON-RPC 2.0 over TR-069/DM parameter paths on /data/data.cgi.
#     /data/<page>.json pages are UI templates (mostly sample payloads) - do not script them.

: "${SP2_HOST:=192.168.1.1}"
: "${SP2_USER:=admin}"
: "${SP2_SCHEME:=https}"

sp2_die() { printf 'sp2: %s\n' "$*" >&2; return 1; }

sp2_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    else
        printf '%s' "$1" | openssl dgst -sha256 | sed 's/^.*= //'
    fi
}

# sp2_login - establish the session; sets SP2_CSRF and SP2_COOKIE.
sp2_login() {
    [ -n "$SP2_PASS" ] || { sp2_die "SP2_PASS is not set (export the router password)"; return 1; }
    local base="$SP2_SCHEME://$SP2_HOST" hdrs body code

    SP2_CSRF=$(curl -sk -m 20 "$base/login.html" \
               | sed -n "s/.*csrf_token = '\([0-9A-Za-z]*\)'.*/\1/p" | head -1)
    [ -n "$SP2_CSRF" ] || { sp2_die "could not read csrf_token from $base/login.html"; return 1; }

    hdrs=$(mktemp); body=$(mktemp)
    body_post() {
        curl -sk -m 20 -D "$hdrs" -o "$body" \
            -H "Cookie: login_uid=0.5; username=$SP2_USER" \
            --data-urlencode "LoginName=$SP2_USER" \
            --data-urlencode "LoginPWD=$(sp2_sha256 "$SP2_PASS")" \
            "$base/data/login.json?_=$1&csrf_token=$SP2_CSRF"
    }
    body_post 1
    code=$(tr -d '"\r\n' < "$body")
    if [ "$code" = "6" ]; then body_post 2; code=$(tr -d '"\r\n' < "$body"); fi

    SP2_COOKIE=$(sed -n 's/^[Ss]et-[Cc]ookie: *\(session_id=[^;]*\).*/\1/p' "$hdrs" | head -1)
    rm -f "$hdrs" "$body"

    case "$code" in
        1) : ;;
        3) sp2_die "login rejected (wrong username or password)"; return 1 ;;
        2) sp2_die "another user is logged in - close the web UI and retry"; return 1 ;;
        *) sp2_die "unexpected login reply: '$code'"; return 1 ;;
    esac
    [ -n "$SP2_COOKIE" ] || { sp2_die "login accepted but no session_id cookie returned"; return 1; }
}

# sp2_page <endpoint> - raw GET of a /data/<endpoint> page (endpoints_list.txt has them all).
sp2_page() {
    curl -sk -m 20 -H "Cookie: $SP2_COOKIE" \
        "$SP2_SCHEME://$SP2_HOST/data/$1?_=3&csrf_token=$SP2_CSRF"
}

# sp2_dm <param>... - batched JSON-RPC GET.
# Prints "<param>\t<value>"; unknown parameters come back as "N/A".
sp2_dm() {
    local req="" i=1 p
    for p in "$@"; do
        req="$req{\"jsonrpc\":\"2.0\",\"method\":\"GET\",\"params\":\"$p\",\"id\":$i},"
        i=$((i + 1))
    done
    curl -sk -m 25 -H "Cookie: $SP2_COOKIE" -H 'Content-Type: application/json' \
        --data "[${req%,}]" \
        "$SP2_SCHEME://$SP2_HOST/data/data.cgi?_=4&csrf_token=$SP2_CSRF" \
    | python3 -c '
import sys, json
for o in json.load(sys.stdin):
    for k, v in o.get("result", {}).items():
        print("%s\t%s" % (k, v))
'
}

# sp2_dm_get <param> - a single value (empty string when the DM returns N/A).
sp2_dm_get() {
    sp2_dm "$1" | sed -n "s|^$1\t||p" | awk '$1 != "N/A"'
}

# sp2_set <param> <value> - JSON-RPC SET. Returns the DM reply.
sp2_set() {
    curl -sk -m 25 -H "Cookie: $SP2_COOKIE" -H 'Content-Type: application/json' \
        --data "[{\"jsonrpc\":\"2.0\",\"method\":\"SET\",\"id\":1,\"params\":{\"$1\":\"$2\"}}]" \
        "$SP2_SCHEME://$SP2_HOST/data/data.cgi?_=5&csrf_token=$SP2_CSRF"
}

