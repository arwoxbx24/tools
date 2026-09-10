#!/bin/bash
set -euo pipefail

# file-assess.sh — File assessment utility for agents
# Usage: file-assess.sh <file_path>
# Output: Single line with key=value pairs describing file and read strategy

FILE="${1:-}"

if [[ -z "$FILE" ]]; then
    echo "ERROR=no_file_path"
    exit 0
fi

if [[ ! -e "$FILE" ]]; then
    echo "ERROR=not_found"
    exit 0
fi

# Detect binary file (exclude text-executable like shell scripts)
FILE_TYPE_OUT=$(file "$FILE" 2>/dev/null || echo "")
if echo "$FILE_TYPE_OUT" | grep -qiE 'ELF|image|audio|video|compressed|zip|gzip|bzip2|binary' && ! echo "$FILE_TYPE_OUT" | grep -qi 'text'; then
    echo "TYPE=binary STRATEGY=skip HINT=\"binary file, use specific tools\""
    exit 0
fi

# Empty file
SIZE_BYTES=$(stat -c%s "$FILE" 2>/dev/null || echo 0)
if [[ "$SIZE_BYTES" -eq 0 ]]; then
    EXT="${FILE##*.}"
    TYPE="unknown"
    case "${EXT,,}" in
        json) TYPE="json" ;;
        yaml|yml) TYPE="yaml" ;;
        py|js|ts|sh|php|go|rs|java) TYPE="code" ;;
        md|txt) TYPE="text" ;;
        csv|tsv) TYPE="data" ;;
        log) TYPE="log" ;;
    esac
    echo "LINES=0 SIZE_KB=0 TYPE=$TYPE STRATEGY=skip"
    exit 0
fi

# Line count
LINES=$(wc -l < "$FILE" 2>/dev/null || echo 0)

# Size in KB (rounded)
SIZE_KB=$(( (SIZE_BYTES + 512) / 1024 ))
[[ "$SIZE_KB" -eq 0 && "$SIZE_BYTES" -gt 0 ]] && SIZE_KB=1

# Type detection by extension
EXT="${FILE##*.}"
# Handle files with no extension
if [[ "$EXT" == "$FILE" ]]; then
    EXT=""
fi

TYPE="unknown"
case "${EXT,,}" in
    json) TYPE="json" ;;
    yaml|yml) TYPE="yaml" ;;
    py|js|ts|sh|php|go|rs|java) TYPE="code" ;;
    md|txt) TYPE="text" ;;
    csv|tsv) TYPE="data" ;;
    log) TYPE="log" ;;
esac

# Strategy logic
STRATEGY=""
HINT=""

if [[ "$LINES" -le 500 ]]; then
    STRATEGY="direct-read"
elif [[ "$LINES" -le 1500 ]]; then
    STRATEGY="offset-read"
elif [[ "$LINES" -le 5000 ]]; then
    if [[ "$TYPE" == "json" ]]; then
        STRATEGY="jq-filter"
    else
        STRATEGY="grep-search"
    fi
else
    # > 5000
    if [[ "$TYPE" == "json" ]]; then
        STRATEGY="jq-filter"
    else
        STRATEGY="grep-search"
    fi
fi

# Build HINT
if [[ "$STRATEGY" == "jq-filter" && "$TYPE" == "json" ]]; then
    ROOT_TYPE=$(jq -r 'type' "$FILE" 2>/dev/null || echo "unknown")
    if [[ "$ROOT_TYPE" == "array" ]]; then
        ELEM_COUNT=$(jq 'length' "$FILE" 2>/dev/null || echo "?")
        HINT="use: jq 'type' file (array, $ELEM_COUNT elements) | jq '.[0]' for first element | jq 'length' file"
    elif [[ "$ROOT_TYPE" == "object" ]]; then
        TOP_KEYS=$(jq -r '[keys[]] | join(", ")' "$FILE" 2>/dev/null | head -c 200 || echo "?")
        HINT="use: jq 'keys' file (object, keys: $TOP_KEYS) | jq '.key' file for specific key"
    else
        HINT="use: jq 'type' file | jq '.' file for inspection"
    fi
elif [[ "$STRATEGY" == "grep-search" ]]; then
    HINT="use: Grep pattern + Read with offset=N limit=M"
elif [[ "$STRATEGY" == "offset-read" ]]; then
    HALF=$(( LINES / 2 ))
    HINT="use: Read with offset=0 limit=500 or offset=$HALF limit=500 for second half"
fi

# Output single line
if [[ -n "$HINT" ]]; then
    echo "LINES=$LINES SIZE_KB=$SIZE_KB TYPE=$TYPE STRATEGY=$STRATEGY HINT=\"$HINT\""
else
    echo "LINES=$LINES SIZE_KB=$SIZE_KB TYPE=$TYPE STRATEGY=$STRATEGY"
fi
