#!/bin/bash
# validate-settings-json.sh
# Validates all settings.json files for Claude profiles
# Returns: exit 0 if all valid, exit 1 if any invalid

SETTINGS_FILES=(
    "$HOME/.claude/settings.json"
    "/root/workspaces/tools/acc1-scripts/settings.json"
    "$HOME/.claude_alex_acc2/settings.json"
)

ERRORS=()

for file in "${SETTINGS_FILES[@]}"; do
    [ -f "$file" ] || continue

    if ! jq '.' "$file" > /dev/null 2>&1; then
        ERRORS+=("$(basename "$(dirname "$file")")/settings.json")
    fi
done

if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "All settings.json files valid"
    exit 0
else
    echo "Invalid JSON in: ${ERRORS[*]}"
    exit 1
fi
