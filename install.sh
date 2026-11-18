#!/data/data/com.termux/files/usr/bin/bash
# Run inside Termux. Installs the WARP scripts to ~/warp and registers a free account.
set -e
cd "$(dirname "$0")"
pkg install -y sing-box wireguard-tools jq curl
mkdir -p ~/warp && chmod 700 ~/warp
cp scripts/warp.sh scripts/mkconf.sh scripts/register.sh ~/warp/
chmod 700 ~/warp/*.sh
~/warp/register.sh
su -c true 2>/dev/null || { echo "Grant root to Termux in your root manager, then run: su -c ~/warp/warp.sh up"; exit 0; }
echo
echo "Done. Start:  su -c ~/warp/warp.sh up    Stop: su -c ~/warp/warp.sh down"
echo "Or install WarpSwitch.apk, grant it root, and use the app / Quick Settings tile."
