#!/bin/bash
set +e
# Auto-cleanup script for plan files
# Archives/deletes plan files based on lifecycle status
# V234: Never deletes plans younger than 10 minutes (600 seconds)
# Run via cron every 6 hours

PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"
MAX_AGE_HOURS=12
MAX_FILES=10
PROJECTS_DIR="/root/claude-projects"

if [ ! -d "$PLANS_DIR" ]; then
    echo "Plans directory not found: $PLANS_DIR"
    exit 1
fi

# Safe delete function - checks for PROJECT field and mirrors if needed
safe_delete() {
    local filepath="$1"
    local basename=$(basename "$filepath")

    # Read first 20 lines and check for PROJECT field
    local project_name=$(head -20 "$filepath" 2>/dev/null | grep -i -E '^\s*[*#-]*\s*PROJECT\s*:' | sed -E 's/^\s*[*#-]*\s*PROJECT\s*:\s*//i' | tr -d ' ')

    # Check PLAN_META STATUS — NEVER delete in_progress or created
    local plan_status=$(grep -oP 'STATUS:\s*\K\w+' "$filepath" 2>/dev/null | head -1)
    if [ "$plan_status" = "in_progress" ] || [ "$plan_status" = "created" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] PROTECTED: $basename (STATUS=$plan_status, not deleting)" | tee -a /tmp/cleanup-plans.log
        return 0
    fi

    # If no PROJECT field found → system plan → preserve
    if [ -z "$project_name" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] System plan, preserving: $basename" | tee -a /tmp/cleanup-plans.log
        return 0
    fi

    # Check if local copy exists in project directory
    local local_copy="${PROJECTS_DIR}/${project_name}/plans/${basename}"

    if [ -f "$local_copy" ]; then
        # Local copy exists → safe to delete
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Has local copy: $basename (project: $project_name)" | tee -a /tmp/cleanup-plans.log
        rm -v "$filepath" 2>&1 | tee -a /tmp/cleanup-plans.log
    else
        # No local copy → mirror first, then delete
        local local_dir="${PROJECTS_DIR}/${project_name}/plans"
        mkdir -p "$local_dir" 2>/dev/null

        if cp "$filepath" "$local_copy" 2>/dev/null; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Mirrored and cleaned: $basename → $project_name/plans/" | tee -a /tmp/cleanup-plans.log
            rm -v "$filepath" 2>&1 | tee -a /tmp/cleanup-plans.log
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Failed to mirror, preserving: $basename" | tee -a /tmp/cleanup-plans.log
        fi
    fi
}

# Delete files older than 12 hours
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Cleaning plans older than ${MAX_AGE_HOURS} hours..."
while IFS= read -r -d '' file; do
    safe_delete "$file"
done < <(find "$PLANS_DIR" -maxdepth 1 -type f -mmin +720 -print0)

# Keep only the last MAX_FILES by modification time
# V234: Never delete plans younger than 10 minutes (600 seconds)
MIN_AGE_SECONDS=600
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Enforcing max ${MAX_FILES} plans limit..."
ls -t "$PLANS_DIR"/*.md 2>/dev/null | tail -n +$((MAX_FILES + 1)) | while IFS= read -r file; do
    file_age=$(( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null || echo 0) ))
    if [[ "$file_age" -lt "$MIN_AGE_SECONDS" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Skipping fresh plan (<10min): $(basename "$file")" | tee -a /tmp/cleanup-plans.log
        continue
    fi
    safe_delete "$file"
done

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Cleanup complete. Current plans:"
ls -lh "$PLANS_DIR"/*.md 2>/dev/null | wc -l
