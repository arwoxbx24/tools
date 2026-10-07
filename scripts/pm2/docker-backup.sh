#!/usr/bin/env bash
set +e
set -o pipefail

# Docker Backup Script
# Stages consistent database dumps; server-backup restic captures Docker files directly.
# FMEA-driven design with comprehensive error handling

BACKUP_ROOT="/root/backups/docker"
LOG_FILE="/root/workspaces/system/tools/scripts/logs/docker-backup.log"
ALERT_FILE="/root/workspaces/system/tools/scripts/data/backup-alert.txt"
MIN_FREE_SPACE_GB=1

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error tracking
ERRORS=0
WARNINGS=0

log "====== Docker Backup Started ======"

# FMEA Mitigation: Check disk space before starting (RPN 216)
AVAILABLE_GB=$(df -BG "$BACKUP_ROOT" 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//')
if [ -z "$AVAILABLE_GB" ]; then
    # Backup directory doesn't exist, create it
    mkdir -p "$BACKUP_ROOT"
    AVAILABLE_GB=$(df -BG "$BACKUP_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
fi

if [ "$AVAILABLE_GB" -lt "$MIN_FREE_SPACE_GB" ]; then
    log "ERROR: Insufficient disk space. Available: ${AVAILABLE_GB}GB, Required: ${MIN_FREE_SPACE_GB}GB"
    echo "CRITICAL: Disk space too low for backup (${AVAILABLE_GB}GB available)" > "$ALERT_FILE"
    exit 2
fi

log "Disk space check passed: ${AVAILABLE_GB}GB available"

# FMEA Mitigation: Verify running as root (RPN 48)
if [ "$EUID" -ne 0 ]; then
    log "ERROR: Script must run as root for volume access"
    echo "CRITICAL: Backup script not running as root" > "$ALERT_FILE"
    exit 2
fi

# Never rotate local archives before their offsite copy and restore are proved.
exec 8>"$BACKUP_ROOT/.docker-backup.lock" || exit 2
flock -n 8 || { log "ERROR: Docker staging already running"; exit 1; }
BACKUP_DIR="$BACKUP_ROOT/current"
[ ! -L "$BACKUP_DIR" ] || { log "ERROR: DB stage is a symlink"; exit 2; }
mkdir -p "$BACKUP_DIR" || exit 2
log "Backup directory: $BACKUP_DIR"

# Function: Check if container is running
# FMEA Mitigation: Detect stopped containers (RPN 60)
is_container_running() {
    local container=$1
    docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null | grep -q true
    return $?
}

# Function: Get environment variable from container
get_container_env() {
    local container=$1
    local var_name=$2
    docker exec "$container" env 2>/dev/null | grep "^${var_name}=" | cut -d= -f2-
}

publish_dump() { # temporary archive, stable archive
    local temp_file=$1 output_file=$2 size
    [ -f "$temp_file" ] && [ ! -L "$temp_file" ] || return 1
    size=$(stat -c%s -- "$temp_file") || return 1
    [ "$size" -gt 100 ] && gzip -t -- "$temp_file" 2>>"$LOG_FILE" \
        && mv -f -- "$temp_file" "$output_file"
}

# Function: Backup PostgreSQL database
backup_postgres() {
    local container=$1
    local db_name=$2
    local db_user=$3
    local db_password=$4
    local output_file="$BACKUP_DIR/${container}_${db_name}.sql.gz"
    local temp_file="$BACKUP_ROOT/.${output_file##*/}.tmp.$$"

    log "Backing up PostgreSQL: $container/$db_name"

    if ! is_container_running "$container"; then
        log "WARNING: Container $container is not running, skipping"
        ((WARNINGS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    timeout -k 30s 300s docker exec "$container" sh -c "PGPASSWORD='$db_password' pg_dump -U $db_user $db_name" 2>>"$LOG_FILE" | gzip > "$temp_file"

    local result=$?
    if [ $result -eq 0 ] && publish_dump "$temp_file" "$output_file"; then
        local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
        log "SUCCESS: PostgreSQL backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
        return 0
    fi
    rm -f -- "$temp_file"
    if [ $result -eq 124 ]; then
        log "ERROR: PostgreSQL backup timed out after 300s"
        ((ERRORS++))
        return 1
    else
        log "ERROR: PostgreSQL backup failed for $container/$db_name (exit code: $result)"
        ((ERRORS++))
        return 1
    fi
}

# Function: Backup MySQL database
backup_mysql() {
    local container=$1
    local db_name=$2
    local db_user=$3
    local db_password=$4
    local output_file="$BACKUP_DIR/${container}_${db_name}.sql.gz"
    local temp_file="$BACKUP_ROOT/.${output_file##*/}.tmp.$$"

    log "Backing up MySQL: $container/$db_name"

    if ! is_container_running "$container"; then
        log "WARNING: Container $container is not running, skipping"
        ((WARNINGS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    timeout -k 30s 300s docker exec "$container" sh -c "command -v mariadb-dump >/dev/null && exec mariadb-dump -u $db_user -p'$db_password' $db_name || exec mysqldump -u $db_user -p'$db_password' $db_name" 2>>"$LOG_FILE" | gzip > "$temp_file"

    local result=$?
    if [ $result -eq 0 ] && publish_dump "$temp_file" "$output_file"; then
        local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
        log "SUCCESS: MySQL backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
        return 0
    fi
    rm -f -- "$temp_file"
    if [ $result -eq 124 ]; then
        log "ERROR: MySQL backup timed out after 300s"
        ((ERRORS++))
        return 1
    else
        log "ERROR: MySQL backup failed for $container/$db_name (exit code: $result)"
        ((ERRORS++))
        return 1
    fi
}

# Function: Backup MongoDB database
backup_mongo() {
    local container=$1
    local output_file="$BACKUP_DIR/${container}.archive.gz"
    local temp_file="$BACKUP_ROOT/.${output_file##*/}.tmp.$$"
    local db_user=$(get_container_env "$container" "MONGO_INITDB_ROOT_USERNAME")
    local db_password=$(get_container_env "$container" "MONGO_INITDB_ROOT_PASSWORD")

    log "Backing up MongoDB: $container"

    if ! is_container_running "$container"; then
        log "WARNING: Container $container is not running, skipping"
        ((WARNINGS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    if [ -n "$db_user" ] && [ -n "$db_password" ]; then
        timeout -k 30s 300s docker exec "$container" mongodump --archive --gzip -u "$db_user" -p "$db_password" --authenticationDatabase admin > "$temp_file" 2>>"$LOG_FILE"
    else
        timeout -k 30s 300s docker exec "$container" mongodump --archive --gzip > "$temp_file" 2>>"$LOG_FILE"
    fi

    local result=$?
    if [ $result -eq 0 ] && publish_dump "$temp_file" "$output_file"; then
        local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
        log "SUCCESS: MongoDB backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
        return 0
    fi
    rm -f -- "$temp_file"
    if [ $result -eq 124 ]; then
        log "ERROR: MongoDB backup timed out after 300s"
        ((ERRORS++))
        return 1
    else
        log "ERROR: MongoDB backup failed for $container (exit code: $result)"
        ((ERRORS++))
        return 1
    fi
}

# ========== BACKUP EXECUTION ==========

# PostgreSQL Databases
log "--- Starting PostgreSQL backups ---"

# Auto-detect kutt postgres credentials
if is_container_running "kutt-postgres-1"; then
    KUTT_DB=$(get_container_env "kutt-postgres-1" "POSTGRES_DB")
    KUTT_USER=$(get_container_env "kutt-postgres-1" "POSTGRES_USER")
    KUTT_PASSWORD=$(get_container_env "kutt-postgres-1" "POSTGRES_PASSWORD")

    if [ -n "$KUTT_DB" ] && [ -n "$KUTT_USER" ] && [ -n "$KUTT_PASSWORD" ]; then
        backup_postgres "kutt-postgres-1" "$KUTT_DB" "$KUTT_USER" "$KUTT_PASSWORD"
    else
        log "WARNING: Could not auto-detect kutt postgres credentials, skipping"
        ((WARNINGS++))
    fi
fi

# MySQL Database
log "--- Starting MySQL backups ---"
for container in stroy-mysql mariadb_container; do
    if is_container_running "$container"; then
        MYSQL_DB=$(get_container_env "$container" "MYSQL_DATABASE")
        MYSQL_USER=$(get_container_env "$container" "MYSQL_USER")
        MYSQL_PASSWORD=$(get_container_env "$container" "MYSQL_PASSWORD")

        if [ "$container" = "mariadb_container" ]; then
            [ -n "$MYSQL_DB" ] || MYSQL_DB=$(get_container_env "$container" "MARIADB_DATABASE")
            [ -n "$MYSQL_USER" ] || MYSQL_USER=$(get_container_env "$container" "MARIADB_USER")
            [ -n "$MYSQL_PASSWORD" ] || MYSQL_PASSWORD=$(get_container_env "$container" "MARIADB_PASSWORD")
        fi

        # Fallback to root if user not set
        if [ -z "$MYSQL_USER" ]; then
            MYSQL_USER="root"
            MYSQL_PASSWORD=$(get_container_env "$container" "MYSQL_ROOT_PASSWORD")
            if [ "$container" = "mariadb_container" ] && [ -z "$MYSQL_PASSWORD" ]; then
                MYSQL_PASSWORD=$(get_container_env "$container" "MARIADB_ROOT_PASSWORD")
            fi
        fi

        if [ -n "$MYSQL_DB" ] && [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ]; then
            backup_mysql "$container" "$MYSQL_DB" "$MYSQL_USER" "$MYSQL_PASSWORD"
        else
            log "WARNING: Could not auto-detect mysql credentials for $container, skipping"
            ((WARNINGS++))
        fi
    fi
done

# MongoDB Database
log "--- Starting MongoDB backups ---"
if is_container_running "komodo-mongo-1"; then
    backup_mongo "komodo-mongo-1"
fi

# ========== FINAL SUMMARY ==========

log "====== Backup Summary ======"
log "Errors: $ERRORS"
log "Warnings: $WARNINGS"
log "Backup directory: $BACKUP_DIR"

# Cleanup alert file if exists and backup was successful
if [ -f "$ALERT_FILE" ] && [ $ERRORS -eq 0 ]; then
    rm -f "$ALERT_FILE"
    log "Cleared previous alert file"
fi

# Determine exit status and create alert if needed
if [ $ERRORS -gt 0 ]; then
    if [ $ERRORS -ge 5 ]; then
        log "CRITICAL: Multiple backup failures detected"
        echo "CRITICAL: Docker backup failed with $ERRORS errors, $WARNINGS warnings" > "$ALERT_FILE"
        exit 2
    else
        log "PARTIAL: Some backups failed"
        echo "WARNING: Docker backup completed with $ERRORS errors, $WARNINGS warnings" > "$ALERT_FILE"
        exit 1
    fi
else
    for archive in "$BACKUP_DIR"/*.gz; do
        [ -e "$archive" ] || continue
        if [ ! -f "$archive" ] || ! gzip -t -- "$archive" 2>>"$LOG_FILE"; then
            log "ERROR: DB dump integrity check failed"
            exit 2
        fi
    done
    log "DB stage ready: $BACKUP_DIR"
    log "SUCCESS: Database dumps completed successfully"
    exit 0
fi
