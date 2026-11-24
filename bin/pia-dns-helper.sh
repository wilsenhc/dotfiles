#!/usr/bin/env bash
# pia-dns-helper: keep the PIA tunnel interface's DNS on PIA's resolver.
#
# PIA's DNS works, but lerd's watcher claims the VPN interface right after
# connect and points it at 127.0.0.1:5300, which PIA's firewall blocks while
# connected. This re-asserts PIA's tunnel DNS a few seconds after every
# Connected state.
#
# Per-machine values: the interface (tun0 for OpenVPN) and PIA's tunnel DNS
# (10.0.0.243 in the field) can be overridden with PIA_TUN_IF/PIA_TUN_DNS.
# State lives under ~/.local/state/pia-dns-helper so it survives reboots.
STATEDIR="${XDG_STATE_HOME:-$HOME/.local/state}/pia-dns-helper"
mkdir -p "$STATEDIR" 2>/dev/null || exit 1
LOG="$STATEDIR/helper.log"
STOPFLAG="$STATEDIR/stop"
TUN_IF="${PIA_TUN_IF:-tun0}"
TUN_DNS="${PIA_TUN_DNS:-10.0.0.243}"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null || true; }

fix() {
  sleep 5 # let PIA set the interface and lerd claim it first
  log "pass1: $TUN_IF -> $TUN_DNS"
  sudo -n resolvectl dns "$TUN_IF" "$TUN_DNS" >>"$LOG" 2>&1 || log "pass1 dns FAILED"
  sudo -n resolvectl domain "$TUN_IF" '~.' >>"$LOG" 2>&1 || log "pass1 domain FAILED"
  sleep 12
  log "pass2: re-assert $TUN_IF -> $TUN_DNS"
  sudo -n resolvectl dns "$TUN_IF" "$TUN_DNS" >>"$LOG" 2>&1 || log "pass2 dns FAILED"
  sudo -n resolvectl domain "$TUN_IF" '~.' >>"$LOG" 2>&1 || log "pass2 domain FAILED"
  log "fix done"
}

log "dnshelper started"
LAST=""
while :; do
  s=$(piactl --timeout 3 get connectionstate 2>/dev/null || echo Unknown)
  if [ "$s" != "$LAST" ]; then
    LAST="$s"
    log "state -> $s"
    [ "$s" = Connected ] && fix &
  fi
  [ -f "$STOPFLAG" ] && { log "stopped"; exit 0; }
  sleep 2
done
