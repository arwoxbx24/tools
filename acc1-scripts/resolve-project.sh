#!/usr/bin/env bash
# resolve-project.sh — project auto-resolver based on keyword matching
# Input:  $1 = user message text, $2 = session_id
# Output: stdout = "project_name|directory_path" or empty string (no switch needed)
# Fast: uses bash/grep for matching, python3 only for one-shot YAML parse

set -euo pipefail

MESSAGE="${1:-}"
SESSION_ID="${2:-}"
REGISTRY="/root/workspaces/tools/acc1-scripts/rules-data/project-registry.yaml"
LOCK_FILE="/tmp/.project-dir-lock-${SESSION_ID}"

# Nothing to resolve if no message
[[ -z "$MESSAGE" ]] && exit 0

# --- Parse YAML into a flat TSV: priority<TAB>name<TAB>directory<TAB>keywords ---
# python3 one-shot, output is cached in /tmp for the session lifetime
CACHE_FILE="/tmp/.resolve-project-cache-${SESSION_ID}"

if [[ ! -f "$CACHE_FILE" || "$REGISTRY" -nt "$CACHE_FILE" ]]; then
    python3 - "$REGISTRY" > "$CACHE_FILE" <<'PYEOF'
import sys, yaml

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

projects = data.get('projects', {})
rows = []
for name, cfg in projects.items():
    priority = cfg.get('priority', 99)
    directory = cfg.get('directory', '')
    kw_en = cfg.get('keywords_en', [])
    kw_ru = cfg.get('keywords_ru', [])
    all_kw = [str(k) for k in kw_en + kw_ru]
    # Join keywords with newline so each can be grepped independently
    kw_str = '|'.join(all_kw)
    rows.append((priority, name, directory, kw_str))

rows.sort(key=lambda r: r[0])
for priority, name, directory, kw_str in rows:
    print(f"{priority}\t{name}\t{directory}\t{kw_str}")
PYEOF
fi

# --- Read current lock ---
CURRENT_LOCK=""
if [[ -n "$SESSION_ID" && -f "$LOCK_FILE" ]]; then
    CURRENT_LOCK="$(cat "$LOCK_FILE" 2>/dev/null || true)"
fi

# --- Match message against keywords ---
MSG_LOWER="$(printf '%s' "$MESSAGE" | tr '[:upper:]' '[:lower:]')"

while IFS=$'\t' read -r _priority name directory kw_pattern; do
    [[ -z "$kw_pattern" ]] && continue

    # Build grep pattern: "keyword1|keyword2|..."  (already pipe-separated from python)
    if printf '%s' "$MSG_LOWER" | grep -qiE "$kw_pattern"; then
        # Match found — check lock
        if [[ "$CURRENT_LOCK" == "$name" ]]; then
            # Already on this project, no switch needed
            exit 0
        fi
        # Output resolution result
        printf '%s|%s\n' "$name" "$directory"
        exit 0
    fi
done < "$CACHE_FILE"

# No match found — output nothing
exit 0
