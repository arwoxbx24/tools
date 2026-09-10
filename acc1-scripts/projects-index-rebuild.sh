#!/usr/bin/env bash
set +e
# projects-index-rebuild.sh - Scan /root/claude-projects/ and build projects index
# AUTO-GENERATED - DO NOT EDIT
# Source: scripts/projects-index-rebuild.sh

PROJECTS_DIR="/root/claude-projects"
OUTPUT_FILE="${PROJECTS_DIR}/PROJECTS-INDEX.md"
TEMP_FILE="/tmp/projects-index-$$.md"

# Skip these directories
SKIP_DIRS=("node_modules" ".tmp" ".git" "plans" "archive" "tests" "skills" "web-share")

log() {
    echo "[projects-index-rebuild] $*" >&2
}

# Check if directory should be skipped
should_skip() {
    local dir_name="$1"
    for skip in "${SKIP_DIRS[@]}"; do
        if [[ "$dir_name" == "$skip" ]]; then
            return 0
        fi
    done
    return 1
}

# Extract field from YAML-like file (simple grep-based, not full parser)
extract_field() {
    local file="$1"
    local field="$2"
    grep "^${field}:" "$file" 2>/dev/null | head -1 | cut -d: -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '"' | tr -d "'"
}

# Count plan files in project
count_plans() {
    local project_dir="$1"
    local plans_dir="${project_dir}/plans"
    if [[ -d "$plans_dir" ]]; then
        find "$plans_dir" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l
    else
        echo "0"
    fi
}

# Main scan function
scan_projects() {
    local project_count=0
    local metadata_count=0

    # Start building output
    {
        echo "# Projects Index"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "| Project | Status | Type | Created | Plans | Description |"
        echo "|---------|--------|------|---------|-------|-------------|"
    } > "$TEMP_FILE"

    # Scan all directories in /root/claude-projects/
    for project_path in "${PROJECTS_DIR}"/*; do
        # Skip if not a directory
        [[ ! -d "$project_path" ]] && continue

        local project_name=$(basename "$project_path")

        # Skip excluded directories
        should_skip "$project_name" && continue

        local project_yaml="${project_path}/project.yaml"
        local claude_md="${project_path}/CLAUDE.md"

        local status="-"
        local type="unknown"
        local created="-"
        local description="-"
        local plans_count=0

        # Count plans
        plans_count=$(count_plans "$project_path")

        # Check if project.yaml exists
        if [[ -f "$project_yaml" ]]; then
            # Parse metadata from project.yaml
            status=$(extract_field "$project_yaml" "status")
            type=$(extract_field "$project_yaml" "type")
            created=$(extract_field "$project_yaml" "created")
            description=$(extract_field "$project_yaml" "description")

            # Defaults if empty
            [[ -z "$status" ]] && status="-"
            [[ -z "$type" ]] && type="unknown"
            [[ -z "$created" ]] && created="-"
            [[ -z "$description" ]] && description="-"

            ((metadata_count++))
        elif [[ -f "$claude_md" ]]; then
            # Legacy project with only CLAUDE.md
            type="unknown"
            description="(no project.yaml)"
        else
            # No metadata files, skip
            continue
        fi

        # Truncate long descriptions
        if [[ ${#description} -gt 60 ]]; then
            description="${description:0:57}..."
        fi

        # Add row to table
        echo "| $project_name | $status | $type | $created | $plans_count | $description |" >> "$TEMP_FILE"

        ((project_count++))
    done

    # Move temp file to final location (atomic write)
    mv "$TEMP_FILE" "$OUTPUT_FILE"

    # Print summary
    log "Found $project_count projects ($metadata_count with metadata)"
    log "Index written to: $OUTPUT_FILE"

    # Also output to stdout
    cat "$OUTPUT_FILE"
}

# Run scan
scan_projects

exit 0

# INTEGRITY
# PARENT: null
# DOCUMENT: projects-index-rebuild.sh
# VERSION: 20260215-173000
# GENERATED: 2026-02-15
