#!/bin/bash
# ============================================================================
# TEST: Resource Guard — Visual Stress Test
# PART 1: CPU ramp over 2 minutes  → green → yellow → red → KILL
# PART 2: RAM ramp over 1.5 min    → green → yellow → red → KILL
# Grafana: http://<server>:3001/d/resource-guard-test/
# DELETE AFTER: rm /root/workspaces/tools/acc1-scripts/scripts/test-resource-guard.sh
# ============================================================================

set +e

ENV_FILE="/root/workspaces/tools/etc/tools-env"
if [ -f "$ENV_FILE" ]; then
    . "$ENV_FILE"
else
    echo "Error: Environment file not found: $ENV_FILE" >&2
    exit 1
fi

for var in RESOURCE_GUARD_AUTH_USER RESOURCE_GUARD_AUTH_PASS; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable '$var' is not set" >&2
        exit 1
    fi
done

# ── Colors ──
R='\033[1;31m'; Y='\033[1;33m'; G='\033[1;32m'; C='\033[1;36m'
W='\033[1;37m'; D='\033[0;90m'; N='\033[0m'
BR='\033[41m'; BG_='\033[42m'; BY='\033[43m'

# ── Config ──
NPROC=$(nproc 2>/dev/null || echo 4)
BAR_W=40
GUARD_LOG="/root/workspaces/tools/acc1-scripts/logs/resource-guard.log"
DIAG_DIR="/root/workspaces/tools/acc1-scripts/logs/diagnostics"
TMP_DIR="/tmp/resource-guard-test-$$"
mkdir -p "$TMP_DIR"

# ── Tracking ──
ALL_PIDS=()

cleanup() {
    echo ""
    printf "\n  ${Y}⛔ Stopping — killing all test workers...${N}\n"
    for P in "${ALL_PIDS[@]}"; do kill "$P" 2>/dev/null; done
    pkill -f 'test-stress-worker' 2>/dev/null
    pkill -f 'test-cpu-ramp' 2>/dev/null
    pkill -f 'test-mem-ramp' 2>/dev/null
    rm -rf "$TMP_DIR" /tmp/test-mem-ramp.py /tmp/test-cpu-worker.py 2>/dev/null
    sleep 1
    printf "  ${G}✔ Clean. ${D}Load: $(cat /proc/loadavg | cut -d' ' -f1-3) | Free RAM: $(free -h | awk '/Mem:/{print $4}')${N}\n\n"
}
trap cleanup EXIT INT TERM

# ══════════════════════════════════════════════════════════════
# draw_bar  <percent>  <label>
# ══════════════════════════════════════════════════════════════
draw_bar() {
    local pct=$1 label="$2"
    local w=$BAR_W
    local filled=$((pct * w / 100))
    [ $filled -gt $w ] && filled=$w
    [ $filled -lt 0 ] && filled=0
    local empty=$((w - filled))

    local fg="$G" bg="$BG_"
    [ $pct -ge 70 ] && fg="$Y" && bg="$BY"
    [ $pct -ge 90 ] && fg="$R" && bg="$BR"

    printf "  ${W}%-5s${N} ${D}|${N}" "$label"
    [ $filled -gt 0 ] && printf "${bg}%${filled}s${N}" ""
    [ $empty  -gt 0 ] && printf "${D}%${empty}s${N}" ""
    printf "${D}|${N} ${fg}%3d%%${N}" "$pct"
}

# ══════════════════════════════════════════════════════════════
# get_system_cpu — reads /proc/stat, returns CPU% (0-100)
# ══════════════════════════════════════════════════════════════
CPU_PREV_TOTAL=0
CPU_PREV_IDLE=0

get_system_cpu() {
    local line
    read -r line < /proc/stat
    set -- $line
    shift  # skip "cpu" label
    local user=$1 nice=$2 system=$3 idle=$4 iowait=$5 irq=$6 softirq=$7 steal=${8:-0}
    local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    local diff_total=$((total - CPU_PREV_TOTAL))
    local diff_idle=$((idle + iowait - CPU_PREV_IDLE))
    CPU_PREV_TOTAL=$total
    CPU_PREV_IDLE=$((idle + iowait))
    if [ $diff_total -gt 0 ]; then
        echo $(( (diff_total - diff_idle) * 100 / diff_total ))
    else
        echo 0
    fi
}

# Prime the CPU reader (first call returns garbage)
get_system_cpu > /dev/null
sleep 1

# ══════════════════════════════════════════════════════════════
# Python: CPU worker with controlled duty cycle
# ══════════════════════════════════════════════════════════════
cat > /tmp/test-cpu-worker.py << 'PYEOF'
"""CPU worker with controlled duty cycle. Usage: python3 test-cpu-worker.py <duty_pct>"""
import sys, time, os
os.environ['PYTHONDONTWRITEBYTECODE'] = '1'
duty = int(sys.argv[1]) if len(sys.argv) > 1 else 50  # percent of 100ms window
window = 0.1  # 100ms
burn_time = window * duty / 100.0
while True:
    start = time.monotonic()
    while time.monotonic() - start < burn_time:
        pass  # burn
    remaining = window - (time.monotonic() - start)
    if remaining > 0.001:
        time.sleep(remaining)
PYEOF

# ══════════════════════════════════════════════════════════════
# Python: RAM eater with gradual allocation
# ══════════════════════════════════════════════════════════════
cat > /tmp/test-mem-ramp.py << 'PYEOF'
"""RAM eater: allocates chunk_mb every interval_sec seconds, up to max_chunks"""
import sys, time
chunk_mb = int(sys.argv[1]) if len(sys.argv) > 1 else 200
interval = int(sys.argv[2]) if len(sys.argv) > 2 else 10
max_chunks = int(sys.argv[3]) if len(sys.argv) > 3 else 30
blocks = []
for i in range(max_chunks):
    try:
        b = bytearray(chunk_mb * 1024 * 1024)
        for j in range(0, len(b), 4096):
            b[j] = 1
        blocks.append(b)
        total = len(blocks) * chunk_mb
        print(f"ALLOC {total}MB", flush=True)
        time.sleep(interval)
    except MemoryError:
        print("OOM", flush=True)
        break
while True:
    time.sleep(1)
PYEOF

# ══════════════════════════════════════════════════════════════
# HEADER
# ══════════════════════════════════════════════════════════════
clear
echo ""
printf "${C}╔════════════════════════════════════════════════════════════╗${N}\n"
printf "${C}║${N}  ${W}RESOURCE GUARD — STRESS TEST${N}                              ${C}║${N}\n"
printf "${C}║${N}  ${D}CPUs: ${NPROC} | Guard: 10s cycle | CPU: 2min, RAM: 1.5min${N}     ${C}║${N}\n"
printf "${C}╠════════════════════════════════════════════════════════════╣${N}\n"
printf "${C}║${N}  ${D}Grafana: http://localhost:3001/d/resource-guard-test/${N}       ${C}║${N}\n"
printf "${C}║${N}  ${D}Ctrl+C = stop test and cleanup${N}                             ${C}║${N}\n"
printf "${C}╚════════════════════════════════════════════════════════════╝${N}\n"
echo ""
printf "  ${D}Thresholds:${N} ${G}■${N} ${D}<70%% OK${N}   ${Y}■${N} ${D}70%% WARN${N}   ${R}■${N} ${D}90%% KILL${N}\n"
echo ""

LOG_BEFORE=$(wc -l < "$GUARD_LOG" 2>/dev/null || echo 0)

# ══════════════════════════════════════════════════════════════
#  PART 1: CPU RAMP — 2 MINUTES (120 seconds)
# ══════════════════════════════════════════════════════════════
printf "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"
printf "  ${W}▶ PART 1: CPU STRESS${N}  ${D}(2 minutes)${N}\n"
printf "  ${D}Adding workers with controlled duty cycles${N}\n"
printf "  ${D}Guard kills any single process at ≥90%% CPU${N}\n"
printf "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"
echo ""

# Schedule: time → add worker at X% duty cycle
# Each worker on 4-core = ~X/4% system CPU
# Phase 1 (0-40s):   2 workers at 50% → ~25% system
# Phase 2 (40-70s):  +2 workers at 60% → ~52% system
# Phase 3 (70-95s):  +2 workers at 70% → ~73% system (WARNING)
# Phase 4 (95-110s): +1 worker at 80% → ~86% system
# Phase 5 (110-120s): +1 worker at 100% → triggers KILL (100% per-process)

SCHEDULE=(
    "0:50"    # t=0s: worker at 50% duty
    "15:50"   # t=15s: worker at 50% duty
    "40:60"   # t=40s: worker at 60%
    "55:60"   # t=55s: worker at 60%
    "70:70"   # t=70s: worker at 70%  → warning zone
    "80:70"   # t=80s: worker at 70%
    "95:80"   # t=95s: worker at 80%
    "110:99"  # t=110s: worker at 99% → KILL ZONE
)

CPU_KILLED=0
NEXT_IDX=0
TOTAL_WORKERS=0
START_TIME=$(date +%s)

for ELAPSED in $(seq 0 120); do
    # Check if it's time to launch next worker
    while [ $NEXT_IDX -lt ${#SCHEDULE[@]} ]; do
        SCHED="${SCHEDULE[$NEXT_IDX]}"
        SCHED_TIME="${SCHED%%:*}"
        SCHED_DUTY="${SCHED##*:}"

        if [ $ELAPSED -ge $SCHED_TIME ]; then
            TOTAL_WORKERS=$((TOTAL_WORKERS + 1))
            python3 /tmp/test-cpu-worker.py "$SCHED_DUTY" &
            PID=$!
            ALL_PIDS+=($PID)

            # Zone label
            ZONE="${G}SAFE${N}"
            [ $SCHED_DUTY -ge 70 ] && ZONE="${Y}⚠ WARN${N}"
            [ $SCHED_DUTY -ge 90 ] && ZONE="${R}☠ KILL${N}"

            echo ""
            printf "  ${W}+ Worker #${TOTAL_WORKERS}${N} ${D}PID ${PID}${N} duty=${SCHED_DUTY}%%  ${ZONE}\n"
            NEXT_IDX=$((NEXT_IDX + 1))
        else
            break
        fi
    done

    sleep 1

    # Read system-wide CPU
    SYS_CPU=$(get_system_cpu)

    # Count alive workers
    ALIVE=0
    for P in "${ALL_PIDS[@]}"; do
        kill -0 "$P" 2>/dev/null && ALIVE=$((ALIVE + 1))
    done

    # Draw bar
    printf "\r"
    draw_bar $SYS_CPU "CPU"
    NOW=$(date +%s)
    REAL_ELAPSED=$((NOW - START_TIME))
    printf "  ${D}workers:${N}${W}${ALIVE}${N} ${D}time:${N}${W}${REAL_ELAPSED}s${N}${D}/120s${N}   "

    # Check if guard killed something
    if [ $ALIVE -lt $TOTAL_WORKERS ] && [ $TOTAL_WORKERS -gt 0 ]; then
        CPU_KILLED=1
        echo ""
        echo ""
        printf "  ${BR}${W} ⚡ RESOURCE GUARD KILLED A CPU WORKER! ${N}\n"
        printf "  ${R}Workers: ${ALIVE}/${TOTAL_WORKERS} alive | Time: ${REAL_ELAPSED}s | System CPU: ${SYS_CPU}%%${N}\n"
        break
    fi
done

if [ $CPU_KILLED -eq 0 ]; then
    echo ""
    printf "\n  ${Y}⚠ No kill detected in 120s${N}\n"
fi

# Cleanup CPU workers
for P in "${ALL_PIDS[@]}"; do kill "$P" 2>/dev/null; done
pkill -f 'test-cpu-worker' 2>/dev/null
ALL_PIDS=()
sleep 2

# Guard log (CPU)
echo ""
printf "  ${C}── Guard Log (CPU) ──${N}\n"
LOG_MID=$(wc -l < "$GUARD_LOG" 2>/dev/null || echo 0)
if [ $LOG_MID -gt $LOG_BEFORE ]; then
    tail -n $((LOG_MID - LOG_BEFORE)) "$GUARD_LOG" 2>/dev/null | while IFS= read -r LINE; do
        if echo "$LINE" | grep -q "KILL"; then printf "  ${R}%s${N}\n" "$LINE"
        elif echo "$LINE" | grep -q "WARN"; then printf "  ${Y}%s${N}\n" "$LINE"
        else printf "  ${D}%s${N}\n" "$LINE"; fi
    done
else
    printf "  ${D}(no entries)${N}\n"
fi

echo ""
printf "  ${D}Cooling down 10s before RAM test...${N}\n"
for i in $(seq 10 -1 1); do
    printf "\r  ${D}  ${i}s...${N}   "
    sleep 1
done
echo ""

# ══════════════════════════════════════════════════════════════
#  PART 2: RAM RAMP — 1.5 MINUTES (90 seconds)
# ══════════════════════════════════════════════════════════════
LOG_BEFORE=$(wc -l < "$GUARD_LOG" 2>/dev/null || echo 0)

printf "\n${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"
printf "  ${W}▶ PART 2: RAM STRESS${N}  ${D}(1.5 minutes)${N}\n"
printf "  ${D}Allocating 200MB every 10 seconds${N}\n"
printf "  ${D}Guard kills when process MEM ≥90%%${N}\n"
printf "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}\n"
echo ""

TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MB=$((TOTAL_KB / 1024))
AVAIL_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
AVAIL_MB=$((AVAIL_KB / 1024))
USED_MB=$((TOTAL_MB - AVAIL_MB))
USED_PCT=$((USED_MB * 100 / TOTAL_MB))

printf "  ${D}Total: ${TOTAL_MB}MB | Current: ${USED_MB}MB (${USED_PCT}%%) | Free: ${AVAIL_MB}MB${N}\n"

# 200MB chunks every 10 seconds, up to 30 chunks
CHUNK_MB=200
MAX_CHUNKS=30

printf "  ${D}Plan: ${CHUNK_MB}MB every 10s (max ${MAX_CHUNKS} chunks)${N}\n"
echo ""

python3 /tmp/test-mem-ramp.py $CHUNK_MB 10 $MAX_CHUNKS &
MEM_PID=$!
ALL_PIDS+=($MEM_PID)

printf "  ${W}Memory eater PID: ${MEM_PID}${N}\n"
echo ""

MEM_KILLED=0
START_TIME=$(date +%s)
LAST_RSS=0

for t in $(seq 1 100); do
    sleep 1

    if ! kill -0 "$MEM_PID" 2>/dev/null; then
        MEM_KILLED=1
        NOW=$(date +%s)
        REAL_ELAPSED=$((NOW - START_TIME))
        echo ""
        printf "  ${BR}${W} ⚡ RESOURCE GUARD KILLED MEMORY EATER! ${N}\n"
        printf "  ${R}Time: ${REAL_ELAPSED}s | Last RSS: ${LAST_RSS}MB${N}\n"
        break
    fi

    # System RAM
    AV_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    AV_MB=$((AV_KB / 1024))
    US_MB=$((TOTAL_MB - AV_MB))
    M_PCT=$((US_MB * 100 / TOTAL_MB))
    [ $M_PCT -gt 100 ] && M_PCT=100

    # Process RSS
    RSS_KB=$(ps -p $MEM_PID -o rss --no-headers 2>/dev/null | tr -d ' ')
    RSS_MB=$(( ${RSS_KB:-0} / 1024 ))
    LAST_RSS=$RSS_MB
    PROC_PCT=$(ps -p $MEM_PID -o %mem --no-headers 2>/dev/null | tr -d ' ' | cut -d. -f1)

    NOW=$(date +%s)
    REAL_ELAPSED=$((NOW - START_TIME))

    printf "\r"
    draw_bar $M_PCT "RAM"
    printf "  ${D}${US_MB}/${TOTAL_MB}MB${N}  ${D}proc:${RSS_MB}MB(${PROC_PCT:-0}%%)${N}  ${D}${REAL_ELAPSED}s${N}   "

    # Log chunk allocations
    if [ $((t % 10)) -eq 0 ]; then
        echo ""
        ZONE="${G}OK${N}"
        [ ${PROC_PCT:-0} -ge 70 ] && ZONE="${Y}⚠ WARN${N}"
        [ ${PROC_PCT:-0} -ge 90 ] && ZONE="${R}☠ KILL ZONE${N}"
        printf "  ${D}  ▸ chunk #$((t/10)): proc=${RSS_MB}MB (${PROC_PCT:-0}%%)${N}  ${ZONE}\n"
    fi
done

if [ $MEM_KILLED -eq 0 ]; then
    echo ""
    if kill -0 "$MEM_PID" 2>/dev/null; then
        printf "\n  ${Y}⚠ Guard did not kill in 100s${N}\n"
        kill "$MEM_PID" 2>/dev/null
    fi
fi

sleep 2
rm -f /tmp/test-mem-ramp.py /tmp/test-cpu-worker.py

# Guard log (RAM)
echo ""
printf "  ${C}── Guard Log (RAM) ──${N}\n"
LOG_END=$(wc -l < "$GUARD_LOG" 2>/dev/null || echo 0)
if [ $LOG_END -gt $LOG_BEFORE ]; then
    tail -n $((LOG_END - LOG_BEFORE)) "$GUARD_LOG" 2>/dev/null | while IFS= read -r LINE; do
        if echo "$LINE" | grep -q "KILL"; then printf "  ${R}%s${N}\n" "$LINE"
        elif echo "$LINE" | grep -q "WARN"; then printf "  ${Y}%s${N}\n" "$LINE"
        else printf "  ${D}%s${N}\n" "$LINE"; fi
    done
else
    printf "  ${D}(no entries)${N}\n"
fi

# ══════════════════════════════════════════════════════════════
#  FINAL REPORT
# ══════════════════════════════════════════════════════════════
echo ""
echo ""
printf "${C}╔════════════════════════════════════════════════════════════╗${N}\n"
printf "${C}║${N}  ${W}RESULTS${N}                                                    ${C}║${N}\n"
printf "${C}╚════════════════════════════════════════════════════════════╝${N}\n"
echo ""

if [ $CPU_KILLED -eq 1 ]; then
    printf "  ${G}✔ CPU TEST: PASSED${N} — guard killed high-CPU process\n"
else
    printf "  ${R}✘ CPU TEST: FAILED${N}\n"
fi

if [ $MEM_KILLED -eq 1 ]; then
    printf "  ${G}✔ RAM TEST: PASSED${N} — guard killed high-MEM process\n"
else
    printf "  ${R}✘ RAM TEST: FAILED${N}\n"
fi

echo ""

LATEST=$(ls -t "$DIAG_DIR" 2>/dev/null | head -1)
if [ -n "$LATEST" ]; then
    printf "  ${C}── Latest Diagnostic ──${N}\n"
    printf "  ${D}${DIAG_DIR}/${LATEST}${N}\n"
    head -10 "$DIAG_DIR/$LATEST" 2>/dev/null | while IFS= read -r LINE; do
        printf "  ${D}  %s${N}\n" "$LINE"
    done
    printf "  ${D}  ...${N}\n"
fi

echo ""
printf "  ${D}Load: $(cat /proc/loadavg | cut -d' ' -f1-3)${N}\n"
printf "  ${D}Free: $(free -h | awk '/Mem:/{print $4}')${N}\n"
echo ""
printf "  ${C}Grafana: http://localhost:3001/d/resource-guard-test/${N}\n"
echo ""
printf "  ${Y}Cleanup:${N}\n"
printf "  ${D}  rm /root/workspaces/tools/acc1-scripts/scripts/test-resource-guard.sh${N}\n"
printf "  ${D}      curl -s -u "$RESOURCE_GUARD_AUTH_USER:$RESOURCE_GUARD_AUTH_PASS" -X DELETE http://localhost:3001/api/dashboards/uid/resource-guard-test${N}\n"
echo ""
