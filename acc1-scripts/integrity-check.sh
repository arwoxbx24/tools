#!/bin/bash
# PAUTINA Web Integrity System - Full Validation Script
# Scans .md files, validates INTEGRITY metadata, builds dependency graph
# Exit codes: 0=pass, 1=violations found

# Note: set -e removed to avoid issues with arithmetic evaluation returning non-zero
# when incrementing from 0

# Configuration
# Handle case where HOME might be empty
if [[ -z "$HOME" ]]; then
    HOME="/root"
fi
PROFILE_DIR="/root/workspaces/tools/acc1-scripts"
REFERENCE_DIR="${PROFILE_DIR}/reference"
OPERATIONS_DIR="${PROFILE_DIR}/operations"
ROOT_FILE="CLAUDE.md"
QUICK_MODE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GOLD='\033[0;33m'
NC='\033[0m'

# Counters
TOTAL_FILES=0
FILES_WITH_INTEGRITY=0
ORPHANS=0
BROKEN_LINKS=0
MISSING_METADATA=0
CIRCULAR_REFS=0
VALID_CONNECTIONS=0

# Arrays for tracking
declare -A FILE_PARENTS
declare -A FILE_RULE_CODES
declare -A FILE_EXISTS
declare -A VISITED

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --quick|-q)
            QUICK_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: integrity-check.sh [--quick|-q] [--help|-h]"
            echo "  --quick, -q  Fast check (skip circular ref detection)"
            echo "  --help, -h   Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${GOLD}======================================${NC}"
echo -e "${GOLD}  PAUTINA Web Integrity Check${NC}"
echo -e "${GOLD}======================================${NC}"
echo ""

# Extract INTEGRITY metadata from a file
extract_integrity() {
    local file="$1"
    local content
    content=$(cat "$file" 2>/dev/null || echo "")

    # Extract INTEGRITY block (HTML comment format)
    local integrity_block
    integrity_block=$(echo "$content" | sed -n '/<!-- INTEGRITY/,/-->/p' 2>/dev/null)

    if [[ -z "$integrity_block" ]]; then
        return 1
    fi

    # Extract PARENT
    local parent
    parent=$(echo "$integrity_block" | grep -oP 'PARENT:\s*\K[^\s]+' 2>/dev/null | head -1)

    # Extract RULE_CODE
    local rule_code
    rule_code=$(echo "$integrity_block" | grep -oP 'RULE_CODE:\s*\K[^\s]+' 2>/dev/null | head -1)

    echo "${parent}|${rule_code}"
    return 0
}

# Check if file exists (relative to profile dir or absolute)
resolve_parent_path() {
    local parent="$1"
    local current_dir="$2"

    # Root file check
    if [[ "$parent" == "CLAUDE.md" ]]; then
        if [[ -f "${PROFILE_DIR}/CLAUDE.md" ]]; then
            echo "${PROFILE_DIR}/CLAUDE.md"
            return 0
        fi
        return 1
    fi

    # Try relative to reference/
    if [[ -f "${REFERENCE_DIR}/${parent}" ]]; then
        echo "${REFERENCE_DIR}/${parent}"
        return 0
    fi

    # Try relative to operations/
    if [[ -f "${OPERATIONS_DIR}/${parent}" ]]; then
        echo "${OPERATIONS_DIR}/${parent}"
        return 0
    fi

    # Try relative to current file's directory
    if [[ -f "${current_dir}/${parent}" ]]; then
        echo "${current_dir}/${parent}"
        return 0
    fi

    return 1
}

# Detect circular references using DFS
detect_circular() {
    local file="$1"
    local -A path_visited
    local current="$file"

    while [[ -n "$current" ]]; do
        if [[ "${path_visited[$current]}" == "1" ]]; then
            return 0  # Circular detected
        fi
        path_visited["$current"]=1

        local parent="${FILE_PARENTS[$current]}"
        if [[ -z "$parent" || "$parent" == "CLAUDE.md" ]]; then
            break
        fi

        # Resolve parent to full path
        local parent_path
        parent_path=$(resolve_parent_path "$parent" "$(dirname "$current")" 2>/dev/null)
        if [[ -z "$parent_path" ]]; then
            break
        fi
        current="$parent_path"
    done

    return 1  # No circular
}

# Check if file traces back to CLAUDE.md
traces_to_root() {
    local file="$1"
    local max_depth=20
    local depth=0
    local current="$file"

    while [[ $depth -lt $max_depth ]]; do
        local parent="${FILE_PARENTS[$current]}"

        if [[ "$parent" == "CLAUDE.md" ]]; then
            return 0  # Traces to root
        fi

        if [[ -z "$parent" ]]; then
            return 1  # Orphan
        fi

        # Resolve parent to full path
        local parent_path
        parent_path=$(resolve_parent_path "$parent" "$(dirname "$current")" 2>/dev/null)
        if [[ -z "$parent_path" ]]; then
            return 1  # Broken link
        fi

        current="$parent_path"
        ((depth++))
    done

    return 1  # Max depth exceeded
}

# Scan directory for .md files
scan_directory() {
    local dir="$1"
    local dir_name="$2"

    if [[ ! -d "$dir" ]]; then
        echo -e "${YELLOW}Warning: Directory not found: $dir${NC}"
        return
    fi

    echo -e "${BLUE}Scanning ${dir_name}...${NC}"

    while IFS= read -r -d '' file; do
        local filename
        filename=$(basename "$file")

        # Skip README, CHANGELOG
        if [[ "$filename" == "README.md" || "$filename" == "CHANGELOG.md" ]]; then
            continue
        fi

        ((TOTAL_FILES++))
        FILE_EXISTS["$file"]=1

        # Extract integrity metadata
        local metadata
        if metadata=$(extract_integrity "$file"); then
            ((FILES_WITH_INTEGRITY++))

            local parent rule_code
            parent=$(echo "$metadata" | cut -d'|' -f1)
            rule_code=$(echo "$metadata" | cut -d'|' -f2)

            FILE_PARENTS["$file"]="$parent"
            FILE_RULE_CODES["$file"]="$rule_code"

            # Check if parent field is empty
            if [[ -z "$parent" ]]; then
                echo -e "  ${RED}[MISSING PARENT]${NC} $file"
                ((MISSING_METADATA++))
            else
                # Check if parent exists
                local parent_path
                if parent_path=$(resolve_parent_path "$parent" "$(dirname "$file")" 2>/dev/null); then
                    ((VALID_CONNECTIONS++))
                else
                    echo -e "  ${RED}[BROKEN LINK]${NC} $file -> $parent"
                    ((BROKEN_LINKS++))
                fi
            fi
        else
            echo -e "  ${YELLOW}[NO INTEGRITY]${NC} $file"
            ((MISSING_METADATA++))
        fi
    done < <(find -L "$dir" -maxdepth 1 -name "*.md" -type f -print0 2>/dev/null)
}

# Main scan
echo ""
scan_directory "$REFERENCE_DIR" "reference/"
echo ""
scan_directory "$OPERATIONS_DIR" "operations/"
echo ""

# Second pass: Check for orphans and circular refs
echo -e "${BLUE}Analyzing dependency graph...${NC}"

for file in "${!FILE_EXISTS[@]}"; do
    # Check if traces to root
    if [[ -n "${FILE_PARENTS[$file]}" ]]; then
        if ! traces_to_root "$file"; then
            echo -e "  ${RED}[ORPHAN]${NC} $file (cannot reach CLAUDE.md)"
            ((ORPHANS++))
        fi
    fi

    # Check circular refs (skip in quick mode)
    if [[ "$QUICK_MODE" == "false" ]]; then
        if detect_circular "$file"; then
            echo -e "  ${RED}[CIRCULAR]${NC} $file"
            ((CIRCULAR_REFS++))
        fi
    fi
done

echo ""

# Summary
echo -e "${GOLD}======================================${NC}"
echo -e "${GOLD}  Summary${NC}"
echo -e "${GOLD}======================================${NC}"
echo ""
echo -e "  Total .md files scanned:    ${TOTAL_FILES}"
echo -e "  Files with INTEGRITY block: ${FILES_WITH_INTEGRITY}"
echo -e "  Valid connections:          ${GREEN}${VALID_CONNECTIONS}${NC}"
echo ""
echo -e "  ${RED}Violations:${NC}"
echo -e "    Missing INTEGRITY/PARENT: ${MISSING_METADATA}"
echo -e "    Broken parent links:      ${BROKEN_LINKS}"
echo -e "    Orphans (no root path):   ${ORPHANS}"
if [[ "$QUICK_MODE" == "false" ]]; then
    echo -e "    Circular references:      ${CIRCULAR_REFS}"
else
    echo -e "    Circular references:      ${YELLOW}(skipped in quick mode)${NC}"
fi
echo ""

# Calculate total violations
TOTAL_VIOLATIONS=$((MISSING_METADATA + BROKEN_LINKS + ORPHANS + CIRCULAR_REFS))

if [[ $TOTAL_VIOLATIONS -eq 0 ]]; then
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}  INTEGRITY CHECK PASSED${NC}"
    echo -e "${GREEN}======================================${NC}"
    exit 0
else
    echo -e "${RED}======================================${NC}"
    echo -e "${RED}  INTEGRITY CHECK FAILED${NC}"
    echo -e "${RED}  Total violations: ${TOTAL_VIOLATIONS}${NC}"
    echo -e "${RED}======================================${NC}"
    exit 1
fi
