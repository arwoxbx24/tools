#!/bin/bash
# Security Queue Processor
# Reads from Redis queue, scans files with throttling
# Only runs during night hours (00:00-07:00 MSK)
#
# PM2 cron: 0 0-7 * * *

set -o pipefail

# Configuration
REDIS_DB=5
QUEUE_KEY="security:queue"
LOCK_KEY="security:lock"
SCANNED_KEY="security:scanned:$(date +%Y-%m-%d)"
STATS_KEY="security:stats:$(date +%Y-%m-%d)"

BATCH_SIZE=10           # Files per batch
BATCH_PAUSE=30          # Seconds between batches
FILE_PAUSE=2            # Seconds between files
MAX_RUNTIME=3600        # Max 1 hour per run
LOCK_TTL=300            # Lock timeout 5 min

SECURITY_SCANNER="/root/workspaces/tools/acc1-scripts/scripts/security-validate.sh"
LOG_FILE="/root/workspaces/tools/acc1-scripts/pm2/logs/security-queue.log"

log() {
    echo "[$(date -Iseconds)] $1" >> "$LOG_FILE"
}

# Check if night hours (00:00-07:00 MSK)
is_night_hours() {
    local hour=$(date +%H)
    [[ $hour -ge 0 && $hour -lt 7 ]] && return 0
    return 1
}

# Acquire lock
acquire_lock() {
    local result=$(redis-cli -n $REDIS_DB SET "$LOCK_KEY" "$$" NX EX $LOCK_TTL 2>/dev/null)
    [[ "$result" == "OK" ]] && return 0
    return 1
}

# Release lock
release_lock() {
    redis-cli -n $REDIS_DB DEL "$LOCK_KEY" >/dev/null 2>&1
}

# Refresh lock TTL
refresh_lock() {
    redis-cli -n $REDIS_DB EXPIRE "$LOCK_KEY" $LOCK_TTL >/dev/null 2>&1
}

# Get queue size
get_queue_size() {
    redis-cli -n $REDIS_DB LLEN "$QUEUE_KEY" 2>/dev/null || echo "0"
}

# Pop item from queue
pop_queue_item() {
    redis-cli -n $REDIS_DB LPOP "$QUEUE_KEY" 2>/dev/null
}

# Check if file already scanned today
is_already_scanned() {
    local file="$1"
    local result=$(redis-cli -n $REDIS_DB SISMEMBER "$SCANNED_KEY" "$file" 2>/dev/null)
    [[ "$result" == "1" ]] && return 0
    return 1
}

# Mark file as scanned
mark_scanned() {
    local file="$1"
    redis-cli -n $REDIS_DB SADD "$SCANNED_KEY" "$file" >/dev/null 2>&1
    redis-cli -n $REDIS_DB EXPIRE "$SCANNED_KEY" 86400 >/dev/null 2>&1
}

# Scan single file with throttling (V027 compliance)
scan_file() {
    local file="$1"
    local project="$2"

    # Get directory of file for scanning
    local dir=$(dirname "$file")

    # V027: Resource limits mandatory
    nice -n 19 ionice -c 3 timeout 60 \
        "$SECURITY_SCANNER" "$dir" --quick 2>/dev/null

    return $?
}

# Update statistics
update_stats() {
    local key="$1"
    local value="${2:-1}"
    redis-cli -n $REDIS_DB HINCRBY "$STATS_KEY" "$key" "$value" >/dev/null 2>&1
    redis-cli -n $REDIS_DB EXPIRE "$STATS_KEY" 2592000 >/dev/null 2>&1
}

# Process batch of files
process_batch() {
    local count=0
    local issues=0

    while [[ $count -lt $BATCH_SIZE ]]; do
        local item=$(pop_queue_item)
        [[ -z "$item" ]] && break

        # Parse JSON
        local file=$(echo "$item" | sed -n 's/.*"file":"\([^"]*\)".*/\1/p')
        local project=$(echo "$item" | sed -n 's/.*"project":"\([^"]*\)".*/\1/p')

        [[ -z "$file" ]] && continue

        # Skip if already scanned today
        if is_already_scanned "$file"; then
            log "SKIP (already scanned): $file"
            continue
        fi

        # Skip if file no longer exists
        if [[ ! -f "$file" ]]; then
            log "SKIP (deleted): $file"
            continue
        fi

        log "SCAN: $file"

        if ! scan_file "$file" "$project"; then
            ((issues++))
            update_stats "issues_found"
        fi

        mark_scanned "$file"
        ((count++))
        update_stats "files_scanned"

        # Throttle between files
        sleep $FILE_PAUSE

        # Refresh lock
        refresh_lock
    done

    echo $count
}

# Main processing loop
main() {
    log "========== Security Queue Processor Starting =========="

    # Check night hours
    if ! is_night_hours; then
        log "Not night hours (current: $(date +%H):00), exiting"
        exit 0
    fi

    # Check queue
    local queue_size=$(get_queue_size)
    if [[ "$queue_size" -eq 0 ]]; then
        log "Queue empty, nothing to process"
        exit 0
    fi
    log "Queue size: $queue_size files"

    # Acquire lock
    if ! acquire_lock; then
        log "Could not acquire lock, another processor running"
        exit 0
    fi
    trap release_lock EXIT

    local start_time=$(date +%s)
    local total_processed=0

    while true; do
        # Check runtime limit
        local elapsed=$(($(date +%s) - start_time))
        if [[ $elapsed -gt $MAX_RUNTIME ]]; then
            log "Max runtime reached (${MAX_RUNTIME}s), stopping"
            break
        fi

        # Check queue
        queue_size=$(get_queue_size)
        if [[ "$queue_size" -eq 0 ]]; then
            log "Queue exhausted"
            break
        fi

        log "Processing batch ($queue_size remaining)..."
        local batch_count=$(process_batch)

        total_processed=$((total_processed + batch_count))

        if [[ $batch_count -eq 0 ]]; then
            break
        fi

        # Pause between batches
        log "Batch complete ($batch_count files), pausing ${BATCH_PAUSE}s..."
        sleep $BATCH_PAUSE
    done

    local runtime=$(($(date +%s) - start_time))
    log "========== Completed: $total_processed files in ${runtime}s =========="
}

main "$@"
