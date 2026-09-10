#!/usr/bin/env bash
# tx-create.sh — create a temporary project dir under /root/claude-projects/
# Convention: /root/claude-projects/.t-{slug}-{NNN}/
# Usage: tx-create.sh <slug>
# slug: ^[a-z0-9-]{3,40}$

set -euo pipefail

PROJECTS_ROOT="/root/claude-projects"

# --- validate argument ---
if [[ $# -ne 1 ]]; then
    echo "Usage: tx-create.sh <slug>" >&2
    echo "slug: lowercase letters, digits, dashes only (3-40 chars)" >&2
    exit 1
fi

SLUG="$1"

if [[ ! "$SLUG" =~ ^[a-z0-9-]{3,40}$ ]]; then
    echo "ERROR: invalid slug '${SLUG}'" >&2
    echo "slug must match ^[a-z0-9-]{3,40}$ (lowercase, digits, dashes, 3-40 chars)" >&2
    exit 1
fi

# --- find max existing index for this slug ---
PATTERN="${PROJECTS_ROOT}/.t-${SLUG}-"

MAX_INDEX=0
while IFS= read -r -d '' dir; do
    # extract trailing NNN from the dir name
    basename_dir="$(basename "$dir")"
    # strip prefix .t-{slug}-
    suffix="${basename_dir#.t-${SLUG}-}"
    # must be purely numeric
    if [[ "$suffix" =~ ^[0-9]+$ ]]; then
        num=$((10#$suffix))
        if (( num > MAX_INDEX )); then
            MAX_INDEX=$num
        fi
    fi
done < <(find "$PROJECTS_ROOT" -maxdepth 1 -type d -name ".t-${SLUG}-*" -print0 2>/dev/null)

NEW_INDEX=$(( MAX_INDEX + 1 ))
NEW_INDEX_PADDED=$(printf "%03d" "$NEW_INDEX")

NEW_DIR="${PROJECTS_ROOT}/.t-${SLUG}-${NEW_INDEX_PADDED}"

# --- create directory ---
mkdir -p "$NEW_DIR"

# --- write .tx-meta.json ---
ISO_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
cat > "${NEW_DIR}/.tx-meta.json" <<EOF
{
  "created": "${ISO_DATE}",
  "slug": "${SLUG}",
  "index": ${NEW_INDEX},
  "promoted": false
}
EOF

# --- output ---
echo "$NEW_DIR"
