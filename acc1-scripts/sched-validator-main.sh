#!/bin/bash
# sched-validator.sh — PM2 Validation Service
# DESIGN: NEVER CRASHES, ALWAYS LOGS
#
# Runs every 5 minutes and validates:
# - Hooks syntax (bash -n)
# - Settings JSON validity
# - PM2 services health
# - Redis connectivity
# - Scripts syntax
#
# Creates: validation-status.json for agents to read

set -o pipefail  # Catch pipe failures
# NO set -e — We handle ALL errors manually

PROFILE_DIR="/root/workspaces/tools/acc1-scripts"
LOG_FILE="$PROFILE_DIR/logs/validator.log"
ERROR_LOG="$PROFILE_DIR/logs/validator-errors.log"
STATUS_FILE="$PROFILE_DIR/validation-status.json"
INTERVAL=300  # 5 minutes

# Ensure log directory exists
mkdir -p "$PROFILE_DIR/logs"

# Trap ALL signals and log them (don't exit)
trap 'log "SIGNAL: Received signal, continuing..."' SIGINT SIGTERM SIGHUP

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_error() {
    local msg="$1"
    # Escape special characters for JSON
    msg=$(echo "$msg" | tr '\n' ' ' | sed 's/"/\\"/g' | head -c 200)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $msg" >> "$ERROR_LOG"
    log "ERROR: $msg"
}

run_check() {
    local name="$1"
    local script="$2"
    local exit_code

    # Check if script exists
    if [ ! -f "$script" ]; then
        echo '{"status":"FAIL","reason":"script_not_found"}'
        return
    fi

    # Run with timeout and capture ALL output
    if timeout 30 bash "$script" >/dev/null 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ]; then
        echo '{"status":"PASS","reason":"ok"}'
    else
        log_error "$name failed (exit $exit_code)"
        echo '{"status":"FAIL","reason":"exit_nonzero","exit_code":'"$exit_code"'}'
    fi
}

write_status() {
    local overall="$1"
    local hooks="$2"
    local settings="$3"
    local pm2="$4"
    local redis="$5"
    local scripts="$6"
    local credentials="$7"

    cat > "$STATUS_FILE" << EOFSTATUS
{
  "timestamp": "$(date -Iseconds)",
  "status": "$overall",
  "checks": {
    "hooks_syntax": $hooks,
    "settings_json": $settings,
    "pm2_services": $pm2,
    "redis": $redis,
    "scripts_syntax": $scripts,
    "credentials": $credentials
  },
  "uptime_hours": $(awk '{printf "%.2f", $1/3600}' /proc/uptime),
  "validator_pid": $$
}
EOFSTATUS
}

main_loop() {
    while true; do
        log "Starting validation cycle..."

        # Initialize status
        local hooks_status settings_status pm2_status redis_status scripts_status credentials_status
        local overall_status="PASS"

        # Run all checks (catch ALL errors with || true)
        hooks_status=$(run_check "hooks_syntax" "$PROFILE_DIR/scripts/validate-hooks-syntax.sh") || hooks_status='{"status":"ERROR","errors":["check crashed"]}'
        settings_status=$(run_check "settings_json" "$PROFILE_DIR/scripts/validate-settings-json.sh") || settings_status='{"status":"ERROR","errors":["check crashed"]}'
        pm2_status=$(run_check "pm2_services" "$PROFILE_DIR/scripts/validate-pm2-health.sh") || pm2_status='{"status":"ERROR","errors":["check crashed"]}'
        redis_status=$(run_check "redis" "$PROFILE_DIR/scripts/validate-redis-health.sh") || redis_status='{"status":"ERROR","errors":["check crashed"]}'
        scripts_status=$(run_check "scripts_syntax" "$PROFILE_DIR/scripts/validate-scripts-syntax.sh") || scripts_status='{"status":"ERROR","errors":["check crashed"]}'
        credentials_status=$(timeout 45 python3 "$PROFILE_DIR/auth-health.py" 2>/dev/null) || true
        python3 -c 'import json,sys; json.loads(sys.argv[1])' "$credentials_status" 2>/dev/null || credentials_status='{"google_credentials":{"status":"FAIL","reason":"check_error"},"assemblyai_credentials":{"status":"FAIL","reason":"check_error"}}'

        # Determine overall status
        [[ "$hooks_status" == *'"status":"FAIL"'* ]] && overall_status="FAIL"
        [[ "$settings_status" == *'"status":"FAIL"'* ]] && overall_status="FAIL"
        [[ "$pm2_status" == *'"status":"FAIL"'* ]] && overall_status="FAIL"
        [[ "$redis_status" == *'"status":"FAIL"'* ]] && overall_status="FAIL"
        [[ "$scripts_status" == *'"status":"FAIL"'* ]] && overall_status="FAIL"
        [[ "$credentials_status" == *'"status": "FAIL"'* || "$credentials_status" == *'"status":"FAIL"'* ]] && overall_status="FAIL"

        # Write status file (ALWAYS succeeds)
        write_status "$overall_status" "$hooks_status" "$settings_status" "$pm2_status" "$redis_status" "$scripts_status" "$credentials_status"

        log "Validation cycle complete: $overall_status"

        [ "${1:-}" = "--once" ] && return

        # Sleep (with trap handling)
        sleep $INTERVAL || true
    done
}

if [ "${SCHED_VALIDATOR_SOURCE_ONLY:-0}" != "1" ]; then
    log "=== sched-validator starting (PID: $$) ==="
    if [ "${1:-}" = "--once" ]; then
        main_loop --once
    else
        while true; do
            main_loop || {
                log_error "Main loop crashed! Restarting in 10s..."
                sleep 10
            }
        done
    fi
fi
