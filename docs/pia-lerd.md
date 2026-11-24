# PIA VPN with lerd

PIA and lerd both want to own DNS on the machine:

- PIA's internal resolver (`hnsd`) binds `127.0.0.1:5300`; its firewall only allows DNS through that resolver while connected.
- lerd's DNS container also uses `127.0.0.1:5300`, and lerd's watcher rewrites the VPN interface's per-link DNS to that address after connect.
- On some networks, plain UDP DNS returns forged `NXDOMAIN` for `*.privateinternetaccess.com`, so the daemon cannot resolve its own API even when the zone is healthy over DNS-over-HTTPS.

The result is the classic "VPN connected but no Internet": the tunnel routes fine, direct `dig @10.0.0.243` works, but the system resolver points at a blocked `127.0.0.1:5300`.

## What install.sh sets up

When both PIA (`/opt/piavpn/bin/piactl`) and lerd are present, `install.sh`:

1. Installs `bin/pia-dns-helper.sh` to `~/.local/bin/pia-dns-helper.sh`.
2. Installs `systemd/user/pia-dns-helper.service` to `~/.config/systemd/user/pia-dns-helper.service` and enables/restarts it.
3. Resolves `api.privateinternetaccess.com` over Cloudflare DNS-over-HTTPS and writes the addresses to `~/.local/share/lerd/dnsmasq/99-pia.conf` as:
   ```
   address=/privateinternetaccess.com/<ip1>/<ip2>
   ```
4. Restarts `lerd-dns` only when that file changed, so the pin takes effect without disturbing a stable setup.

The helper watches `piactl get connectionstate`. On every `Connected`, it waits for lerd to claim the interface, then re-asserts PIA's tunnel DNS twice (after 5 and 12 seconds):

```bash
sudo -n resolvectl dns tun0 10.0.0.243
sudo -n resolvectl domain tun0 ~.
```

The `sudo -n` grant comes from lerd's `/etc/sudoers.d/lerd` entry for `resolvectl`. If that grant is missing, `install.sh` installs the files but does not enable or start the service and prints a warning.

Everything is best-effort: a failed DoH lookup, a missing user systemd bus, or a failed `lerd-dns` restart warns and continues.

## Verify

```bash
systemctl --user status pia-dns-helper
tail -n 20 ~/.local/state/pia-dns-helper/helper.log

dig @127.0.0.1 -p 5300 api.privateinternetaccess.com +short
curl -m 8 -sS -o /dev/null -w 'HTTP %{http_code}\n' \
  https://api.privateinternetaccess.com/api/client/status
```

While connected, `resolvectl dns tun0` should show `10.0.0.243`, and `journalctl -u systemd-resolved` shows who last set it.

After a reboot, `systemd-resolved` can fall back to the router as the main link's DNS if `lerd-dns` was not up yet. If `resolvectl status` shows that, re-assert lerd's resolver on the main interface and flush the cache:

```bash
sudo -n resolvectl dns <main-interface> 127.0.0.1:5300
resolvectl flush-caches
```

## Caveats

- The defaults are for PIA over OpenVPN: interface `tun0` and tunnel DNS `10.0.0.243`. Override them by editing the unit:
  ```
  Environment=PIA_TUN_IF=wgpia0 PIA_TUN_DNS=<resolver>
  ```
- The PIA zone addresses are Cloudflare-fronted and can change. Re-run `install.sh` to resolve and rewrite `99-pia.conf`.
- Restarting `lerd-dns` restarts its pasta network namespace. `install.sh` only does it when the pin file actually changed.
- PIA's GUI re-asserts its cached `overrideDNS` setting, so editing `/opt/piavpn/etc/settings.json` is not durable. The helper re-applies DNS independently and works in either mode.
- If PIA later fixes the `5300` collision, remove the helper service and `99-pia.conf`; nothing else depends on them.
