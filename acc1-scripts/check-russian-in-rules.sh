#!/bin/bash
# V165: Check for Russian text in rules/prompts
# Rules and prompts MUST be in English only

DIRS=(
    "/root/workspaces/tools/acc1-scripts/reference"
    "/root/workspaces/tools/acc1-scripts/tests"
    "/root/workspaces/tools/acc1-scripts/skills"
)

FOUND=0

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        FILES=$(grep -r -l '[а-яА-ЯёЁ]' "$dir"/*.md 2>/dev/null)
        if [ -n "$FILES" ]; then
            echo "❌ Russian text found in:"
            echo "$FILES"
            FOUND=1
        fi
    fi
done

if [ $FOUND -eq 0 ]; then
    echo "✅ No Russian text in rules/prompts"
    exit 0
else
    echo ""
    echo "Run: grep -n '[а-яА-ЯёЁ]' <file> to see lines"
    exit 1
fi
