#!/usr/bin/env bash
# Hook Validator — detects broken hooks that don't read stdin correctly
# Claude Code hooks receive JSON via stdin. Correct: INPUT="$(cat)" or direct jq
# Broken: $TOOL_INPUT, $CLAUDE_TOOL_INPUT, "$1" for tool data
# Usage: bash hook-validator.sh [--quiet]
# Issue: #230
set +e

HOOKS_DIR="/root/workspaces/tools/acc1-scripts/hooks"
OK=0; BROKEN=0; EXEMPT=0; CHECK=0
QUIET="${1:-}"

# Event hooks that don't need stdin tool data
EXEMPT_HOOKS="auto-context-restore.sh auto-context-save-stop.sh auto-reload-service.sh block-unverified-ports.sh commit-blocker.sh count-code-lines.sh post-recovery-check.sh rules-reload-reminder.sh skill-activator-plan.sh skill-deactivator-stop.sh track-task-usage.sh ultrathink-detector.sh plan-audit.sh"

echo "=== HOOK INPUT VALIDATOR ==="
echo ""

BROKEN_LIST=""

for f in "$HOOKS_DIR"/*.sh; do
  [ -f "$f" ] || continue
  name=$(basename "$f")

  # Skip exempt hooks
  if echo " $EXEMPT_HOOKS " | grep -q " $name "; then
    EXEMPT=$((EXEMPT + 1))
    continue
  fi

  # Check: does it read stdin?
  reads_stdin=0
  grep -q '$(cat)' "$f" 2>/dev/null && reads_stdin=1
  grep -q '$(jq ' "$f" 2>/dev/null && reads_stdin=1

  # Check: does it use broken patterns?
  uses_broken=0
  broken_detail=""

  # Pattern 1: $TOOL_INPUT used as variable (not assignment like TOOL_INPUT="...")
  if grep -Pn '\$TOOL_INPUT(?!=)|\$\{TOOL_INPUT\}' "$f" 2>/dev/null | grep -Pv '^\d+:\s*#' | head -1 | read -r line; then
    uses_broken=1
    broken_detail="uses \$TOOL_INPUT (undefined env var): $line"
  fi

  # Pattern 2: $CLAUDE_TOOL_INPUT
  if grep -Pn '\$CLAUDE_TOOL_INPUT|\$\{CLAUDE_TOOL_INPUT\}' "$f" 2>/dev/null | grep -Pv '^\d+:\s*#' | head -1 | read -r line; then
    uses_broken=1
    broken_detail="uses \$CLAUDE_TOOL_INPUT (undefined env var): $line"
  fi

  # Pattern 3: Using $1 for tool data (file_path="$1", command="$1")
  # But NOT for UserPromptSubmit hooks where $1 might be valid
  if grep -Pn '(file_path|command|tool_name)="\$1"' "$f" 2>/dev/null | grep -Pv '^\d+:\s*#' | head -1 | read -r line; then
    uses_broken=1
    broken_detail="uses \$1 for tool data (not passed by Claude Code): $line"
  fi

  # If hook reads stdin, $TOOL_INPUT may be legitimately defined from stdin JSON
  if [ "$uses_broken" -eq 1 ] && [ "$reads_stdin" -eq 1 ]; then
    uses_broken=0
    broken_detail=""
  fi

  # Classify
  if [ "$uses_broken" -eq 1 ]; then
    BROKEN=$((BROKEN + 1))
    BROKEN_LIST="${BROKEN_LIST}  BROKEN: $name — $broken_detail\n"
    [ -z "$QUIET" ] && echo "  BROKEN: $name — $broken_detail"
  elif [ "$reads_stdin" -eq 1 ]; then
    OK=$((OK + 1))
    [ -z "$QUIET" ] && echo "  OK: $name"
  else
    CHECK=$((CHECK + 1))
    [ -z "$QUIET" ] && echo "  CHECK: $name (no stdin reading detected)"
  fi
done

TOTAL=$((OK + BROKEN + EXEMPT + CHECK))

echo ""
echo "=== HOOK VALIDATION SUMMARY ==="
echo "Total hooks: $TOTAL"
echo "OK: $OK"
echo "Exempt: $EXEMPT"
echo "Check: $CHECK"
echo "BROKEN: $BROKEN"

if [ "$BROKEN" -gt 0 ]; then
  echo ""
  echo "=== BROKEN HOOKS ==="
  echo -e "$BROKEN_LIST"
  echo "RESULT: VALIDATION FAILED"
  exit 1
else
  echo ""
  echo "RESULT: ALL HOOKS VALID"
  exit 0
fi

