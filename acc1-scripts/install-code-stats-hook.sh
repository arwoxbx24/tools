#!/bin/bash
# Installs post-commit hook for code stats tracking
# Run once per repository

HOOK_SOURCE="/root/workspaces/tools/acc1-scripts/hooks/post-commit-stats.sh"
HOOK_TARGET=".git/hooks/post-commit"

if [ ! -d ".git" ]; then
  echo "❌ Error: Not in a git repository"
  exit 1
fi

if [ -f "$HOOK_TARGET" ]; then
  # Append to existing hook
  echo "" >> "$HOOK_TARGET"
  echo "# Code stats tracking" >> "$HOOK_TARGET"
  echo "source $HOOK_SOURCE" >> "$HOOK_TARGET"
  echo "✅ Appended to existing post-commit hook"
else
  # Create new hook
  echo "#!/bin/bash" > "$HOOK_TARGET"
  echo "source $HOOK_SOURCE" >> "$HOOK_TARGET"
  chmod +x "$HOOK_TARGET"
  echo "✅ Created new post-commit hook"
fi
