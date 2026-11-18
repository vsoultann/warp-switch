#!/data/data/com.termux/files/usr/bin/bash
# Registers a free Cloudflare WARP account for this device and saves
# priv (WireGuard private key) and reg.json next to this script (mode 600).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
cd "$D"
umask 077
if [ -s reg.json ] && jq -e .config.client_id reg.json >/dev/null 2>&1; then
    echo "already registered ($(jq -r .id reg.json))"; exit 0
fi
[ -s priv ] || wg genkey > priv
PUB=$(wg pubkey < priv)
curl -fsS -m 30 -X POST https://api.cloudflareclient.com/v0a2158/reg \
  -H 'User-Agent: okhttp/3.12.1' -H 'CF-Client-Version: a-6.10-2158' -H 'Content-Type: application/json' \
  -d "{\"key\":\"$PUB\",\"install_id\":\"\",\"fcm_token\":\"\",\"tos\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",\"model\":\"PC\",\"serial_number\":\"\",\"locale\":\"en_US\"}" > reg.json.tmp
jq -e .config.client_id reg.json.tmp >/dev/null
mv reg.json.tmp reg.json
echo "registered free WARP account $(jq -r .id reg.json)"
