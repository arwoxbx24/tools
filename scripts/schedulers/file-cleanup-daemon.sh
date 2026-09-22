#!/bin/bash
# PM2 Scheduler: File Cleanup Daemon
# Tightened 2026-02-24: interval-based (every 4h), 1-day retention, 2M threshold, 300 lines keep
# Sections: JSONL compress/delete, logs, diagnostics, PM2 logs, history.jsonl, emergency size cap
set +e

INTERVAL=14400  # 4 hours in seconds
LOG_FILE="/root/workspaces/system/tools/scripts/logs/file-cleanup.log"
CLAUDE_DIR="/root/workspaces/system/tools/scripts"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date -Iseconds)] File cleanup daemon started (interval=${INTERVAL}s)" | tee -a "$LOG_FILE"

while true; do
    echo "[$(date -Iseconds)] Starting file cleanup" | tee -a "$LOG_FILE"

    # Track statistics
    compressed_count=0
    deleted_count=0
    space_freed=0

    # 1. JSONL files in projects directory (recursive — includes subagent dirs)
    PROJECTS_DIR="/root/workspaces/system/tools/scripts/projects"

    if [ -d "$PROJECTS_DIR" ]; then
        # Get the newest .jsonl file per top-level project dir (current active sessions)
        declare -A newest_jsonls
        while IFS= read -r projdir; do
            nj=$(find "$projdir" -maxdepth 1 -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
            [ -n "$nj" ] && newest_jsonls["$nj"]=1
        done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)

        # Compress JSONL files older than 6 hours (skip newest active sessions)
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ] && [ -z "${newest_jsonls[$file]}" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                gzip "$file" 2>/dev/null && {
                    compressed_count=$((compressed_count + 1))
                    space_freed=$((space_freed + size))
                    echo "[$(date -Iseconds)] Compressed: $file" | tee -a "$LOG_FILE"
                }
            fi
        done < <(find "$PROJECTS_DIR" -name "*.jsonl" -type f -mmin +360 2>/dev/null)

        # Delete JSONL and .jsonl.gz files older than 1 day
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                rm "$file" 2>/dev/null && {
                    deleted_count=$((deleted_count + 1))
                    space_freed=$((space_freed + size))
                    echo "[$(date -Iseconds)] Deleted: $file" | tee -a "$LOG_FILE"
                }
            fi
        done < <(find "$PROJECTS_DIR" \( -name "*.jsonl" -o -name "*.jsonl.gz" \) -type f -mtime +1 2>/dev/null)

        # Clean empty subagent directories
        find "$PROJECTS_DIR" -mindepth 2 -type d -name "subagents" -empty -delete 2>/dev/null
        find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -type d -empty -delete 2>/dev/null

        unset newest_jsonls
    fi

    # 2. Context JSON files (skip latest.json, delete >1 day)
    CONTEXT_DIR="/root/workspaces/system/tools/scripts/context"

    if [ -d "$CONTEXT_DIR" ]; then
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                bn=$(basename "$file")
                if [ "$bn" != "latest.json" ]; then
                    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                    rm "$file" 2>/dev/null && {
                        deleted_count=$((deleted_count + 1))
                        space_freed=$((space_freed + size))
                        echo "[$(date -Iseconds)] Deleted: $file" | tee -a "$LOG_FILE"
                    }
                fi
            fi
        done < <(find "$CONTEXT_DIR" -maxdepth 1 -name "*.json" -type f -mtime +1 2>/dev/null)
    fi

    # 3. Log files — unified: truncate >2M to 300 lines
    LOGS_DIR="/root/workspaces/system/tools/scripts/logs"
    truncated_count=0

    if [ -d "$LOGS_DIR" ]; then
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                temp_file="${file}.tmp"
                tail -300 "$file" > "$temp_file" 2>/dev/null && {
                    mv "$temp_file" "$file" 2>/dev/null
                    new_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                    space_freed=$((space_freed + size - new_size))
                    truncated_count=$((truncated_count + 1))
                    echo "[$(date -Iseconds)] Truncated: $file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size}B) -> $(numfmt --to=iec-i --suffix=B $new_size 2>/dev/null || echo ${new_size}B))" | tee -a "$LOG_FILE"
                } || rm -f "$temp_file" 2>/dev/null
            fi
        done < <(find "$LOGS_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.txt" \) -size +2M 2>/dev/null)
    fi

    # 4. Agent reports rotation (3-day retention — counts preserved in Redis DB2)
    REPORTS_DIR="/root/workspaces/system/tools/scripts/agent-reports"

    if [ -d "$REPORTS_DIR" ]; then
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                rm "$file" 2>/dev/null && {
                    deleted_count=$((deleted_count + 1))
                    space_freed=$((space_freed + size))
                    echo "[$(date -Iseconds)] Deleted report: $file" | tee -a "$LOG_FILE"
                }
            fi
        done < <(find "$REPORTS_DIR" -name "*.md" -type f -mtime +3 2>/dev/null)
    fi

    # 5. Diagnostics logs — delete after 1 day (was 3 days)
    DIAG_DIR="/root/workspaces/system/tools/scripts/logs/diagnostics"

    if [ -d "$DIAG_DIR" ]; then
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                rm "$file" 2>/dev/null && {
                    deleted_count=$((deleted_count + 1))
                    space_freed=$((space_freed + size))
                }
            fi
        done < <(find "$DIAG_DIR" -type f -mtime +1 2>/dev/null)
        echo "[$(date -Iseconds)] Diagnostics cleanup done" | tee -a "$LOG_FILE"
    fi

    # 6. PM2 log rotation — delete rotated logs, truncate >2M to 200 lines
    PM2_LOGS_DIR="/root/.pm2/logs"

    if [ -d "$PM2_LOGS_DIR" ]; then
        # Delete rotated log files (e.g. app-out-2026-02-23_00-00-00.log)
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                rm "$file" 2>/dev/null && {
                    deleted_count=$((deleted_count + 1))
                    space_freed=$((space_freed + size))
                    echo "[$(date -Iseconds)] Deleted PM2 rotated log: $file" | tee -a "$LOG_FILE"
                }
            fi
        done < <(find "$PM2_LOGS_DIR" -type f \( -name "*-out-[0-9]*.log" -o -name "*-error-[0-9]*.log" \) 2>/dev/null)

        # Truncate active PM2 logs >2M to 200 lines
        while IFS= read -r file; do
            if [ -n "$file" ] && [ -f "$file" ]; then
                size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                temp_file="${file}.tmp"
                tail -200 "$file" > "$temp_file" 2>/dev/null && {
                    mv "$temp_file" "$file" 2>/dev/null
                    new_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                    space_freed=$((space_freed + size - new_size))
                    truncated_count=$((truncated_count + 1))
                    echo "[$(date -Iseconds)] Truncated PM2 log: $file ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size}B) -> $(numfmt --to=iec-i --suffix=B $new_size 2>/dev/null || echo ${new_size}B))" | tee -a "$LOG_FILE"
                } || rm -f "$temp_file" 2>/dev/null
            fi
        done < <(find "$PM2_LOGS_DIR" -maxdepth 1 -type f \( -name "*-out.log" -o -name "*-error.log" \) -size +2M 2>/dev/null)
    fi

    # 7. history.jsonl — truncate to 1000 lines if >5M
    HISTORY_FILE="/root/.claude/history.jsonl"

    if [ -f "$HISTORY_FILE" ]; then
        hist_size=$(stat -c%s "$HISTORY_FILE" 2>/dev/null || echo 0)
        if [ "$hist_size" -gt 5242880 ]; then
            temp_file="${HISTORY_FILE}.tmp"
            tail -1000 "$HISTORY_FILE" > "$temp_file" 2>/dev/null && {
                mv "$temp_file" "$HISTORY_FILE" 2>/dev/null
                new_size=$(stat -c%s "$HISTORY_FILE" 2>/dev/null || echo 0)
                space_freed=$((space_freed + hist_size - new_size))
                truncated_count=$((truncated_count + 1))
                echo "[$(date -Iseconds)] Truncated history.jsonl ($(numfmt --to=iec-i --suffix=B $hist_size 2>/dev/null || echo ${hist_size}B) -> $(numfmt --to=iec-i --suffix=B $new_size 2>/dev/null || echo ${new_size}B))" | tee -a "$LOG_FILE"
            } || rm -f "$temp_file" 2>/dev/null
        fi
    fi

    # 8. Emergency size cap: if /root/workspaces/tools/acc1-scripts/ > 800MB
    total_mb=$(du -sm "$CLAUDE_DIR" --exclude="$CLAUDE_DIR/mcp-servers" --exclude="$CLAUDE_DIR/data/vectors.db" 2>/dev/null | cut -f1 || echo 0)

    if [ "$total_mb" -gt 800 ]; then
        echo "[$(date -Iseconds)] EMERGENCY: ${total_mb}MB > 800MB cap. Aggressive cleanup starting." | tee -a "$LOG_FILE"

        # Delete all .jsonl older than 6 hours (not just 1 day)
        find "$PROJECTS_DIR" -name "*.jsonl" -type f -mmin +360 -delete 2>/dev/null
        # Delete all compressed session files
        find "$PROJECTS_DIR" -name "*.jsonl.gz" -type f -delete 2>/dev/null
        # Delete all diagnostics
        [ -d "$DIAG_DIR" ] && find "$DIAG_DIR" -type f -delete 2>/dev/null
        # Delete old tool-results (>7 days)
        find "$PROJECTS_DIR" -path "*/tool-results/*" -type f -mtime +7 -delete 2>/dev/null
        # Truncate all logs to 100 lines
        find "$LOGS_DIR" -maxdepth 1 -type f \( -name "*.log" -o -name "*.txt" \) | while IFS= read -r file; do
            [ -f "$file" ] || continue
            temp_file="${file}.tmp"
            tail -100 "$file" > "$temp_file" 2>/dev/null && mv "$temp_file" "$file" 2>/dev/null || rm -f "$temp_file" 2>/dev/null
        done

        new_mb=$(du -sm "$CLAUDE_DIR" --exclude="$CLAUDE_DIR/mcp-servers" --exclude="$CLAUDE_DIR/data/vectors.db" 2>/dev/null | cut -f1 || echo 0)
        echo "[$(date -Iseconds)] EMERGENCY cleanup done: ${total_mb}MB -> ${new_mb}MB" | tee -a "$LOG_FILE"
    fi

    # 9. tmux TTL — handled by MinIO ILM rule (prefix: tmux-copy-, expiry: 1 day)
    # No manual queue processing needed. /tmp/tmux-ttl-queue/ is obsolete.
    ttl_deleted=0

    # Summary
    space_freed_human=$(numfmt --to=iec-i --suffix=B $space_freed 2>/dev/null || echo "${space_freed} bytes")
    echo "[$(date -Iseconds)] Cleanup complete: compressed=$compressed_count, deleted=$deleted_count, truncated=$truncated_count, ttl_minio=$ttl_deleted, space_freed=$space_freed_human" | tee -a "$LOG_FILE"

    sleep $INTERVAL
done
