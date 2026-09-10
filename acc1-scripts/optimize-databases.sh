#!/bin/bash
# ===========================================
# Database Optimization Script
# Runs periodically via cron to clean and optimize
# ===========================================

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/db-optimize.log"
VECTORS_DB="/root/workspaces/tools/acc1-scripts/data/vectors.db"
RETENTION_DAYS=${1:-3}  # Default: 3 days

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== Starting database optimization ==="

# -----------------------------
# 1. REDIS: Clean expired sessions
# -----------------------------
log "Cleaning Redis..."

# Count before
REDIS_BEFORE=$(redis-cli DBSIZE 2>/dev/null | grep -oE '[0-9]+')

# Redis TTL handles expiration automatically, but we can force cleanup
# of any sessions without TTL that are older than retention period
CUTOFF_DATE=$(date -d "-${RETENTION_DAYS} days" '+%Y-%m-%d')

# Get all session keys and check their age
OLD_SESSIONS=0
for key in $(redis-cli KEYS "session:*" 2>/dev/null); do
    # Extract date from key format: session:YYYY-MM-DD-HHMMSS
    KEY_DATE=$(echo "$key" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    if [[ -n "$KEY_DATE" && "$KEY_DATE" < "$CUTOFF_DATE" ]]; then
        # Check if key has no TTL (TTL = -1)
        TTL=$(redis-cli TTL "$key" 2>/dev/null)
        if [[ "$TTL" == "-1" ]]; then
            redis-cli DEL "$key" >/dev/null 2>&1
            ((OLD_SESSIONS++))
        fi
    fi
done

REDIS_AFTER=$(redis-cli DBSIZE 2>/dev/null | grep -oE '[0-9]+')
log "Redis: $REDIS_BEFORE -> $REDIS_AFTER keys (deleted $OLD_SESSIONS old sessions without TTL)"

# -----------------------------
# 2. VECTORS.DB: Clean garbage and optimize
# -----------------------------
log "Optimizing vectors.db..."

if [[ -f "$VECTORS_DB" ]]; then
    SIZE_BEFORE=$(du -h "$VECTORS_DB" | cut -f1)
    CHUNKS_BEFORE=$(sqlite3 "$VECTORS_DB" "SELECT COUNT(*) FROM code_chunks;" 2>/dev/null)

    # Delete garbage patterns (libraries, build artifacts)
    GARBAGE_PATTERNS=(
        '%/.venv/%'
        '%/venv/%'
        '%/node_modules/%'
        '%/__pycache__/%'
        '%/.git/%'
        '%/dist/%'
        '%/build/%'
        '%/vendor/%'
        '%.min.js'
        '%/site-packages/%'
    )

    DELETED=0
    for pattern in "${GARBAGE_PATTERNS[@]}"; do
        COUNT=$(sqlite3 "$VECTORS_DB" "SELECT COUNT(*) FROM code_chunks WHERE file_path LIKE '$pattern';" 2>/dev/null)
        if [[ "$COUNT" -gt 0 ]]; then
            sqlite3 "$VECTORS_DB" "DELETE FROM code_chunks WHERE file_path LIKE '$pattern';" 2>/dev/null
            DELETED=$((DELETED + COUNT))
            log "  Deleted $COUNT chunks matching: $pattern"
        fi
    done

    # Delete chunks for files that no longer exist
    log "Checking for orphaned chunks (deleted files)..."
    ORPHANED=0
    while IFS= read -r filepath; do
        if [[ ! -f "$filepath" ]]; then
            sqlite3 "$VECTORS_DB" "DELETE FROM code_chunks WHERE file_path = '$filepath';" 2>/dev/null
            ((ORPHANED++))
        fi
    done < <(sqlite3 "$VECTORS_DB" "SELECT DISTINCT file_path FROM code_chunks LIMIT 1000;" 2>/dev/null)

    if [[ "$ORPHANED" -gt 0 ]]; then
        log "  Deleted chunks for $ORPHANED non-existent files"
    fi

    # Vacuum to reclaim space
    log "Running VACUUM..."
    sqlite3 "$VECTORS_DB" "VACUUM;" 2>/dev/null

    SIZE_AFTER=$(du -h "$VECTORS_DB" | cut -f1)
    CHUNKS_AFTER=$(sqlite3 "$VECTORS_DB" "SELECT COUNT(*) FROM code_chunks;" 2>/dev/null)

    log "Vectors.db: $SIZE_BEFORE -> $SIZE_AFTER, chunks: $CHUNKS_BEFORE -> $CHUNKS_AFTER"
else
    log "Vectors.db not found at $VECTORS_DB"
fi

# -----------------------------
# 3. Clean old log files
# -----------------------------
log "Cleaning old logs..."
find /root/workspaces/tools/acc1-scripts/logs -name "*.log" -mtime +7 -delete 2>/dev/null
find /tmp/claude* -mtime +3 -delete 2>/dev/null

# -----------------------------
# 4. Summary
# -----------------------------
REDIS_MEM=$(redis-cli INFO memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
log "=== Optimization complete ==="
log "Redis memory: $REDIS_MEM"
log "Vectors.db: $(du -h "$VECTORS_DB" 2>/dev/null | cut -f1)"
