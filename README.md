# WARP Switch

Phone-wide **Cloudflare WARP** for **rooted Android**, without the official 1.1.1.1 app and without Android's VPN slot.
One button (or a Quick Settings tile) turns it on and off.

Use it when the official app isn't an option: custom ROMs or guest frameworks where it isn't installed, VPN slot already in use, or networks where its default servers are throttled.

> Unofficial project, not affiliated with or endorsed by Cloudflare. It uses the free WARP service under Cloudflare's terms.

## How it works

- **Free account:** `register.sh` registers a free WARP account through Cloudflare's client API. It saves the WireGuard key and account to `~/warp` (mode 600, never leaves the phone).
- **Tunnel:** [sing-box](https://github.com/SagerNet/sing-box) creates a TUN interface `warp0` and connects to WARP over WireGuard. It sends WARP's three "reserved" bytes (the client id). Plain kernel WireGuard can't send them, and without them Cloudflare stalls most TLS handshakes for 2–5 s.
- **Routing:** policy rules (priority 13500) send the phone's own traffic for **every app except Termux** into `warp0`.
  - Termux stays on the direct connection, so a shell, ssh session or CLI agent never cuts itself off.
  - Private/LAN ranges bypass the tunnel. Hotspot clients are untouched.
- **Watchdog:** every 10 s it checks `https://1.0.0.1/cdn-cgi/trace` through the tunnel. If WARP stops answering, it **fails open**: the rules are removed so apps keep working on the normal connection. It then rotates through endpoints until one works and turns WARP back on.
- **Endpoints:** some ISPs throttle the default `162.159.192.x` endpoints, so `188.114.96-99.x` are tried first.
- **No VPN slot:** a real VPN app (including the official 1.1.1.1 app) still takes priority, because netd's VPN rules sit at 12000–13000. Turn this off before using another VPN, so the VPN's own connection isn't tunnelled through WARP.

IPv4 and IPv6 both go through WARP.

## Requirements

- Root (KernelSU, Magisk or APatch) and a kernel with TUN support (every Android kernel).
- [Termux](https://github.com/termux/termux-app) (F-Droid/GitHub build), with root granted to it once for setup.

## Install

In Termux:

```sh
pkg install -y git
git clone https://github.com/vsoultann/warp-switch
cd warp-switch && ./install.sh
```

Then install **WarpSwitch.apk** from the [latest release](https://github.com/vsoultann/warp-switch/releases/latest) and grant it root in your root manager.

- Open the app and tap the button.
- Optionally add the **WARP** tile in Quick Settings.

Or from Termux:

```sh
su -c ~/warp/warp.sh up      # start
su -c ~/warp/warp.sh status  # engine / routing / exit IP / log
su -c ~/warp/warp.sh down    # stop
```

The app shows **On** (with the exit IP and Cloudflare colo), **Reconnecting**, **Paused** (WARP unreachable, apps on the direct connection), or **Off**.

## Files

| Path | What |
|---|---|
| `scripts/warp.sh` | up / down / status, routing rules, watchdog |
| `scripts/mkconf.sh` | writes the sing-box config for an endpoint |
| `scripts/register.sh` | registers the free WARP account |
| `install.sh` | installs packages and the scripts to `~/warp`, registers |
| `app/` | WARP Switch app (plain Java, no Gradle; `app/build.sh` builds it in Termux) |

Runtime files in `~/warp`: `warp.log`, `singbox.log`, `sb-tun.json`. The account files `priv` and `reg.json` are private, so don't share them.

## Notes

- It isn't started at boot. Tap the button or tile once after a reboot.
- Exclude another uid: `su -c "WARP_EXCLUDE_UID=<uid> ~/warp/warp.sh up"` (defaults to Termux's uid).
- DNS: while WARP is on, Android's Private DNS is set to `one.one.one.one` (encrypted, through the tunnel). Your ISP/router resolver would otherwise bypass WARP and can block sites. Your previous Private DNS setting is restored on `down`. Opt out with `WARP_DNS=0`.

## License

MIT
