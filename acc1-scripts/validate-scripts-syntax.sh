#!/bin/bash
# validate-scripts-syntax.sh
# Validates syntax of ALL shell scripts in scripts directory
# Returns: exit 0 if all pass, exit 1 if any fail

SCRIPTS_DIR="/root/workspaces/tools/acc1-scripts/scripts"
ERRORS=()

for script in "$SCRIPTS_DIR"/*.sh; do
    [ -f "$script" ] || continue

    # Skip self to avoid recursion issues
    [[ "$script" == *"validate-scripts-syntax.sh" ]] && continue

    if ! bash -n "$script" 2>/dev/null; then
        ERRORS+=("$(basename "$script")")
    fi
done

if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "All scripts syntax OK"
    exit 0
else
    echo "Syntax errors in: ${ERRORS[*]}"
    exit 1
fi
