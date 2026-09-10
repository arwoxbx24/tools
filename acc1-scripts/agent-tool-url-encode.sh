#!/usr/bin/env bash
# agent-tool-url-encode.sh — URL encode/decode without Python
# Usage: agent-tool-url-encode.sh [--decode] STRING
#        agent-tool-url-encode.sh --help

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: agent-tool-url-encode.sh [OPTIONS] STRING

URL encode or decode a string (pure bash, no Python required).
Handles UTF-8 / Cyrillic characters correctly.

Options:
  --decode    Decode a URL-encoded string (default: encode)
  --help      Show this help message

Examples:
  agent-tool-url-encode.sh "hello world"
  # → hello%20world

  agent-tool-url-encode.sh "привет мир"
  # → %D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20%D0%BC%D0%B8%D1%80

  agent-tool-url-encode.sh --decode "hello%20world"
  # → hello world

  agent-tool-url-encode.sh --decode "%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82"
  # → привет
EOF
}

# URL-encode: percent-encode every byte except unreserved chars (RFC 3986)
url_encode() {
    local string="$1"
    local encoded=""
    local i byte

    # Convert string to hex bytes via printf
    local hex
    hex=$(printf '%s' "$string" | od -An -tx1 -v | tr -d ' \n')

    for (( i=0; i<${#hex}; i+=2 )); do
        byte="${hex:$i:2}"
        # Unreserved chars (RFC 3986): A-Z a-z 0-9 - _ . ~
        # Decimal: 41-5A, 61-7A, 30-39, 2D, 5F, 2E, 7E
        local dec=$(( 16#$byte ))
        if (( (dec >= 0x41 && dec <= 0x5A) ||
              (dec >= 0x61 && dec <= 0x7A) ||
              (dec >= 0x30 && dec <= 0x39) ||
              dec == 0x2D || dec == 0x5F ||
              dec == 0x2E || dec == 0x7E )); then
            encoded+=$(printf "\\x${byte}")
        else
            encoded+="%${byte^^}"
        fi
    done

    printf '%s\n' "$encoded"
}

# URL-decode: replace %XX sequences and + with space
url_decode() {
    local string="$1"
    # Replace + with space first
    string="${string//+/ }"
    # Use printf to interpret %XX sequences
    printf '%b\n' "${string//%/\\x}"
}

# --- Argument parsing ---
DECODE=false
STRING=""

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --decode|-d)
            DECODE=true
            shift
            ;;
        --)
            shift
            STRING="$*"
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            STRING="$*"
            break
            ;;
    esac
done

if [[ -z "$STRING" ]]; then
    echo "Error: no string provided" >&2
    usage >&2
    exit 1
fi

if $DECODE; then
    url_decode "$STRING"
else
    url_encode "$STRING"
fi
