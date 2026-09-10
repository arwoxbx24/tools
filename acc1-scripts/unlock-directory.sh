#!/bin/bash
# unlock-directory.sh — Remove the hard directory lock
# Usage: unlock-directory.sh
# Effect: Removes /tmp/.claude-directory-lock, all directories become accessible again

LOCK_FILE="/tmp/.claude-directory-lock"

if [[ -f "$LOCK_FILE" ]]; then
    PREV=$(cat "$LOCK_FILE" 2>/dev/null)
    rm -f "$LOCK_FILE"
    echo "Directory lock removed (was: $PREV)"
else
    echo "No directory lock active."
fi
