#!/usr/bin/env bash
# update-progress.sh - Auto-generate/update claude-progress.txt in a project directory
# Usage: update-progress.sh [PROJECT_DIR]
# Called after task completion to keep progress file current.

set -euo pipefail

# Resolve project directory
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_DIR")"
OUTPUT_FILE="$PROJECT_DIR/claude-progress.txt"
NOW="$(date '+%Y-%m-%d %H:%M')"

# Collect DONE section from git log
collect_done() {
    if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$PROJECT_DIR" log --oneline -20 2>/dev/null || echo "(no commits yet)"
    else
        echo "(not a git repository)"
    fi
}

# Collect IN PROGRESS tasks via redis (best-effort)
collect_in_progress() {
    local task_output=""
    if command -v redis-cli >/dev/null 2>&1; then
        task_output="$(redis-cli --scan --pattern "task:*" 2>/dev/null | head -20 | while read -r key; do
            status="$(redis-cli hget "$key" status 2>/dev/null || true)"
            title="$(redis-cli hget "$key" title 2>/dev/null || true)"
            if [[ "$status" == "pending" || "$status" == "in_progress" ]]; then
                echo "  - [$status] ${title:-$key}"
            fi
        done)" || true
    fi
    if [[ -z "$task_output" ]]; then
        echo "  (run TaskList to see active tasks)"
    else
        echo "$task_output"
    fi
}

# Extract ARCHITECTURE DECISIONS from CLAUDE.md
extract_arch_decisions() {
    local claude_md="$PROJECT_DIR/CLAUDE.md"
    if [[ -f "$claude_md" ]]; then
        awk '/^#+[[:space:]]*(Architecture|Stack|Tech|Decisions)/{found=1;next} found && /^#+[[:space:]]/{found=0} found{print "  "$0}' \
            "$claude_md" | head -20
    else
        echo "  (no CLAUDE.md found in project)"
    fi
}

# Preserve a named section from existing file
extract_section() {
    local file="$1"
    local section_start="$2"
    local section_end="$3"
    if [[ ! -f "$file" ]]; then
        return
    fi
    awk -v start="$section_start" -v end="$section_end" \
        '$0 ~ start {found=1;next} found && $0 ~ end {found=0} found {print}' \
        "$file"
}

PRESERVED_ISSUES=""
PRESERVED_ARCH=""

if [[ -f "$OUTPUT_FILE" ]]; then
    PRESERVED_ISSUES="$(extract_section "$OUTPUT_FILE" "^## KNOWN ISSUES" "^## ")"
    PRESERVED_ARCH="$(extract_section "$OUTPUT_FILE" "^## ARCHITECTURE DECISIONS" "^## ")"
fi

if [[ -n "$PRESERVED_ISSUES" ]]; then
    KNOWN_ISSUES_CONTENT="$PRESERVED_ISSUES"
else
    KNOWN_ISSUES_CONTENT="  (none known)"
fi

if [[ -n "$PRESERVED_ARCH" ]]; then
    ARCH_CONTENT="$PRESERVED_ARCH"
else
    ARCH_CONTENT="$(extract_arch_decisions)"
    if [[ -z "$ARCH_CONTENT" ]]; then
        ARCH_CONTENT="  (add key decisions here)"
    fi
fi

# Write the progress file
{
    echo "# Progress: $PROJECT_NAME"
    echo "Last updated: $NOW"
    echo ""
    echo "## DONE"
    collect_done | sed 's/^/  /'
    echo ""
    echo "## IN PROGRESS"
    collect_in_progress
    echo ""
    echo "## NEXT STEPS"
    echo "  (agent: fill in planned next actions here)"
    echo ""
    echo "## KNOWN ISSUES"
    echo "$KNOWN_ISSUES_CONTENT"
    echo ""
    echo "## ARCHITECTURE DECISIONS"
    echo "$ARCH_CONTENT"
} > "$OUTPUT_FILE"

echo "Updated: $OUTPUT_FILE"
