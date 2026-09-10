#!/bin/bash
# PHPStan Static Analyzer
# Usage: phpstan-analyze.sh <path> [--level=N] [--json]

set -e

PATH_TO_ANALYZE="${1:-.}"
LEVEL="5"
OUTPUT_FORMAT="table"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --level=*) LEVEL="${arg#*=}" ;;
    --json) OUTPUT_FORMAT="json" ;;
  esac
done

# Check if phpstan is installed (V027: NO auto-install - security risk)
if ! command -v phpstan &> /dev/null; then
  echo "❌ ERROR: PHPStan not installed!"
  echo "💡 Install manually: composer global require phpstan/phpstan"
  echo "⛔ Auto-install disabled for security (V028)"
  exit 1
fi

echo "🔍 Analyzing: $PATH_TO_ANALYZE (level $LEVEL)"

# Run PHPStan with V027 resource limits
if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  timeout 300 phpstan analyse "$PATH_TO_ANALYZE" \
    --level="$LEVEL" \
    --error-format=json \
    --no-progress \
    --processes=1 \
    --memory-limit=256M \
    2>/dev/null || true
else
  timeout 300 phpstan analyse "$PATH_TO_ANALYZE" \
    --level="$LEVEL" \
    --no-progress \
    --processes=1 \
    --memory-limit=256M \
    2>/dev/null || true
fi
