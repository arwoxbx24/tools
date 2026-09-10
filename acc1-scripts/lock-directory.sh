#!/bin/bash
# lock-directory.sh — Create a hard directory lock
# Usage: lock-directory.sh /path/to/project
# Effect: All Bash/Write/Edit operations outside this path will be BLOCKED
# Remove with: unlock-directory.sh

LOCK_FILE="/tmp/.claude-directory-lock"

if [[ -z "$1" ]]; then
    echo "Usage: lock-directory.sh /absolute/path/to/project" >&2
    exit 1
fi

TARGET="$1"

# Must be an absolute path
if [[ "${TARGET:0:1}" != "/" ]]; then
    echo "Error: path must be absolute (got: $TARGET)" >&2
    exit 1
fi

echo "$TARGET" > "$LOCK_FILE"
echo "Directory locked to: $TARGET"
