#!/bin/bash
# Semgrep Security Scanner
# Usage: semgrep-scan.sh <path> [--config=auto|p/php|p/javascript] [--json]

set -e

PATH_TO_SCAN="${1:-.}"
CONFIG="auto"
OUTPUT_FORMAT=""

# Parse arguments
for arg in "$@"; do
  case $arg in
    --config=*) CONFIG="${arg#*=}" ;;
    --json) OUTPUT_FORMAT="--json" ;;
  esac
done

# Check if semgrep is installed (V027: NO auto-install - security risk)
if ! command -v semgrep &> /dev/null; then
  echo "❌ ERROR: Semgrep not installed!"
  echo "💡 Install manually: pip3 install semgrep"
  echo "⛔ Auto-install disabled for security (V028)"
  exit 1
fi

echo "🔒 Security scan: $PATH_TO_SCAN (config: $CONFIG)"

# Run Semgrep with V027 resource limits
timeout 60 semgrep scan "$PATH_TO_SCAN" \
  --config "$CONFIG" \
  --quiet \
  --timeout=60 \
  --max-target-bytes=1000000 \
  $OUTPUT_FORMAT \
  2>/dev/null || true
