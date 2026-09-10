#!/bin/bash
# Get GitHub Projects V2 information for arwoxbx24/claude-state
# Finds project ID, field IDs, and field options

GITHUB_USER="arwoxbx24"
REPO="claude-state"

echo "=========================================="
echo "  GITHUB PROJECTS V2 DISCOVERY"
echo "=========================================="
echo ""

# Step 1: List all projects for the organization
echo "[1/4] Listing projects for $GITHUB_USER..."
PROJECTS=$(gh api graphql -f query='
  query($org: String!) {
    organization(login: $org) {
      projectsV2(first: 10) {
        nodes {
          id
          number
          title
          url
        }
      }
    }
  }' -f org="$GITHUB_USER")

echo "$PROJECTS" | jq -r '.data.organization.projectsV2.nodes[] | "Project #\(.number): \(.title)\n  ID: \(.id)\n  URL: \(.url)\n"'

# Step 2: Ask user for project number
read -p "Enter project number to use: " PROJECT_NUM

# Step 3: Get project details including fields
echo ""
echo "[2/4] Getting project fields..."
PROJECT_DATA=$(gh api graphql -f query='
  query($org: String!, $number: Int!) {
    organization(login: $org) {
      projectV2(number: $number) {
        id
        title
        fields(first: 20) {
          nodes {
            ... on ProjectV2Field {
              id
              name
              dataType
            }
            ... on ProjectV2SingleSelectField {
              id
              name
              dataType
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  }' -f org="$GITHUB_USER" -F number="$PROJECT_NUM")

PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.data.organization.projectV2.id')
echo "Project ID: $PROJECT_ID"
echo ""

# Step 4: Find "Type" field
echo "[3/4] Finding 'Type' field..."
TYPE_FIELD=$(echo "$PROJECT_DATA" | jq -r '.data.organization.projectV2.fields.nodes[] | select(.name == "Type")')

if [ -z "$TYPE_FIELD" ]; then
    echo "[WARN] No 'Type' field found in project"
    echo ""
    echo "Available fields:"
    echo "$PROJECT_DATA" | jq -r '.data.organization.projectV2.fields.nodes[] | "- \(.name) (\(.dataType))"'
    echo ""
    echo "Please create a 'Type' field with options: Epic, Plan, Task"
    exit 1
fi

TYPE_FIELD_ID=$(echo "$TYPE_FIELD" | jq -r '.id')
echo "Type Field ID: $TYPE_FIELD_ID"
echo ""
echo "Type options:"
echo "$TYPE_FIELD" | jq -r '.options[] | "- \(.name): \(.id)"'

# Step 5: Save configuration
echo ""
echo "[4/4] Saving configuration..."
CONFIG_FILE="/root/workspaces/tools/acc1-scripts/.projects-config"

cat > "$CONFIG_FILE" << EOF
# GitHub Projects V2 Configuration
PROJECT_NUMBER=$PROJECT_NUM
PROJECT_ID=$PROJECT_ID
TYPE_FIELD_ID=$TYPE_FIELD_ID

# Type field options (name=id)
EOF

echo "$TYPE_FIELD" | jq -r '.options[] | "TYPE_OPTION_\(.name | ascii_upcase)=\(.id)"' >> "$CONFIG_FILE"

echo "Configuration saved to $CONFIG_FILE"
echo ""
cat "$CONFIG_FILE"
echo ""
echo "=========================================="
echo "[OK] Discovery complete!"
echo "=========================================="
