#!/bin/bash
# Link Validator — Check all file references in the system
# Finds broken links in CLAUDE.md and reference files

echo "🔗 Link Validator"
echo "================="

BROKEN=0
TOTAL=0
BASE_DIR="/root/workspaces/tools/acc1-scripts"

# Check all .md references in CLAUDE.md
echo ""
echo "Checking CLAUDE.md references..."
while IFS= read -r ref; do
    ((TOTAL++))
    # Remove backticks and quotes
    clean_ref=$(echo "$ref" | tr -d '`"')

    # Check different path patterns
    if [[ $clean_ref == reference/* ]] || [[ $clean_ref == templates/* ]] || [[ $clean_ref == operations/* ]] || [[ $clean_ref == scripts/* ]] || [[ $clean_ref == config/* ]]; then
        if [ ! -f "$BASE_DIR/$clean_ref" ]; then
            echo "  ❌ BROKEN: $clean_ref"
            ((BROKEN++))
        fi
    fi
done < <(grep -oP '`[^`]+\.md`|`[^`]+\.sh`' "$BASE_DIR/CLAUDE.md" | tr -d '`')

# Check references in reference/*.md files
echo ""
echo "Checking reference/ files..."
for file in "$BASE_DIR"/reference/*.md; do
    while IFS= read -r ref; do
        ((TOTAL++))
        clean_ref=$(echo "$ref" | tr -d '`"')

        if [[ $clean_ref == reference/* ]] || [[ $clean_ref == templates/* ]] || [[ $clean_ref == operations/* ]]; then
            if [ ! -f "$BASE_DIR/$clean_ref" ]; then
                echo "  ❌ BROKEN in $(basename $file): $clean_ref"
                ((BROKEN++))
            fi
        fi
    done < <(grep -oP '`[^`]+\.md`' "$file" 2>/dev/null | tr -d '`')
done

echo ""
echo "================="
echo "Total refs checked: $TOTAL"
echo "Broken links: $BROKEN"

if [ $BROKEN -eq 0 ]; then
    echo ""
    echo "✅ All links valid!"
    exit 0
else
    echo ""
    echo "⚠️ Found $BROKEN broken links"
    exit 1
fi
