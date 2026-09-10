#!/usr/bin/env bash
# tx-promote.sh — promote a temporary project to a real project
# Usage: tx-promote.sh <tx-dir> <target>
# tx-dir: basename (e.g. .t-hr-bot-001) or full path inside /root/claude-projects/
# target: relative path from /root/claude-projects/ (e.g. clients/hr-system)

set -euo pipefail

PROJECTS_ROOT="/root/claude-projects"

# --- argument validation ---
if [[ $# -ne 2 ]]; then
    echo "Usage: tx-promote.sh <tx-dir> <target>" >&2
    echo "  tx-dir  — basename or full path, must start with .t-" >&2
    echo "  target  — relative path (e.g. clients/hr-system)" >&2
    exit 1
fi

RAW_TX="$1"
RAW_TARGET="$2"

# Normalize tx-dir to basename, then build full path
TX_BASENAME="$(basename "$RAW_TX")"
TX_PATH="${PROJECTS_ROOT}/${TX_BASENAME}"

# Normalize target (strip leading slash if any)
TARGET_REL="${RAW_TARGET#/}"
TARGET_PATH="${PROJECTS_ROOT}/${TARGET_REL}"

# --- validate: source exists and starts with .t- ---
if [[ ! "$TX_BASENAME" =~ ^\.t- ]]; then
    echo "ERROR: tx-dir must start with .t- (got: ${TX_BASENAME})" >&2
    exit 1
fi

if [[ ! -d "$TX_PATH" ]]; then
    echo "ERROR: source directory not found: ${TX_PATH}" >&2
    exit 1
fi

# --- validate: target must NOT exist ---
if [[ -e "$TARGET_PATH" ]]; then
    echo "ERROR: target already exists: ${TARGET_PATH}" >&2
    echo "       Refusing to overwrite. Choose a different target path." >&2
    exit 1
fi

# --- ensure target parent directory exists ---
TARGET_PARENT="$(dirname "$TARGET_PATH")"
if [[ ! -d "$TARGET_PARENT" ]]; then
    echo "ERROR: parent directory does not exist: ${TARGET_PARENT}" >&2
    echo "       Create the parent directory first or choose an existing one." >&2
    exit 1
fi

# --- update .tx-meta.json before move (while path is still known) ---
META_FILE="${TX_PATH}/.tx-meta.json"
ISO_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ -f "$META_FILE" ]]; then
    # Read existing meta, inject promoted fields
    TMP_META="$(mktemp)"
    # Use python3 for safe JSON manipulation (always available on this system)
    python3 - "$META_FILE" "$TARGET_REL" "$ISO_DATE" > "$TMP_META" <<'PYEOF'
import json, sys
path, target, ts = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data["promoted"] = True
data["promoted_to"] = target
data["promoted_at"] = ts
print(json.dumps(data, indent=2))
PYEOF
    mv "$TMP_META" "$META_FILE"
else
    # Create meta from scratch
    cat > "$META_FILE" <<EOF
{
  "promoted": true,
  "promoted_to": "${TARGET_REL}",
  "promoted_at": "${ISO_DATE}"
}
EOF
fi

# --- atomic move ---
mv "$TX_PATH" "$TARGET_PATH"

# --- Redis cleanup: remove sticky session pointers to old path ---
if command -v redis-cli &>/dev/null; then
    OLD_PATH="${TX_PATH}"
    # Find all session:sticky:project:* keys pointing to the old path
    KEYS_TO_DEL=()
    while IFS= read -r key; do
        val="$(redis-cli GET "$key" 2>/dev/null || true)"
        if [[ "$val" == "$OLD_PATH" ]]; then
            KEYS_TO_DEL+=("$key")
        fi
    done < <(redis-cli KEYS "session:sticky:project:*" 2>/dev/null || true)

    if [[ ${#KEYS_TO_DEL[@]} -gt 0 ]]; then
        redis-cli DEL "${KEYS_TO_DEL[@]}" >/dev/null 2>&1 || true
        echo "Redis: removed ${#KEYS_TO_DEL[@]} stale session key(s)"
    fi
fi

# --- success ---
echo "Promoted: ${TX_BASENAME} -> ${TARGET_REL}"
