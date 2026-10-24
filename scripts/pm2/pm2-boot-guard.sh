#!/usr/bin/env bash
# After reboot pm2-root resurrects the old PM2 6 daemon on Node 20; replace it
# with PM2 7 on Node 24 through the /root/bin/pm2 wrapper without editing the unit.
set -u

PM2_HOME=${PM2_HOME:-/root/.pm2}
WANT=${WANT:-/root/.nvm/versions/node/v24.22.1/bin/node}
PM2=${PM2:-/root/bin/pm2}
UNIT=${UNIT:-pm2-root}
WAIT=${WAIT:-300}
SYSTEMCTL=${SYSTEMCTL:-systemctl}

log() { printf '%s pm2-boot-guard: %s\n' "$(date -Is)" "$*"; }
pid() { [ -f "$PM2_HOME/pm2.pid" ] && cat "$PM2_HOME/pm2.pid" 2>/dev/null; }
alive() {
  local p; p=$(pid)
  [ -n "$p" ] && [ -d "/proc/$p" ] || return 1
  tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q 'God Daemon'
}
exe() { local p; p=$(pid); [ -n "$p" ] && readlink "/proc/$p/exe" 2>/dev/null; }
ok() { alive && [ "$(exe)" = "$WANT" ] && { log "ok: daemon $(pid) on $WANT"; exit 0; }; }

case "${1:-}" in
  -h|--help) echo "usage: pm2-boot-guard.sh [-h|--help]  env: PM2_HOME WANT PM2 UNIT WAIT SYSTEMCTL"; exit 0 ;;
esac

ok

if "$SYSTEMCTL" is-enabled --quiet "$UNIT" 2>/dev/null; then
  i=0
  while [ "$i" -lt "$WAIT" ]; do
    case "$("$SYSTEMCTL" is-active "$UNIT" 2>/dev/null)" in active|failed) break ;; esac
    sleep 2; i=$((i + 2))
  done
fi

ok

state=$("$SYSTEMCTL" is-active "$UNIT" 2>/dev/null)
"$SYSTEMCTL" stop "$UNIT"
log "stopped $UNIT (state was $state)"

# resurrect while any daemon is alive would duplicate every process
if alive; then
  log "error: daemon $(pid) $(exe) still alive, resurrect skipped"
  exit 1
fi

"$PM2" resurrect
[ "$(exe)" = "$WANT" ] && { log "ok: resurrected on $WANT"; exit 0; }
log "error: after resurrect daemon $(pid) $(exe)"
exit 1
