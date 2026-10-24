#!/bin/bash
set -u
D=$(cd "$(dirname "$0")/.." && pwd -P)
S="$D/scripts/pm2/pm2-boot-guard.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export CALLS="$T/calls" PM2PID="$T/home/pm2.pid"
export PM2_HOME="$T/home"
ME_PID=$$
ME_EXE=$(readlink "/proc/$$/exe")

mkdir -p "$T/home" "$T/bin"
cat >"$T/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
  is-enabled) exit 0 ;;
  is-active)
    [ "${2:-}" = --quiet ] && { [ "${MODE:-}" = activating ] && exit 3; exit 0; }
    [ "${MODE:-}" = activating ] && { echo activating; exit 3; }
    echo active; exit 0
    ;;
  stop) [ "${STOP_KEEPS:-0}" = 1 ] || : > "$PM2PID"; exit 0 ;;
esac
exit 0
EOF
cat >"$T/bin/pm2" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
[ "$1" = resurrect ] && echo "$NEWPID" > "$PM2PID"
exit 0
EOF
chmod +x "$T/bin/systemctl" "$T/bin/pm2"
export SYSTEMCTL="$T/bin/systemctl" PM2="$T/bin/pm2"

SPAWNED=
spawn() {
  local p i=0
  if [ "$1" = bash ]; then
    ( exec -a 'PM2 God Daemon' /usr/bin/bash -c 'sleep 20; :' ) >/dev/null 2>&1 &
  else
    ( exec -a 'PM2 God Daemon' /usr/bin/sleep 20 ) >/dev/null 2>&1 &
  fi
  p=$!
  while [ "$i" -lt 100 ]; do
    tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null | grep -q 'God Daemon' && break
    sleep 0.05
    i=$((i + 1))
  done
  SPAWNED=$p
}
want_of() { readlink "/proc/$1/exe"; }

fail=0
bad() { echo "FAIL $1: $2"; fail=1; }
run() { WANT="$1" WAIT="${2:-4}" bash "$S" >/dev/null 2>&1; }

spawn sleep; OLD=$SPAWNED
spawn bash; NEW=$SPAWNED
WANT_NEW=$(want_of "$NEW")
export NEWPID="$NEW"

rm -f "$CALLS" "$PM2PID"; echo "$NEW" >"$PM2PID"
run "$WANT_NEW"; rc=$?
[ "$rc" = 0 ] || bad case1 "rc=$rc"
[ ! -s "$CALLS" ] || bad case1 "calls: $(cat "$CALLS")"

rm -f "$CALLS" "$PM2PID"; echo "$OLD" >"$PM2PID"
run "$WANT_NEW"; rc=$?
[ "$rc" = 0 ] || bad case2 "rc=$rc"
grep -qx 'stop pm2-root' "$CALLS" || bad case2 "no stop"
grep -qx 'resurrect' "$CALLS" || bad case2 "no resurrect"

rm -f "$CALLS" "$PM2PID"; echo "$OLD" >"$PM2PID"
export STOP_KEEPS=1
run "$WANT_NEW"; rc=$?
unset STOP_KEEPS
[ "$rc" = 1 ] || bad case3 "rc=$rc"
grep -qx 'resurrect' "$CALLS" && bad case3 "resurrect called"

rm -f "$CALLS" "$PM2PID"; echo "$ME_PID" >"$PM2PID"
run "$ME_EXE"; rc=$?
grep -qx 'stop pm2-root' "$CALLS" || bad case4 "no stop"
grep -qx 'resurrect' "$CALLS" || bad case4 "no resurrect"

rm -f "$CALLS" "$PM2PID"; echo "$OLD" >"$PM2PID"
export MODE=activating
run "$WANT_NEW"; rc=$?
unset MODE
grep -qx 'stop pm2-root' "$CALLS" || bad case5 "no stop"
grep -qx 'resurrect' "$CALLS" || bad case5 "no resurrect"
s=$(grep -n '^stop pm2-root$' "$CALLS" | cut -d: -f1)
r=$(grep -n '^resurrect$' "$CALLS" | cut -d: -f1)
{ [ -n "$s" ] && [ -n "$r" ] && [ "$s" -lt "$r" ]; } || bad case5 "stop not before resurrect"

[ "$fail" = 0 ] && { echo "ok 5/5"; exit 0; }
exit 1
