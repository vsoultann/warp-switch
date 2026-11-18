#!/data/data/com.termux/files/usr/bin/bash
# mkconf.sh <ip> <port>  -> writes sb-tun.json for sing-box (WARP with reserved bytes)
# Kernel WireGuard can't send WARP's 3 "reserved" bytes (client_id); without them
# Cloudflare drops/delays packets (TLS 2-5 s, timeouts). sing-box sends them.
D="$(cd "$(dirname "$0")" && pwd)"
R=$(jq -r '.config.client_id' "$D/reg.json" | base64 -d | od -An -tu1 | xargs | tr ' ' ',')
jq -n --arg priv "$(cat "$D/priv")" --arg peer "$(jq -r '.config.peers[0].public_key' "$D/reg.json")" \
  --arg v4 "$(jq -r .config.interface.addresses.v4 "$D/reg.json")" --arg v6 "$(jq -r .config.interface.addresses.v6 "$D/reg.json")" \
  --arg ip "$1" --argjson port "$2" --argjson res "[$R]" '{
 log:{level:"warn"},
 inbounds:[{type:"tun",tag:"tun",interface_name:"warp0",address:["172.19.0.1/30","fdfe:dcba:9876::1/126"],
   mtu:1280,auto_route:false,stack:"gvisor"}],
 endpoints:[{type:"wireguard",tag:"warp",mtu:1280,address:[($v4+"/32"),($v6+"/128")],private_key:$priv,
   peers:[{address:$ip,port:$port,public_key:$peer,allowed_ips:["0.0.0.0/0","::/0"],reserved:$res,persistent_keepalive_interval:25}]}],
 route:{final:"warp",auto_detect_interface:true}}' > "$D/sb-tun.json"
chmod 600 "$D/sb-tun.json"
