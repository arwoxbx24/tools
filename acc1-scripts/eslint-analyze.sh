#!/bin/bash
# ESLint JavaScript/Node Analyzer
# Usage: eslint-analyze.sh <path> [--fix] [--json]

set -e

PATH_TO_ANALYZE="${1:-.}"
FIX_MODE=""
OUTPUT_FORMAT="stylish"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --fix) FIX_MODE="--fix" ;;
    --json) OUTPUT_FORMAT="json" ;;
  esac
done

# Check if eslint is installed (V027: NO auto-install - security risk)
if ! command -v eslint &> /dev/null; then
  echo "❌ ERROR: ESLint not installed!"
  echo "💡 Install manually: npm install -g eslint"
  echo "⛔ Auto-install disabled for security (V028)"
  exit 1
fi

echo "🔍 Analyzing: $PATH_TO_ANALYZE"

# Run ESLint with V027 resource limits
timeout 120 eslint "$PATH_TO_ANALYZE" \
  --ext .js,.jsx,.ts,.tsx,.mjs \
  --format "$OUTPUT_FORMAT" \
  --max-warnings=100 \
  $FIX_MODE \
  2>/dev/null || true
