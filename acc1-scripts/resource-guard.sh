#!/bin/bash
# ============================================================================
# resource-guard.sh — System Resource Guardian
# Monitors ALL processes. Kills anything consuming >60% CPU (warn) / >75% (kill) or >75% RAM.
# Logs every kill with full diagnostics for agent investigation.
# PM2: pm2 start resource-guard.sh --name resource-guard
# Created: 2026-02-07
# ============================================================================

set +e

# Load guard: skip if system is under heavy load
LOAD_NOW=$(awk '{print $1}' /proc/loadavg 2>/dev/null)
LOAD_INT=$(echo "$LOAD_NOW" | awk '{printf "%d", $1 * 10}')
if [ "${LOAD_INT:-0}" -gt 80 ]; then
    exit 0
fi

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/resource-guard.log"
KILL_LOG="/root/workspaces/tools/acc1-scripts/logs/resource-kills.log"
DIAG_DIR="/root/workspaces/tools/acc1-scripts/logs/diagnostics"
CHECK_INTERVAL=10  # seconds between checks

# Thresholds (from V117)
CPU_WARN=60
CPU_KILL=75
MEM_WARN=60
MEM_KILL=75

# Disk thresholds
DISK_WARN=70
DISK_EMERGENCY=75
DISK_CRITICAL=80

# Protected processes — NEVER kill these
PROTECTED_PIDS="1"  # init
PROTECTED_NAMES="sshd|systemd|dockerd|containerd|containerd-shim|pm2|redis-server|mysqld|nginx|grafana|zabbix|prometheus|dpkg|apt-get|dpkg-deb|apt|ps|sort|grep|awk|sed|wc|head|tail|cat|node|bash|claude|resource-guard"
# Protected by command-line args (for python3/node processes managed by PM2)
PROTECTED_ARGS="hr-bot-v2|action-log-index"

STATE_DIR="/root/workspaces/tools/acc1-scripts/data"

mkdir -p "$DIAG_DIR" "$(dirname "$LOG_FILE")" "$STATE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_kill() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$KILL_LOG" "$LOG_FILE"
}

# ============================================================================
# Cleanup stale state files for PIDs that no longer exist
# ============================================================================
cleanup_stale_state_files() {
    ls "$STATE_DIR"/cpu-hog-* 2>/dev/null | while read STATE_FILE; do
        [ -f "$STATE_FILE" ] || continue
        STALE_PID="${STATE_FILE##*/cpu-hog-}"
        if ! kill -0 "$STALE_PID" 2>/dev/null; then
            rm -f "$STATE_FILE"
        fi
    done
}

# ============================================================================
# Sustained CPU tracking: 60-75% zone held for >60s triggers SIGTERM/SIGKILL
# ============================================================================
check_sustained_cpu() {
    local PID=$1
    local CPU=$2
    local MEM=$3
    local COMM=$4
    local ARGS=$5

    local CPU_INT=${CPU%.*}
    local STATE_FILE="$STATE_DIR/cpu-hog-${PID}"
    local NOW
    NOW=$(date +%s)

    # Process dropped below warn threshold — remove state file if present
    if [ "$CPU_INT" -lt "$CPU_WARN" ]; then
        [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"
        return
    fi

    # Already handled by instant-kill logic (>=CPU_KILL)
    [ "$CPU_INT" -ge "$CPU_KILL" ] && return

    # CPU is in sustained zone (>= CPU_WARN and < CPU_KILL)
    if [ ! -f "$STATE_FILE" ]; then
        # First time seen — record timestamp
        echo "$NOW" > "$STATE_FILE"
        log "SUSTAINED-TRACK: $COMM (PID $PID) CPU=${CPU}% entered sustained zone — tracking started"
        return
    fi

    # State file exists — check how long in sustained zone
    local FIRST_SEEN
    FIRST_SEEN=$(cat "$STATE_FILE" 2>/dev/null)
    if [ -z "$FIRST_SEEN" ]; then
        echo "$NOW" > "$STATE_FILE"
        return
    fi

    local DURATION=$(( NOW - FIRST_SEEN ))

    if [ "$DURATION" -ge 60 ]; then
        log_kill "SUSTAINED-KILL: $COMM (PID $PID) CPU=${CPU}% for ${DURATION}s (threshold=60s) | $ARGS"
        DIAG=$(capture_diagnostics "$PID" "Sustained CPU ${CPU}% >= ${CPU_WARN}% for ${DURATION}s")
        kill -15 "$PID" 2>/dev/null
        local WAIT=0
        while [ "$WAIT" -lt 30 ]; do
            sleep 1
            WAIT=$(( WAIT + 1 ))
            kill -0 "$PID" 2>/dev/null || break
        done
        if kill -0 "$PID" 2>/dev/null; then
            kill -9 "$PID" 2>/dev/null
            log_kill "SUSTAINED-FORCE-KILL: PID $PID still alive after 30s — SIGKILL sent"
        fi
        save_to_redis "$PID" "$COMM" "SustainedCPU=${CPU}%>${CPU_WARN}%_for_${DURATION}s" "$DIAG"
        redis-cli SET "resource-guard:sustained:${PID}" \
            "{\"pid\":$PID,\"name\":\"$COMM\",\"cpu\":\"$CPU\",\"duration\":${DURATION},\"action\":\"SIGTERM+SIGKILL\",\"time\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}" \
            EX 3600 2>/dev/null
        log_kill "SUSTAINED diagnostics: $DIAG"
        rm -f "$STATE_FILE"
    else
        log "SUSTAINED-TRACKING: $COMM (PID $PID) CPU=${CPU}% for ${DURATION}s / 60s before action"
    fi
}

# ============================================================================
# Docker sustained CPU throttle: containers >60% CPU for >60s get throttled
# ============================================================================
check_docker_sustained() {
    # Require docker available
    command -v docker >/dev/null 2>&1 || return

    docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}" 2>/dev/null | while read CNAME CPERC; do
        # Strip trailing % and decimal
        local CCPU_INT
        CCPU_INT=$(echo "$CPERC" | tr -d '%' | cut -d'.' -f1)
        [ -z "$CCPU_INT" ] && continue
        # Ensure numeric
        [ "$CCPU_INT" -eq "$CCPU_INT" ] 2>/dev/null || continue

        local DOCKER_STATE_FILE="$STATE_DIR/cpu-hog-docker-${CNAME}"
        local NOW
        NOW=$(date +%s)

        if [ "$CCPU_INT" -lt "$CPU_WARN" ]; then
            [ -f "$DOCKER_STATE_FILE" ] && rm -f "$DOCKER_STATE_FILE"
            continue
        fi

        if [ ! -f "$DOCKER_STATE_FILE" ]; then
            echo "$NOW" > "$DOCKER_STATE_FILE"
            log "DOCKER-SUSTAINED-TRACK: container '$CNAME' CPU=${CPERC} — tracking started"
            continue
        fi

        local FIRST_SEEN
        FIRST_SEEN=$(cat "$DOCKER_STATE_FILE" 2>/dev/null)
        [ -z "$FIRST_SEEN" ] && { echo "$NOW" > "$DOCKER_STATE_FILE"; continue; }

        local DURATION=$(( NOW - FIRST_SEEN ))

        if [ "$DURATION" -ge 60 ]; then
            log_kill "DOCKER-THROTTLE: container '$CNAME' CPU=${CPERC} for ${DURATION}s — applying cpu limit 2.0"
            docker update --cpus=2.0 "$CNAME" 2>/dev/null \
                && log_kill "DOCKER-THROTTLE: '$CNAME' cpus limited to 2.0" \
                || log_kill "DOCKER-THROTTLE: '$CNAME' docker update failed (check docker version)"
            redis-cli LPUSH "resource-guard:docker_throttles" \
                "{\"container\":\"$CNAME\",\"cpu\":\"$CPERC\",\"duration\":${DURATION},\"time\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}" \
                2>/dev/null
            redis-cli LTRIM "resource-guard:docker_throttles" 0 49 2>/dev/null
            rm -f "$DOCKER_STATE_FILE"
        else
            log "DOCKER-SUSTAINED-TRACKING: container '$CNAME' CPU=${CPERC} for ${DURATION}s / 60s before throttle"
        fi
    done
}

# ============================================================================
# Diagnostics: capture full system state at time of kill
# ============================================================================
capture_diagnostics() {
    local PID=$1
    local REASON=$2
    local TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    local DIAG_FILE="$DIAG_DIR/kill-${PID}-${TIMESTAMP}.log"

    {
        echo "============================================"
        echo "PROCESS KILL DIAGNOSTIC REPORT"
        echo "============================================"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Killed PID: $PID"
        echo "Reason: $REASON"
        echo ""

        echo "--- KILLED PROCESS INFO ---"
        ps -p "$PID" -o pid,ppid,user,%cpu,%mem,vsz,rss,etime,args --no-headers 2>/dev/null || echo "(process already dead)"
        echo ""

        echo "--- PARENT PROCESS ---"
        PPID_VAL=$(ps -p "$PID" -o ppid --no-headers 2>/dev/null | tr -d ' ')
        if [ -n "$PPID_VAL" ]; then
            ps -p "$PPID_VAL" -o pid,user,%cpu,%mem,args --no-headers 2>/dev/null
        fi
        echo ""

        echo "--- CHILD PROCESSES ---"
        pgrep -P "$PID" 2>/dev/null | while read CHILD; do
            ps -p "$CHILD" -o pid,%cpu,%mem,args --no-headers 2>/dev/null
        done
        echo ""

        echo "--- SYSTEM STATE AT KILL TIME ---"
        echo "CPU Load: $(cat /proc/loadavg)"
        echo ""
        free -h
        echo ""

        echo "--- TOP 10 CPU CONSUMERS ---"
        ps aux --sort=-%cpu | head -11
        echo ""

        echo "--- TOP 10 MEM CONSUMERS ---"
        ps aux --sort=-%mem | head -11
        echo ""

        echo "--- DISK USAGE ---"
        df -h / /root 2>/dev/null
        echo ""

        echo "--- PM2 STATUS ---"
        pm2 jlist 2>/dev/null | timeout 30 python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for p in data:
        print(f\"  {p['name']:25s} {p['pm2_env']['status']:10s} CPU:{p['monit']['cpu']}% MEM:{p['monit']['memory']//1024//1024}MB restart:{p['pm2_env']['restart_time']}\")
except: print('  (pm2 unavailable)')
" 2>/dev/null
        echo ""

        echo "--- RECENT DMESG (OOM/errors) ---"
        dmesg --time-format iso 2>/dev/null | tail -20 | grep -iE 'oom|kill|out of memory|error' || echo "(no OOM events)"
        echo ""

        echo "============================================"
        echo "END OF DIAGNOSTIC REPORT"
        echo "============================================"
    } > "$DIAG_FILE" 2>&1

    echo "$DIAG_FILE"
}

# ============================================================================
# Check if process is protected
# ============================================================================
is_protected() {
    local PID=$1
    local NAME=$2
    local FULL_ARGS=$3

    # PID 1 and kernel threads
    [ "$PID" -le 2 ] 2>/dev/null && return 0

    # Protected names
    echo "$NAME" | grep -qiE "$PROTECTED_NAMES" && return 0

    # Protected by full command-line args (PM2-managed python/node scripts)
    if [ -n "$FULL_ARGS" ] && [ -n "$PROTECTED_ARGS" ]; then
        echo "$FULL_ARGS" | grep -qiE "$PROTECTED_ARGS" && return 0
    fi

    # Interactive Claude sessions (have TTY)
    local TTY=$(ps -p "$PID" -o tty --no-headers 2>/dev/null | tr -d ' ')
    if [ "$TTY" != "?" ] && [ -n "$TTY" ]; then
        echo "$NAME" | grep -qi "claude" && return 0
    fi

    return 1
}

# ============================================================================
# Save to Redis for agent access
# ============================================================================
save_to_redis() {
    local PID=$1
    local NAME=$2
    local REASON=$3
    local DIAG_FILE=$4
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    redis-cli LPUSH "resource-guard:kills" \
        "{\"pid\":$PID,\"name\":\"$NAME\",\"reason\":\"$REASON\",\"diag\":\"$DIAG_FILE\",\"time\":\"$TIMESTAMP\"}" \
        2>/dev/null
    redis-cli LTRIM "resource-guard:kills" 0 99 2>/dev/null
    redis-cli SET "resource-guard:last_kill" "$TIMESTAMP" 2>/dev/null
    redis-cli INCR "resource-guard:kill_count" 2>/dev/null
}

# ============================================================================
# Disk cleanup: emergency level (80-94%)
# ============================================================================
emergency_disk_cleanup() {
    log "DISK EMERGENCY: Starting cleanup..."

    # 3a. Truncate Apache logs inside stroy-php container
    docker exec stroy-php sh -c 'truncate -s 0 /var/log/apache2/*.log 2>/dev/null' 2>/dev/null \
        && log "DISK EMERGENCY: Truncated stroy-php Apache logs"

    # 3b. Prune Docker builder cache older than 24h
    docker builder prune -f --filter "until=24h" 2>/dev/null \
        && log "DISK EMERGENCY: Pruned Docker builder cache (>24h)"

    # 3c. Truncate Docker daemon json-logs larger than 50MB
    find /var/lib/docker/containers/ -name "*.log" -size +50M 2>/dev/null | while read LOGFILE; do
        truncate -s 0 "$LOGFILE" 2>/dev/null \
            && log "DISK EMERGENCY: Truncated large Docker log: $LOGFILE"
    done

    # 3d. Vacuum system journal to 100M
    journalctl --vacuum-size=100M 2>/dev/null \
        && log "DISK EMERGENCY: Vacuumed system journal to 100M"

    # 3e. Remove temp files older than 1 day
    find /tmp -maxdepth 1 -name "claude-*" -mtime +1 -exec rm -rf {} + 2>/dev/null \
        && log "DISK EMERGENCY: Cleaned /tmp/claude-* older than 1 day"

    log "DISK EMERGENCY: Cleanup complete"
}

# ============================================================================
# Disk cleanup: critical level (95%+)
# ============================================================================
critical_disk_cleanup() {
    # Run all emergency steps first
    emergency_disk_cleanup

    # Additionally truncate ALL Docker container Apache logs (not just stroy-php)
    for CONTAINER in $(docker ps --format '{{.Names}}' 2>/dev/null); do
        docker exec "$CONTAINER" sh -c 'truncate -s 0 /var/log/apache2/*.log 2>/dev/null' 2>/dev/null \
            && log "DISK CRITICAL: Truncated Apache logs in container: $CONTAINER"
    done

    # Log CRITICAL to Redis
    redis-cli SET "resource-guard:disk_critical" \
        "{\"time\":\"$(date '+%Y-%m-%d %H:%M:%S')\",\"message\":\"Disk usage reached CRITICAL level\"}" \
        EX 86400 2>/dev/null
    redis-cli LPUSH "resource-guard:disk_events" \
        "{\"level\":\"CRITICAL\",\"time\":\"$(date '+%Y-%m-%d %H:%M:%S')\"}" \
        2>/dev/null
    redis-cli LTRIM "resource-guard:disk_events" 0 49 2>/dev/null

    log "DISK CRITICAL: All cleanup steps complete, event saved to Redis"
}

# ============================================================================
# Main loop
# ============================================================================
log "=== RESOURCE GUARD STARTED ==="
log "Thresholds: CPU warn=${CPU_WARN}% kill=${CPU_KILL}% | MEM warn=${MEM_WARN}% kill=${MEM_KILL}%"
log "Disk thresholds: warn=${DISK_WARN}% emergency=${DISK_EMERGENCY}% critical=${DISK_CRITICAL}%"
log "Check interval: ${CHECK_INTERVAL}s"
log "Protected: ${PROTECTED_NAMES}"

WARN_COOLDOWN_FILE="/tmp/resource-guard-warned"

while true; do
    # Clean up state files for PIDs that no longer exist
    cleanup_stale_state_files

    # Get all processes sorted by CPU
    ps -eo pid,%cpu,%mem,comm,args --no-headers --sort=-%cpu 2>/dev/null | while read PID CPU MEM COMM ARGS; do
        # Skip empty or low usage
        CPU_INT=${CPU%.*}
        MEM_INT=${MEM%.*}
        [ -z "$CPU_INT" ] && continue
        [ "$CPU_INT" -lt "$CPU_WARN" ] && [ "$MEM_INT" -lt "$MEM_WARN" ] && continue

        # Skip own child processes (resource-guard spawns ps/sort/grep)
        PPID_OF_PROC=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
        [ "$PPID_OF_PROC" = "$$" ] && continue

        # Skip protected
        if is_protected "$PID" "$COMM" "$ARGS"; then
            # Still warn if protected process is high
            if [ "$CPU_INT" -ge "$CPU_WARN" ] || [ "$MEM_INT" -ge "$MEM_WARN" ]; then
                log "WARNING: Protected process $COMM (PID $PID) high usage: CPU=${CPU}% MEM=${MEM}%"
            fi
            continue
        fi

        # CPU KILL threshold
        if [ "$CPU_INT" -ge "$CPU_KILL" ]; then
            log_kill "KILL CPU: $COMM (PID $PID) CPU=${CPU}% MEM=${MEM}% | $ARGS"
            DIAG=$(capture_diagnostics "$PID" "CPU ${CPU}% >= ${CPU_KILL}% threshold")
            kill -15 "$PID" 2>/dev/null
            sleep 2
            # Force kill if still alive
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null
                log_kill "FORCE KILLED PID $PID (SIGTERM ignored)"
            fi
            save_to_redis "$PID" "$COMM" "CPU=${CPU}%>=${CPU_KILL}%" "$DIAG"
            log_kill "Diagnostics: $DIAG"
            continue
        fi

        # MEM KILL threshold
        if [ "$MEM_INT" -ge "$MEM_KILL" ]; then
            log_kill "KILL MEM: $COMM (PID $PID) CPU=${CPU}% MEM=${MEM}% | $ARGS"
            DIAG=$(capture_diagnostics "$PID" "MEM ${MEM}% >= ${MEM_KILL}% threshold")
            kill -15 "$PID" 2>/dev/null
            sleep 2
            if kill -0 "$PID" 2>/dev/null; then
                kill -9 "$PID" 2>/dev/null
                log_kill "FORCE KILLED PID $PID (SIGTERM ignored)"
            fi
            save_to_redis "$PID" "$COMM" "MEM=${MEM}%>=${MEM_KILL}%" "$DIAG"
            log_kill "Diagnostics: $DIAG"
            continue
        fi

        # WARN threshold (log only)
        if [ "$CPU_INT" -ge "$CPU_WARN" ] || [ "$MEM_INT" -ge "$MEM_WARN" ]; then
            log "WARN: $COMM (PID $PID) CPU=${CPU}% MEM=${MEM}% | $(echo "$ARGS" | head -c 100)"
        fi

        # Sustained CPU tracking (60-75% zone, kills after 60s)
        check_sustained_cpu "$PID" "$CPU" "$MEM" "$COMM" "$ARGS"

    done

    # ========================================================================
    # Disk space monitoring
    # ========================================================================
    DISK_USED=$(df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %')
    if [ -n "$DISK_USED" ] && [ "$DISK_USED" -eq "$DISK_USED" ] 2>/dev/null; then
        if [ "$DISK_USED" -ge "$DISK_CRITICAL" ]; then
            log "DISK CRITICAL: / usage=${DISK_USED}% (threshold=${DISK_CRITICAL}%)"
            critical_disk_cleanup
        elif [ "$DISK_USED" -ge "$DISK_EMERGENCY" ]; then
            log "DISK EMERGENCY: / usage=${DISK_USED}% (threshold=${DISK_EMERGENCY}%)"
            emergency_disk_cleanup
        elif [ "$DISK_USED" -ge "$DISK_WARN" ]; then
            log "DISK WARN: / usage=${DISK_USED}% (threshold=${DISK_WARN}%)"
        fi
    fi

    # Docker container sustained CPU throttle
    check_docker_sustained

    sleep "$CHECK_INTERVAL"
done
