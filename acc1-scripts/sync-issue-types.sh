#!/bin/bash
# Sync Issue Types based on issue title prefix
# [EPIC] -> Epic, [FIX] -> Bug, [FEATURE] -> Feature, [IDEA] -> Idea
# Also syncs to Projects V2 "Issue Type" field

GITHUB_USER="arwoxbx24"
REPO="claude-state"

# Load Projects config
source /root/workspaces/tools/acc1-scripts/.projects-config 2>/dev/null

# Issue Type IDs (GraphQL node_id for GitHub Issues)
declare -A TYPE_IDS=(
  ["task"]="IT_kwDODbPMm84Btgtd"
  ["bug"]="IT_kwDODbPMm84Btgte"
  ["feature"]="IT_kwDODbPMm84Btgtf"
  ["epic"]="IT_kwDODbPMm84B09VX"
  ["improvement"]="IT_kwDODbPMm84B09VY"
  ["documentation"]="IT_kwDODbPMm84B09VZ"
)

# Projects V2 "Issue Type" field options
PROJECTS_TYPE_FIELD="PVTSSF_lADODbPMm84BMbuTzg7t5DI"
declare -A PROJECTS_TYPE_OPTIONS=(
  ["bug"]="7a04eafb"
  ["feature"]="d7d0e07a"
  ["improvement"]="c20b76a4"
  ["docs"]="a8d3a79b"
  ["research"]="807d93a1"
  ["epic"]="2d3caf1c"
)

echo "=========================================="
echo "  SYNC ISSUE TYPES FROM TITLE PREFIX"
echo "=========================================="
echo ""

# Get all issues
ISSUES=$(gh issue list --repo "$GITHUB_USER/$REPO" --state all --json number,title,id --jq '.[] | "\(.number)|\(.title)|\(.id)"')

if [ -z "$ISSUES" ]; then
    echo "[WARN] No issues found"
    exit 0
fi

SUCCESS=0
FAIL=0

while IFS='|' read -r NUM TITLE NODE_ID; do
    echo "Issue #$NUM: $TITLE"

    # Determine type from title prefix
    TYPE_KEY=""
    if [[ "$TITLE" =~ ^\[TASK\] ]]; then
        TYPE_KEY="task"
    elif [[ "$TITLE" =~ ^\[FIX\] ]]; then
        TYPE_KEY="bug"
    elif [[ "$TITLE" =~ ^\[FEATURE\] ]]; then
        TYPE_KEY="feature"
    elif [[ "$TITLE" =~ ^\[EPIC\] ]]; then
        TYPE_KEY="epic"
    elif [[ "$TITLE" =~ ^\[IMPROVEMENT\] ]] || [[ "$TITLE" =~ ^\[REFACTOR\] ]]; then
        TYPE_KEY="improvement"
    elif [[ "$TITLE" =~ ^\[DOCS\] ]] || [[ "$TITLE" =~ ^\[DOC\] ]]; then
        TYPE_KEY="documentation"
    elif [[ "$TITLE" =~ ^\[PLAN\] ]] || [[ "$TITLE" =~ ^\[CHECKPOINT\] ]] || [[ "$TITLE" =~ ^\[TEST\] ]] || [[ "$TITLE" =~ ^\[TEST-[0-9]+\] ]]; then
        TYPE_KEY="task"  # Default to task
    else
        echo "  [SKIP] No prefix found"
        continue
    fi

    TYPE_ID="${TYPE_IDS[$TYPE_KEY]}"
    echo "  Setting type: $TYPE_KEY"

    # Update via GraphQL
    RESULT=$(gh api graphql -f query="
      mutation {
        updateIssue(input: {
          id: \"$NODE_ID\"
          issueTypeId: \"$TYPE_ID\"
        }) {
          issue {
            issueType { name }
          }
        }
      }" --jq '.data.updateIssue.issue.issueType.name' 2>&1)

    if [ -n "$RESULT" ] && [ "$RESULT" != "null" ]; then
        echo "  [OK] -> $RESULT"
        ((SUCCESS++))

        # Also set Projects V2 "Issue Type" field
        PROJ_TYPE_KEY="$TYPE_KEY"
        [ "$TYPE_KEY" = "task" ] && PROJ_TYPE_KEY=""  # No "task" option in Projects
        [ "$TYPE_KEY" = "documentation" ] && PROJ_TYPE_KEY="docs"

        if [ -n "$PROJ_TYPE_KEY" ] && [ -n "${PROJECTS_TYPE_OPTIONS[$PROJ_TYPE_KEY]}" ]; then
            # Get project item ID
            ITEM_ID=$(gh api graphql -f query="query { node(id: \"$NODE_ID\") { ... on Issue { projectItems(first: 1) { nodes { id } } } } }" --jq '.data.node.projectItems.nodes[0].id' 2>/dev/null)

            if [ -n "$ITEM_ID" ] && [ "$ITEM_ID" != "null" ]; then
                gh api graphql -f query="mutation { updateProjectV2ItemFieldValue(input: { projectId: \"$PROJECT_ID\", itemId: \"$ITEM_ID\", fieldId: \"$PROJECTS_TYPE_FIELD\", value: { singleSelectOptionId: \"${PROJECTS_TYPE_OPTIONS[$PROJ_TYPE_KEY]}\" } }) { projectV2Item { id } } }" >/dev/null 2>&1 && echo "  [OK] Projects V2 type set"
            fi
        fi
    else
        echo "  [FAIL] $RESULT"
        ((FAIL++))
    fi
    echo ""
done <<< "$ISSUES"

echo "=========================================="
echo "[DONE] Sync complete"
echo "=========================================="
echo "Success: $SUCCESS"
echo "Failed: $FAIL"
