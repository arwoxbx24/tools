#!/bin/bash
# Idea Lifecycle Management Script
# Usage:
#   idea-lifecycle.sh create "title"     - Create new idea with [IDEA] prefix, Status=Ideas
#   idea-lifecycle.sh promote <number>   - Move idea from Ideas to Todo (ready for work)
#   idea-lifecycle.sh archive <number>   - Move to Archive status
#   idea-lifecycle.sh list               - Show all ideas (Status=Ideas)
#   idea-lifecycle.sh archived           - Show archived items

set -e

GITHUB_USER="arwoxbx24"
REPO="claude-state"
CONFIG_FILE="/root/workspaces/tools/acc1-scripts/.projects-config"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "[ERROR] Config file not found: $CONFIG_FILE"
    exit 1
fi

# Required config variables
: "${PROJECT_ID:?Missing PROJECT_ID}"
: "${STATUS_FIELD_ID:?Missing STATUS_FIELD_ID}"
: "${STATUS_OPTION_IDEAS:?Missing STATUS_OPTION_IDEAS}"
: "${STATUS_OPTION_ARCHIVE:?Missing STATUS_OPTION_ARCHIVE}"
: "${STATUS_OPTION_TODO:?Missing STATUS_OPTION_TODO}"

# Helper function to update issue status in project
update_project_status() {
    local ISSUE_NUMBER=$1
    local STATUS_OPTION_ID=$2
    local STATUS_NAME=$3

    echo "[1/4] Getting Issue node ID for #$ISSUE_NUMBER..."
    ISSUE_NODE_ID=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_USER/$REPO" --json id -q .id)

    if [ -z "$ISSUE_NODE_ID" ]; then
        echo "[ERROR] Issue #$ISSUE_NUMBER not found"
        return 1
    fi
    echo "      Issue node ID: $ISSUE_NODE_ID"

    echo "[2/4] Finding item in Projects..."
    ITEM_ID=$(gh api graphql -f query="query { node(id: \"$ISSUE_NODE_ID\") { ... on Issue { projectItems(first: 1) { nodes { id } } } } }" --jq '.data.node.projectItems.nodes[0].id' 2>/dev/null)

    # If not found in project, add it first
    if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" == "null" ]; then
        echo "      Issue not in project, adding..."
        ADD_RESULT=$(gh api graphql -f query="
          mutation {
            addProjectV2ItemById(input: {
              projectId: \"$PROJECT_ID\"
              contentId: \"$ISSUE_NODE_ID\"
            }) {
              item { id }
            }
          }")
        ITEM_ID=$(echo "$ADD_RESULT" | jq -r '.data.addProjectV2ItemById.item.id')
        echo "      Added to project, item ID: $ITEM_ID"
    else
        echo "      Found item ID: $ITEM_ID"
    fi

    echo "[3/4] Updating status to '$STATUS_NAME'..."
    UPDATE_RESULT=$(gh api graphql -f query='
      mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: {singleSelectOptionId: $optionId}
        }) {
          projectV2Item {
            id
          }
        }
      }' -f projectId="$PROJECT_ID" -f itemId="$ITEM_ID" -f fieldId="$STATUS_FIELD_ID" -f optionId="$STATUS_OPTION_ID")

    echo "[4/4] Verifying..."
    if echo "$UPDATE_RESULT" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null 2>&1; then
        echo "[OK] Issue #$ISSUE_NUMBER status updated to '$STATUS_NAME'"
        return 0
    else
        echo "[ERROR] Failed to update status"
        echo "$UPDATE_RESULT"
        return 1
    fi
}

# Command: create
cmd_create() {
    local TITLE="$1"

    if [ -z "$TITLE" ]; then
        echo "Usage: idea-lifecycle.sh create \"title\""
        exit 1
    fi

    # Add [IDEA] prefix if not present
    if [[ ! "$TITLE" =~ ^\[IDEA\] ]]; then
        TITLE="[IDEA] $TITLE"
    fi

    echo "Creating idea: $TITLE"

    # Create issue (without label as it may not exist)
    ISSUE_URL=$(gh issue create \
        --repo "$GITHUB_USER/$REPO" \
        --title "$TITLE" \
        --body "**Status:** Idea (not yet prioritized)")

    # Extract issue number from URL
    ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oP '\d+$')

    echo "Created issue #$ISSUE_NUMBER: $ISSUE_URL"

    # Set status to Ideas
    echo ""
    update_project_status "$ISSUE_NUMBER" "$STATUS_OPTION_IDEAS" "💡 Ideas / Идеи"

    echo ""
    echo "[OK] Idea #$ISSUE_NUMBER created and set to Ideas status"
}

# Command: promote
cmd_promote() {
    local ISSUE_NUMBER="$1"

    if [ -z "$ISSUE_NUMBER" ]; then
        echo "Usage: idea-lifecycle.sh promote <number>"
        exit 1
    fi

    echo "Promoting idea #$ISSUE_NUMBER to Todo..."

    # Verify it's an idea
    TITLE=$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_USER/$REPO" --json title -q .title)

    if [[ ! "$TITLE" =~ ^\[IDEA\] ]]; then
        echo "[WARNING] Issue #$ISSUE_NUMBER doesn't have [IDEA] prefix"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Update status to Todo
    update_project_status "$ISSUE_NUMBER" "$STATUS_OPTION_TODO" "Todo / К выполнению"

    # Update issue body to reflect promotion
    gh issue edit "$ISSUE_NUMBER" \
        --repo "$GITHUB_USER/$REPO" \
        --body "**Status:** Ready for implementation (promoted from Ideas)" \
        2>/dev/null || true

    echo ""
    echo "[OK] Idea #$ISSUE_NUMBER promoted to Todo"
}

# Command: archive
cmd_archive() {
    local ISSUE_NUMBER="$1"

    if [ -z "$ISSUE_NUMBER" ]; then
        echo "Usage: idea-lifecycle.sh archive <number>"
        exit 1
    fi

    echo "Archiving issue #$ISSUE_NUMBER..."

    # Update status to Archive
    update_project_status "$ISSUE_NUMBER" "$STATUS_OPTION_ARCHIVE" "📦 Archive / Архив"

    # Update issue body
    gh issue edit "$ISSUE_NUMBER" \
        --repo "$GITHUB_USER/$REPO" \
        --body "**Status:** Archived (paused or no longer relevant)" \
        2>/dev/null || true

    echo ""
    echo "[OK] Issue #$ISSUE_NUMBER archived"
}

# Command: list
cmd_list() {
    echo "Ideas (Status=Ideas):"
    echo "====================="
    echo ""

    # Query project for items with Ideas status
    QUERY_RESULT=$(gh api graphql -f query='
      query($projectId: ID!) {
        node(id: $projectId) {
          ... on ProjectV2 {
            items(first: 100) {
              nodes {
                id
                content {
                  ... on Issue {
                    number
                    title
                    url
                    createdAt
                    labels(first: 10) {
                      nodes {
                        name
                      }
                    }
                  }
                }
                fieldValueByName(name: "Status") {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                  }
                }
              }
            }
          }
        }
      }' -f projectId="$PROJECT_ID")

    # Filter and display items with Ideas status (match bilingual name)
    echo "$QUERY_RESULT" | jq -r '
      .data.node.items.nodes[] |
      select(.fieldValueByName.name | contains("Ideas") or contains("Идеи")) |
      select(.content != null) |
      "#\(.content.number) - \(.content.title)\n  URL: \(.content.url)\n  Created: \(.content.createdAt | split("T")[0])\n"
    '

    COUNT=$(echo "$QUERY_RESULT" | jq -r '[.data.node.items.nodes[] | select(.fieldValueByName.name | contains("Ideas") or contains("Идеи")) | select(.content != null)] | length')
    echo "Total: $COUNT ideas"
}

# Command: archived
cmd_archived() {
    echo "Archived items (Status=Archive):"
    echo "================================="
    echo ""

    # Query project for items with Archive status
    QUERY_RESULT=$(gh api graphql -f query='
      query($projectId: ID!) {
        node(id: $projectId) {
          ... on ProjectV2 {
            items(first: 100) {
              nodes {
                id
                content {
                  ... on Issue {
                    number
                    title
                    url
                    createdAt
                    labels(first: 10) {
                      nodes {
                        name
                      }
                    }
                  }
                }
                fieldValueByName(name: "Status") {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                  }
                }
              }
            }
          }
        }
      }' -f projectId="$PROJECT_ID")

    # Filter and display items with Archive status (match bilingual name)
    echo "$QUERY_RESULT" | jq -r '
      .data.node.items.nodes[] |
      select(.fieldValueByName.name | contains("Archive") or contains("Архив")) |
      select(.content != null) |
      "#\(.content.number) - \(.content.title)\n  URL: \(.content.url)\n  Created: \(.content.createdAt | split("T")[0])\n"
    '

    COUNT=$(echo "$QUERY_RESULT" | jq -r '[.data.node.items.nodes[] | select(.fieldValueByName.name | contains("Archive") or contains("Архив")) | select(.content != null)] | length')
    echo "Total: $COUNT archived items"
}

# Main command dispatcher
COMMAND="$1"
shift || true

case "$COMMAND" in
    create)
        cmd_create "$@"
        ;;
    promote)
        cmd_promote "$@"
        ;;
    archive)
        cmd_archive "$@"
        ;;
    list)
        cmd_list
        ;;
    archived)
        cmd_archived
        ;;
    *)
        echo "Usage: idea-lifecycle.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create \"title\"     - Create new idea with [IDEA] prefix, Status=Ideas"
        echo "  promote <number>   - Move idea from Ideas to Todo (ready for work)"
        echo "  archive <number>   - Move to Archive status"
        echo "  list               - Show all ideas (Status=Ideas)"
        echo "  archived           - Show archived items"
        echo ""
        echo "Examples:"
        echo "  idea-lifecycle.sh create \"Add dark mode to dashboard\""
        echo "  idea-lifecycle.sh list"
        echo "  idea-lifecycle.sh promote 42"
        echo "  idea-lifecycle.sh archive 38"
        exit 1
        ;;
esac
