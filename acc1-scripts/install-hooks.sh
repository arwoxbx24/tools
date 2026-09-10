#!/bin/bash
#
# Install Pre-commit Hooks
# Устанавливает unified code quality pipeline как pre-commit hook
#
# Usage:
#   ./install-hooks.sh <project_path>
#   ./install-hooks.sh /root/claude-projects/bitrix/sdk-php
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE_SCRIPT="$SCRIPT_DIR/code-quality-pipeline.sh"

# Проверка аргументов
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project_path>"
    echo ""
    echo "Examples:"
    echo "  $0 /root/claude-projects/bitrix/sdk-php"
    echo "  $0 .  # current directory"
    exit 1
fi

PROJECT_PATH="$1"

# Проверка что это git репозиторий
if [[ ! -d "$PROJECT_PATH/.git" ]]; then
    echo "❌ Not a git repository: $PROJECT_PATH"
    exit 1
fi

# Создать директорию hooks если нет
mkdir -p "$PROJECT_PATH/.git/hooks"

# Создать pre-commit hook
HOOK_FILE="$PROJECT_PATH/.git/hooks/pre-commit"

cat > "$HOOK_FILE" << 'EOF'
#!/bin/bash
#
# Pre-commit Hook — Unified Code Quality Pipeline
# Проверяет только staged файлы перед коммитом
#

PIPELINE="/root/workspaces/tools/acc1-scripts/scripts/code-quality-pipeline.sh"

# Проверка что pipeline существует
if [[ ! -x "$PIPELINE" ]]; then
    echo "⚠️ Code quality pipeline not found, skipping check"
    exit 0
fi

# Получить список staged файлов
STAGED=$(git diff --cached --name-only --diff-filter=ACMR)

if [[ -z "$STAGED" ]]; then
    # Нет файлов для проверки
    exit 0
fi

echo "🔍 Running code quality checks on staged files..."

# Запуск pipeline в режиме changed-only
if "$PIPELINE" . changed-only silent; then
    echo "✅ Code quality checks passed"
    exit 0
else
    echo ""
    echo "❌ Code quality checks failed!"
    echo ""
    echo "Fix the errors above or use --no-verify to skip:"
    echo "  git commit --no-verify -m 'message'"
    echo ""
    exit 1
fi
EOF

# Сделать исполняемым
chmod +x "$HOOK_FILE"

echo "✅ Pre-commit hook installed: $HOOK_FILE"
echo ""
echo "The hook will:"
echo "  1. Run PHPStan on staged .php files"
echo "  2. Run ESLint on staged .js/.ts files"
echo "  3. Block commit if errors found"
echo ""
echo "To skip hook: git commit --no-verify"
