#!/usr/bin/env bash
# agent-tool-file-stats.sh — file info without Python
# Usage: agent-tool-file-stats.sh [--json] [--help] FILE [FILE2...]

set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

usage() {
  cat <<'EOF'
Usage: agent-tool-file-stats.sh [OPTIONS] FILE [FILE2...]

Show file statistics without requiring Python.

OPTIONS:
  --json    Output all results as a JSON array
  --help    Show this help message

OUTPUT FIELDS (per file):
  path          Absolute path to the file
  size_human    Human-readable size (e.g. 4.2K, 1.3M)
  size_bytes    Raw size in bytes
  lines         Line count (0 for binary/empty files)
  type          File type from `file` command
  last_modified ISO-8601 last modification timestamp
  git_status    Git status code (M, A, ??, clean, not_tracked, no_git)

EXAMPLES:
  agent-tool-file-stats.sh /etc/hosts
  agent-tool-file-stats.sh --json src/app.js src/index.js
  agent-tool-file-stats.sh --json $(git diff --name-only)
EOF
}

# ── argument parsing ──────────────────────────────────────────────────────────

JSON_MODE=0
FILES=()

for arg in "$@"; do
  case "$arg" in
    --json)  JSON_MODE=1 ;;
    --help)  usage; exit 0 ;;
    *)       FILES+=("$arg") ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Error: no files specified." >&2
  usage >&2
  exit 1
fi

# ── per-file stat function ────────────────────────────────────────────────────

get_file_stats() {
  local input_path="$1"

  # Resolve to absolute path
  local abs_path
  if command -v realpath &>/dev/null; then
    abs_path="$(realpath -m "$input_path" 2>/dev/null || echo "$input_path")"
  else
    abs_path="$(cd "$(dirname "$input_path")" 2>/dev/null && pwd)/$(basename "$input_path")"
  fi

  # Existence check
  if [[ ! -e "$abs_path" ]]; then
    if [[ $JSON_MODE -eq 1 ]]; then
      printf '{"path":"%s","error":"file not found"}' "$abs_path"
    else
      echo "ERROR: $abs_path — file not found"
    fi
    return
  fi

  # Size
  local size_bytes
  size_bytes="$(stat -c '%s' "$abs_path" 2>/dev/null || stat -f '%z' "$abs_path" 2>/dev/null || echo 0)"

  local size_human
  if command -v numfmt &>/dev/null; then
    size_human="$(numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || echo "${size_bytes}B")"
  else
    # Fallback: manual human-readable
    if   (( size_bytes >= 1073741824 )); then
      size_human="$(echo "scale=1; $size_bytes / 1073741824" | bc)G"
    elif (( size_bytes >= 1048576 )); then
      size_human="$(echo "scale=1; $size_bytes / 1048576" | bc)M"
    elif (( size_bytes >= 1024 )); then
      size_human="$(echo "scale=1; $size_bytes / 1024" | bc)K"
    else
      size_human="${size_bytes}B"
    fi
  fi

  # Lines — only for text files, avoid counting binary
  local lines=0
  if file "$abs_path" 2>/dev/null | grep -qiE 'text|json|xml|html|script|source|ascii|utf'; then
    lines="$(wc -l < "$abs_path" 2>/dev/null || echo 0)"
    # wc -l doesn't count last line without newline; add 1 if file non-empty and no trailing newline
    if [[ $size_bytes -gt 0 ]]; then
      local last_char
      last_char="$(tail -c1 "$abs_path" 2>/dev/null | wc -l)"
      if [[ "$last_char" -eq 0 ]]; then
        lines=$(( lines + 1 ))
      fi
    fi
  fi

  # File type
  local file_type
  file_type="$(file --brief "$abs_path" 2>/dev/null || echo "unknown")"

  # Last modified — prefer ISO-8601
  # stat -c '%y' format: "2026-04-09 12:34:56.123456789 +0300"
  # Target: "2026-04-09T12:34:56+0300"
  local last_modified
  last_modified="$(stat -c '%y' "$abs_path" 2>/dev/null \
    | sed 's/ \([0-9][0-9]:[0-9][0-9]:[0-9][0-9]\)\.[0-9]* /T\1/' \
    | sed 's/ +/+/' | sed 's/ -/-/' \
    || stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S' "$abs_path" 2>/dev/null \
    || echo "unknown")"

  # Git status
  local git_status="no_git"
  local file_dir
  file_dir="$(dirname "$abs_path")"
  if git -C "$file_dir" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    local gs
    gs="$(git -C "$file_dir" status --porcelain -- "$abs_path" 2>/dev/null | head -1)"
    if [[ -z "$gs" ]]; then
      # Check if file is tracked at all
      if git -C "$file_dir" ls-files --error-unmatch "$abs_path" &>/dev/null 2>&1; then
        git_status="clean"
      else
        git_status="not_tracked"
      fi
    else
      git_status="${gs:0:2}"
      git_status="${git_status// /_}"
    fi
  fi

  # ── output ──────────────────────────────────────────────────────────────────
  if [[ $JSON_MODE -eq 1 ]]; then
    # Escape double-quotes in strings
    local safe_type safe_modified safe_path safe_gs
    safe_path="${abs_path//\"/\\\"}"
    safe_type="${file_type//\"/\\\"}"
    safe_modified="${last_modified//\"/\\\"}"
    safe_gs="${git_status//\"/\\\"}"
    printf '{
  "path": "%s",
  "size_human": "%s",
  "size_bytes": %s,
  "lines": %s,
  "type": "%s",
  "last_modified": "%s",
  "git_status": "%s"
}' "$safe_path" "$size_human" "$size_bytes" "$lines" "$safe_type" "$safe_modified" "$safe_gs"
  else
    echo "────────────────────────────────────────"
    echo "  path:          $abs_path"
    echo "  size:          $size_human ($size_bytes bytes)"
    echo "  lines:         $lines"
    echo "  type:          $file_type"
    echo "  last_modified: $last_modified"
    echo "  git_status:    $git_status"
  fi
}

# ── main loop ────────────────────────────────────────────────────────────────

if [[ $JSON_MODE -eq 1 ]]; then
  echo "["
  first=1
  for f in "${FILES[@]}"; do
    if [[ $first -eq 0 ]]; then
      echo ","
    fi
    get_file_stats "$f"
    first=0
  done
  echo ""
  echo "]"
else
  for f in "${FILES[@]}"; do
    get_file_stats "$f"
  done
  echo "────────────────────────────────────────"
fi
