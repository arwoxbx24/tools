#!/usr/bin/env bash
# claude-compliance-scanner.sh — Offline hook system compliance audit
set -euo pipefail

HOOKS_DIR="/root/workspaces/tools/acc1-scripts/hooks"
SETTINGS="$HOME/.claude/settings.json"
PASS=0
FAIL=0
WARN=0

echo "=== CLAUDE COMPLIANCE SCANNER ==="
echo "Date: $(date -Is)"
echo ""

# 1. Syntax check all hooks
echo "--- Syntax Check ---"
for f in "$HOOKS_DIR"/*.sh; do
  if bash -n "$f" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $(basename "$f")"
    FAIL=$((FAIL + 1))
  fi
done
echo "Syntax: $PASS pass, $FAIL fail"

# 2. Check all registered hooks exist on disk
echo ""
echo "--- Registration Check ---"
REG_PASS=0
REG_FAIL=0
REGISTERED=$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$SETTINGS" 2>/dev/null | grep -oP '[\w/.-]+\.sh' | sort -u)
for hook in $REGISTERED; do
  FULL="$HOOKS_DIR/$(basename "$hook")"
  if [[ -f "$FULL" ]]; then
    REG_PASS=$((REG_PASS + 1))
  else
    echo "MISSING: $hook (registered but not on disk)"
    REG_FAIL=$((REG_FAIL + 1))
  fi
done
echo "Registration: $REG_PASS found, $REG_FAIL missing"

# 3. Check for duplicate registrations
echo ""
echo "--- Duplicate Check (V_DEDUP) ---"
DUPES=$(jq -r '.hooks | to_entries[] | .value[] | .hooks[] | .command' "$SETTINGS" 2>/dev/null | sort | uniq -d)
if [[ -z "$DUPES" ]]; then
  echo "No duplicates found"
else
  echo "DUPLICATES:"
  echo "$DUPES"
  WARN=$((WARN + $(echo "$DUPES" | wc -l)))
fi

# 4. Check critical V-rules have enforcing hooks
echo ""
echo "--- Critical V-Rule Coverage ---"
RULES=("V025" "V032" "V070" "V101" "V102" "V109" "V162" "V262" "V275" "V301" "V353")
for rule in "${RULES[@]}"; do
  if grep -rl "$rule" "$HOOKS_DIR"/*.sh >/dev/null 2>&1; then
    echo "  OK $rule — enforced"
  else
    echo "  MISSING $rule — NO enforcing hook"
    WARN=$((WARN + 1))
  fi
done

# 5. New hooks from PE System Hardening plan
echo ""
echo "--- PE Hardening Hooks (Wave 1-3) ---"
NEW_HOOKS=(
  "enforce-minio-reuse-path.sh"
  "minio-path-registry.sh"
  "enforce-git-commit-on-stop.sh"
  "post-agent-compliance-scan.sh"
  "health-check-delegator.sh"
  "enforce-visual-baseline.sh"
)
for h in "${NEW_HOOKS[@]}"; do
  if [[ -f "$HOOKS_DIR/$h" ]]; then
    echo "  OK $h — exists"
  else
    echo "  MISSING $h — not found"
    FAIL=$((FAIL + 1))
  fi
done

# Summary
echo ""
echo "=== SUMMARY ==="
TOTAL=$((PASS + FAIL))
echo "Syntax: $PASS/$TOTAL pass"
echo "Warnings: $WARN"
echo "Failures: $FAIL"

# Store in Redis
redis-cli SET "compliance:audit:$(date +%Y%m%d)" "{\"pass\":$PASS,\"fail\":$FAIL,\"warn\":$WARN,\"date\":\"$(date -Is)\"}" EX 604800 >/dev/null 2>&1

if [[ $FAIL -gt 0 ]]; then
  exit 1
else
  exit 0
fi
