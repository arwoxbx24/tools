#!/usr/bin/env bash
set +e
set -o pipefail

# Docker Backup Script
# Backs up all PostgreSQL, MySQL databases and Docker volumes/bind mounts
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
# Publish a complete directory only; interrupted dumps stay hidden.
FINAL_BACKUP_DIR="$BACKUP_ROOT/$(date '+%Y-%m-%d_%H%M%S')"
if [ -e "$FINAL_BACKUP_DIR" ] || [ -L "$FINAL_BACKUP_DIR" ]; then
    log "ERROR: Snapshot destination already exists"
    exit 2
fi
BACKUP_DIR=$(mktemp -d "$BACKUP_ROOT/.incomplete-XXXXXX") || exit 2
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

# Function: Backup PostgreSQL database
backup_postgres() {
    local container=$1
    local db_name=$2
    local db_user=$3
    local db_password=$4
    local output_file="$BACKUP_DIR/${container}_${db_name}.sql.gz"

    log "Backing up PostgreSQL: $container/$db_name"

    if ! is_container_running "$container"; then
        log "WARNING: Container $container is not running, skipping"
        ((WARNINGS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    timeout -k 30s 300s docker exec "$container" sh -c "PGPASSWORD='$db_password' pg_dump -U $db_user $db_name" 2>>"$LOG_FILE" | gzip > "$output_file"

    local result=$?
    if [ $result -eq 0 ] && [ -f "$output_file" ]; then
        local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
        # FMEA Mitigation: Verify backup not empty (RPN 80)
        if [ "$size" -gt 100 ]; then
            log "SUCCESS: PostgreSQL backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
            return 0
        else
            log "ERROR: PostgreSQL backup file too small ($size bytes), likely corrupted"
            ((ERRORS++))
            return 1
        fi
    elif [ $result -eq 124 ]; then
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

    log "Backing up MySQL: $container/$db_name"

    if ! is_container_running "$container"; then
        log "WARNING: Container $container is not running, skipping"
        ((WARNINGS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    timeout -k 30s 300s docker exec "$container" sh -c "command -v mariadb-dump >/dev/null && exec mariadb-dump -u $db_user -p'$db_password' $db_name || exec mysqldump -u $db_user -p'$db_password' $db_name" 2>>"$LOG_FILE" | gzip > "$output_file"

    local result=$?
    if [ $result -eq 0 ] && [ -f "$output_file" ]; then
        local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
        # FMEA Mitigation: Verify backup not empty (RPN 80)
        if [ "$size" -gt 100 ]; then
            log "SUCCESS: MySQL backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
            return 0
        else
            log "ERROR: MySQL backup file too small ($size bytes), likely corrupted"
            ((ERRORS++))
            return 1
        fi
    elif [ $result -eq 124 ]; then
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
        timeout -k 30s 300s docker exec "$container" mongodump --archive --gzip -u "$db_user" -p "$db_password" --authenticationDatabase admin > "$output_file" 2>>"$LOG_FILE"
    else
        timeout -k 30s 300s docker exec "$container" mongodump --archive --gzip > "$output_file" 2>>"$LOG_FILE"
    fi

    local result=$?
    if [ $result -eq 0 ] && [ -f "$output_file" ]; then
        local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
        # FMEA Mitigation: Verify backup not empty (RPN 80)
        if [ "$size" -gt 100 ]; then
            log "SUCCESS: MongoDB backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
            return 0
        else
            log "ERROR: MongoDB backup file too small ($size bytes), likely corrupted"
            ((ERRORS++))
            return 1
        fi
    elif [ $result -eq 124 ]; then
        log "ERROR: MongoDB backup timed out after 300s"
        ((ERRORS++))
        return 1
    else
        log "ERROR: MongoDB backup failed for $container (exit code: $result)"
        ((ERRORS++))
        return 1
    fi
}

# Function: Backup Docker volume
backup_volume() {
    local volume_name=$1
    local volume_path="/var/lib/docker/volumes/${volume_name}/_data"
    local output_file="$BACKUP_DIR/${volume_name}.tar.gz"

    log "Backing up volume: $volume_name"

    if [ ! -d "$volume_path" ]; then
        log "ERROR: Volume path does not exist: $volume_path"
        ((ERRORS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    timeout -k 30s 300s tar -czf "$output_file" -C "$volume_path" . 2>>"$LOG_FILE"

    local result=$?
    # tar exit code 1 = some files differ (changed during read, common for active services)
    # tar exit code 2 is fatal: never publish it as a successful archive.
    if [ $result -eq 0 ] || [ $result -eq 1 ]; then
        if [ -f "$output_file" ]; then
            local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
            # FMEA Mitigation: Verify backup not empty (RPN 80)
            if [ "$size" -gt 20 ]; then
                if [ $result -ne 0 ]; then
                    log "SUCCESS: Volume backup completed with warnings: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes)) - files changed during backup (tar exit $result)"
                    ((WARNINGS++))
                else
                    log "SUCCESS: Volume backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
                fi
                return 0
            else
                log "ERROR: Volume backup file too small ($size bytes), likely corrupted"
                ((ERRORS++))
                return 1
            fi
        fi
    elif [ $result -eq 124 ]; then
        log "ERROR: Volume backup timed out after 300s"
        ((ERRORS++))
        return 1
    else
        log "ERROR: Volume backup failed for $volume_name (exit code: $result)"
        ((ERRORS++))
        return 1
    fi
}

# Function: Backup bind mount directory
backup_bindmount() {
    local mount_path=$1
    local mount_name=$(basename "$mount_path")
    local output_file="$BACKUP_DIR/bindmount_${mount_name}.tar.gz"

    log "Backing up bind mount: $mount_path"

    if [ ! -d "$mount_path" ]; then
        log "WARNING: Bind mount path does not exist: $mount_path, skipping"
        ((WARNINGS++))
        return 1
    fi

    # FMEA Mitigation: Timeout to prevent hangs (RPN 98)
    timeout -k 30s 300s tar -czf "$output_file" -C "$(dirname "$mount_path")" "$(basename "$mount_path")" 2>>"$LOG_FILE"

    local result=$?
    # tar exit code 1 = some files differ (changed during read, common for active services)
    # tar exit code 2 is fatal: never publish it as a successful archive.
    if [ $result -eq 0 ] || [ $result -eq 1 ]; then
        if [ -f "$output_file" ]; then
            local size=$(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null)
            # FMEA Mitigation: Verify backup not empty (RPN 80)
            if [ "$size" -gt 20 ]; then
                if [ $result -ne 0 ]; then
                    log "SUCCESS: Bind mount backup completed with warnings: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes)) - files changed during backup (tar exit $result)"
                    ((WARNINGS++))
                else
                    log "SUCCESS: Bind mount backup completed: $output_file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
                fi
                return 0
            else
                log "ERROR: Bind mount backup file too small ($size bytes), likely corrupted"
                ((ERRORS++))
                return 1
            fi
        fi
    elif [ $result -eq 124 ]; then
        log "ERROR: Bind mount backup timed out after 300s"
        ((ERRORS++))
        return 1
    else
        log "ERROR: Bind mount backup failed for $mount_path (exit code: $result)"
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

# Docker Volumes
log "--- Starting Docker volume backups ---"
VOLUMES=$(docker volume ls -q)
if [ "$?" -ne 0 ]; then
    log "ERROR: Cannot enumerate Docker volumes"
    ((ERRORS++))
fi
for v in $VOLUMES; do
    if [[ "$v" == *_cache ]]; then
        log "Skipping cache volume: $v"
    else
        backup_volume "$v"
    fi
done

# Bind Mounts
log "--- Starting bind mount backups ---"
# /data/minio is directly backed up by server-backup; its S3 restore is proved.
# Keep the nginx fallback until its actual direct-path recovery is proved.
backup_bindmount "/root/nginx-proxy-manager"

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
        if [ ! -f "$archive" ] || ! gzip -t -- "$archive" 2>>"$LOG_FILE"; then
            log "ERROR: Archive integrity check failed; incomplete directory retained"
            exit 2
        fi
    done
    if ! mv -T -n -- "$BACKUP_DIR" "$FINAL_BACKUP_DIR" || [ -d "$BACKUP_DIR" ]; then
        log "ERROR: Snapshot publication failed; incomplete directory retained"
        exit 2
    fi
    BACKUP_DIR="$FINAL_BACKUP_DIR"
    log "Published snapshot: $BACKUP_DIR"
    log "SUCCESS: All backups completed successfully"
    exit 0
fi
