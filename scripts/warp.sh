#!/data/data/com.termux/files/usr/bin/bash
# Cloudflare WARP for the whole phone (root). Usage: warp.sh up|down|status
# Engine: sing-box (TUN "warp0" + WireGuard with WARP's reserved bytes; kernel
# WireGuard can't send them and Cloudflare then stalls every TLS handshake 2-5 s).
# Every app's own traffic (iif lo) goes through warp0, EXCEPT Termux's uid,
# which keeps the direct route (so a shell / ssh session never loses the network).
# The official 1.1.1.1 app's VPN rules (netd, priority 12000-13000) still win.
# Some ISPs throttle the 162.159.192/193.x endpoints, so 188.114.96-99.x are tried first.
# A watchdog probes 1.0.0.1 through the tunnel every 10 s, rotates endpoints,
# and fails OPEN (removes the steering rules -> direct internet) when WARP is down.
set -u
export PATH=/system/bin:/data/data/com.termux/files/usr/bin:$PATH
D="$(cd "$(dirname "$0")" && pwd)"
SELF_UID="${WARP_EXCLUDE_UID:-$(stat -c %u /data/data/com.termux 2>/dev/null)}"   # Termux
PRIO=13500
PROBE=1.0.0.1
LOG="$D/warp.log"
PIDF="$D/watchdog.pid"
SBPID="$D/singbox.pid"
ENDPOINTS="188.114.97.3:2408 188.114.98.66:4500 188.114.96.5:2408 188.114.99.10:500 162.159.192.5:2408"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

steer_off() { for fam in -4 -6; do while ip $fam rule del priority $PRIO 2>/dev/null; do :; done; done; }
steer_on() {
    steer_off
    for fam in -4 -6; do
        ip $fam rule add iif lo uidrange 0-$((SELF_UID-1)) lookup 5150 priority $PRIO
        ip $fam rule add iif lo uidrange $((SELF_UID+1))-99999 lookup 5150 priority $PRIO
    done
}
steered() { ip -4 rule show | grep -q "^$PRIO:"; }
alive() {
    for i in 1 2; do
        curl -s -m 5 https://$PROBE/cdn-cgi/trace 2>/dev/null | grep -q '^warp=on' && return 0
    done
    return 1
}

sb_stop() {
    [ -f "$SBPID" ] && kill "$(cat "$SBPID")" 2>/dev/null; rm -f "$SBPID"
    for i in 1 2 3 4 5; do ip link show warp0 >/dev/null 2>&1 || break; sleep 1; done
}
sb_start() {   # $1 = ip:port
    sb_stop
    "$D/mkconf.sh" "${1%:*}" "${1##*:}" || return 1
    nohup sing-box run -c "$D/sb-tun.json" >> "$D/singbox.log" 2>&1 &
    echo $! > "$SBPID"
    for i in $(seq 1 10); do ip link show warp0 >/dev/null 2>&1 && break; sleep 0.5; done
    ip link show warp0 >/dev/null 2>&1 || return 1
    ip -4 route replace default dev warp0 table 5150
    ip -6 route replace default dev warp0 table 5150
    for p in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 169.254.0.0/16 224.0.0.0/4 255.255.255.255/32; do
        ip -4 route replace throw $p table 5150
    done
    for p in fe80::/10 fc00::/7 ff00::/8; do ip -6 route replace throw $p table 5150; done
}

# start sing-box on the first endpoint that passes the probe
pick_endpoint() {
    for ep in $ENDPOINTS; do
        sb_start "$ep" || { log "sing-box failed to start ($ep)"; continue; }
        ok=0; for i in 1 2 3; do alive && ok=$((ok+1)); done
        if [ $ok -ge 2 ]; then log "endpoint $ep ok ($ok/3)"; echo "$ep"; return 0; fi
        log "endpoint $ep bad ($ok/3)"
    done
    return 1
}

watchdog() {
    fails=0
    while [ -f "$SBPID" ]; do
        sleep 10
        if alive; then fails=0; continue; fi
        fails=$((fails+1))
        if [ $fails -eq 3 ] || [ $((fails % 30)) -eq 0 ]; then
            steered && { steer_off; log "WARP unreachable, failing open (direct internet)"; }
            pick_endpoint >/dev/null && { steer_on; fails=0; log "steering on again"; }
        fi
    done
}

rules_base() {
    # sing-box binds its WireGuard UDP to the real default interface itself
    # the health-probe address always goes through the tunnel
    ip -4 rule add to $PROBE/32 lookup 5150 priority $((PRIO-50))
}

# DNS: the network's resolver is usually on the LAN (bypasses the tunnel) and
# ISP resolvers can block sites. While WARP is on, Private DNS is set to
# Cloudflare (DNS-over-TLS through the tunnel); the previous setting is restored
# on down. Disable with WARP_DNS=0.
DNSPREV="$D/dns.prev"
# Another VPN (Tailscale, a work VPN, ...) owns its apps' DNS. Forcing strict
# Private DNS on top of it marks that VPN's DNS "broken" and every lookup fails.
other_vpn() { dumpsys connectivity 2>/dev/null | grep -q 'ni{VPN CONNECTED'; }
resolves() {
    for i in 1 2 3 4 5 6 7 8; do
        curl -s -m 3 -o /dev/null https://www.cloudflare.com/cdn-cgi/trace && return 0
        sleep 1
    done
    return 1
}
dns_on() {
    [ "${WARP_DNS:-1}" = 1 ] || return 0
    if other_vpn; then log "another VPN is active, leaving Private DNS alone"; return 0; fi
    [ -f "$DNSPREV" ] || printf '%s\n%s\n' "$(settings get global private_dns_mode)" \
        "$(settings get global private_dns_specifier)" > "$DNSPREV"
    settings put global private_dns_specifier one.one.one.one
    settings put global private_dns_mode hostname
    if ! resolves; then dns_off; log "Private DNS didn't resolve, restored the previous setting"; fi
}
dns_off() {
    [ -f "$DNSPREV" ] || return 0
    m=$(sed -n 1p "$DNSPREV"); h=$(sed -n 2p "$DNSPREV")
    if [ -z "$m" ] || [ "$m" = null ]; then settings delete global private_dns_mode >/dev/null
    else settings put global private_dns_mode "$m"; fi
    if [ -z "$h" ] || [ "$h" = null ]; then settings delete global private_dns_specifier >/dev/null
    else settings put global private_dns_specifier "$h"; fi
    rm -f "$DNSPREV"
}

down() {
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"
    steer_off
    sb_stop
    for fam in -4 -6; do
        while ip $fam rule del priority $((PRIO-100)) 2>/dev/null; do :; done
        while ip $fam rule del priority $((PRIO-50)) 2>/dev/null; do :; done
        ip $fam route flush table 5150 2>/dev/null
    done
    ip link del warp0 2>/dev/null
    dns_off
    log "down"; echo "warp down"
}

up() {
    down >/dev/null
    rules_base
    if ! ep=$(pick_endpoint); then
        echo "no WARP endpoint reachable, leaving routing alone"; down >/dev/null; exit 1
    fi
    steer_on
    dns_on
    log "up via $ep"
    nohup "$0" _watchdog >/dev/null 2>&1 &
    echo $! > "$PIDF"
    echo "warp up via $ep (uid $SELF_UID excluded)"
}

status() {
    if [ -f "$SBPID" ] && kill -0 "$(cat "$SBPID")" 2>/dev/null; then
        echo "sing-box running, endpoint $(jq -r '.endpoints[0].peers[0] | "\(.address):\(.port)"' "$D/sb-tun.json")"
    else echo "sing-box not running"; fi
    steered && echo "steering ON (all apps except uid $SELF_UID)" || echo "steering OFF (direct)"
    [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null && echo "watchdog running" || echo "watchdog not running"
    curl -s -m 5 https://$PROBE/cdn-cgi/trace | grep -E '^(ip|colo|warp)='
    tail -5 "$LOG" 2>/dev/null
}

# Missing pieces (e.g. after moving to a new phone/ROM) show up in the app as
# "Not set up" instead of a silent failure.
setup_ok() {
    miss=""
    for b in sing-box jq curl; do command -v $b >/dev/null 2>&1 || miss="$miss $b"; done
    [ -s "$D/reg.json" ] && [ -s "$D/priv" ] || miss="$miss account(reg.json/priv)"
    [ -x "$D/mkconf.sh" ] || miss="$miss mkconf.sh"
    [ -z "$miss" ] && return 0
    echo "SETUP missing:$miss"
    echo "In Termux: cd warp-switch && ./install.sh"
    return 1
}
case "${1:-status}" in down|_watchdog) ;; *) setup_ok || exit 3 ;; esac

case "${1:-status}" in
    up) up ;; down) down ;; _watchdog) watchdog ;; *) status ;;
esac
