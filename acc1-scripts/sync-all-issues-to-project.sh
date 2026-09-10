#!/bin/bash
# Sync all issues #1-5 to Projects V2
# Updates Type field for each issue

# Note: Removed 'set -e' to continue processing even if one issue fails

GITHUB_USER="arwoxbx24"
REPO="claude-state"

echo "=========================================="
echo "  BULK SYNC: ALL ISSUES TO PROJECTS V2"
echo "=========================================="
echo ""

# Get all issues with type: labels
ISSUES=$(gh issue list --repo "$GITHUB_USER/$REPO" --state all --json number,labels \
  --jq '.[] | select(.labels[] | .name | startswith("type:")) | .number')

if [ -z "$ISSUES" ]; then
    echo "[WARN] No issues with type: labels found"
    exit 0
fi

ISSUE_COUNT=$(echo "$ISSUES" | wc -l | tr -d ' ')
echo "Found $ISSUE_COUNT issue(s) with type: labels"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for ISSUE_NUM in $ISSUES; do
    echo "Processing Issue #$ISSUE_NUM..."
    if bash /root/workspaces/tools/acc1-scripts/scripts/sync-project-type-field.sh $ISSUE_NUM 2>&1 | grep -q "\[OK\] Sync complete"; then
        echo "  [OK] Issue #$ISSUE_NUM synced"
        ((SUCCESS_COUNT++))
    else
        echo "  [NO] Issue #$ISSUE_NUM failed"
        ((FAIL_COUNT++))
    fi
    echo ""
done

echo "=========================================="
echo "[OK] Bulk sync complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Success: $SUCCESS_COUNT"
echo "  - Failed: $FAIL_COUNT"
echo "  - Total: $ISSUE_COUNT"
