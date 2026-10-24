#!/bin/bash
set -u
D=$(cd "$(dirname "$0")/.." && pwd -P)
S="$D/scripts/pm2/pm2-boot-guard.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export T CALLS="$T/calls" PM2PID="$T/home/pm2.pid"
export PM2_HOME="$T/home" WAIT=4
TESTPID=$$
export TESTPID
ME=$(readlink "/proc/$$/exe")

mkdir -p "$T/home" "$T/bin"
cat >"$T/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
case "$1" in
  is-enabled) exit 0 ;;
  is-active) [ "${2:-}" = --quiet ] && exit 0; echo active; exit 0 ;;
  stop) [ "${STOP_KEEPS:-0}" = 1 ] || : > "$PM2PID"; exit 0 ;;
esac
exit 0
EOF
cat >"$T/bin/pm2" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CALLS"
[ "$1" = resurrect ] && echo "$TESTPID" > "$PM2PID"
exit 0
EOF
chmod +x "$T/bin/systemctl" "$T/bin/pm2"
export SYSTEMCTL="$T/bin/systemctl" PM2="$T/bin/pm2"

fail=0
bad() { echo "FAIL $1: $2"; fail=1; }
run() { WANT="$ME" bash "$S" >/dev/null 2>&1; }

rm -f "$CALLS"; echo "$$" >"$PM2PID"
run; rc=$?
[ "$rc" = 0 ] || bad case1 "rc=$rc"
[ ! -s "$CALLS" ] || bad case1 "calls: $(cat "$CALLS")"

rm -f "$CALLS"; echo 1 >"$PM2PID"
run; rc=$?
[ "$rc" = 0 ] || bad case2 "rc=$rc"
grep -qx 'stop pm2-root' "$CALLS" || bad case2 "no stop"
grep -qx 'resurrect' "$CALLS" || bad case2 "no resurrect"

rm -f "$CALLS"; echo 1 >"$PM2PID"
export STOP_KEEPS=1
run; rc=$?
[ "$rc" = 1 ] || bad case3 "rc=$rc"
grep -qx 'resurrect' "$CALLS" && bad case3 "resurrect called"

[ "$fail" = 0 ] && { echo "ok 3/3"; exit 0; }
exit 1
