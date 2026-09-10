#!/bin/bash
# Pre-commit hook - Auto-run validation before commit
# Install: ln -sf /root/workspaces/tools/acc1-scripts/scripts/pre-commit-hook.sh .git/hooks/pre-commit

echo "🔍 Running pre-commit validation..."
echo ""

# Call global validator
/root/workspaces/tools/acc1-scripts/scripts/validate-code.sh

EXIT_CODE=$?

# Block commit if validation failed
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🛑 COMMIT BLOCKED                                           ║"
    echo "║                                                              ║"
    echo "║  Fix validation errors before committing!                   ║"
    echo "║                                                              ║"
    echo "║  To bypass (NOT RECOMMENDED):                               ║"
    echo "║  git commit --no-verify                                     ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    exit 1
fi

echo ""
echo "✅ Pre-commit validation passed"
exit 0
