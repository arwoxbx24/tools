#!/bin/bash
# validate-hooks-syntax.sh
# Validates syntax of ALL shell scripts in hooks directory
# Returns: exit 0 if all pass, exit 1 if any fail

HOOKS_DIR="/root/workspaces/tools/acc1-scripts/hooks"
ERRORS=()

for script in "$HOOKS_DIR"/*.sh; do
    [ -f "$script" ] || continue

    if ! bash -n "$script" 2>/dev/null; then
        ERRORS+=("$(basename "$script")")
    fi
done

if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "All hooks syntax OK"
    exit 0
else
    echo "Syntax errors in: ${ERRORS[*]}"
    exit 1
fi
