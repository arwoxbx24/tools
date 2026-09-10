#!/bin/bash
# GLOBAL PHP Code Validator
# Works with ANY PHP project
# MANDATORY: Run before claiming "done"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            AGENT CODE VALIDATION SYSTEM                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Auto-detect project type
detect_project() {
    if [ -f "composer.json" ]; then
        echo "php-composer"
    elif [ -f "package.json" ]; then
        echo "nodejs"
    elif [ -f "requirements.txt" ]; then
        echo "python"
    else
        echo "generic"
    fi
}

PROJECT_TYPE=$(detect_project)
echo "📁 Project type: $PROJECT_TYPE"
echo "📂 Working dir:  $(pwd)"

# Find changed PHP files
CHANGED=$(git diff --name-only HEAD~1 -- "*.php" 2>/dev/null || true)
[ -z "$CHANGED" ] && CHANGED=$(git diff --cached --name-only -- "*.php" 2>/dev/null || true)
[ -z "$CHANGED" ] && CHANGED=$(git status --porcelain 2>/dev/null | grep "\.php$" | awk '{print $2}' || true)

if [ -z "$CHANGED" ]; then
    echo ""
    echo "⚠️ No PHP changes detected"
    echo "✅ VALIDATION SKIPPED — No PHP files to check"
    exit 0
fi

FILE_COUNT=$(echo "$CHANGED" | wc -l)
echo "📝 Changed files: $FILE_COUNT"
echo ""

ERRORS=0
WARNINGS=0

# ═══════════════════════════════════════════════════════════════
# Level 1: Syntax check (php -l)
# ═══════════════════════════════════════════════════════════════
echo "[1/6] Syntax check (php -l)..."
SYNTAX_ERRORS=0
for f in $CHANGED; do
    if [ -f "$f" ]; then
        if ! php -l "$f" > /dev/null 2>&1; then
            echo "  ❌ $f"
            php -l "$f" 2>&1 | grep -v "^$" | head -3 | sed 's/^/     /'
            SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
        fi
    fi
done
if [ $SYNTAX_ERRORS -eq 0 ]; then
    echo "  ✅ OK"
else
    echo "  ❌ FAILED: $SYNTAX_ERRORS syntax errors"
    ERRORS=$((ERRORS + SYNTAX_ERRORS))
fi

# ═══════════════════════════════════════════════════════════════
# Level 2: Static analysis (PHPStan)
# ═══════════════════════════════════════════════════════════════
echo ""
echo "[2/6] Static analysis (PHPStan level 5)..."
PHPSTAN_CMD=""
if [ -f "vendor/bin/phpstan" ]; then
    PHPSTAN_CMD="vendor/bin/phpstan"
elif command -v phpstan &> /dev/null; then
    PHPSTAN_CMD="phpstan"
elif [ -f "$HOME/.composer/vendor/bin/phpstan" ]; then
    PHPSTAN_CMD="$HOME/.composer/vendor/bin/phpstan"
elif [ -f "$HOME/.config/composer/vendor/bin/phpstan" ]; then
    PHPSTAN_CMD="$HOME/.config/composer/vendor/bin/phpstan"
fi

if [ -n "$PHPSTAN_CMD" ]; then
    # Create temp file list
    echo "$CHANGED" > /tmp/phpstan_files.txt

    # V027: Resource limits mandatory - prevent 100% CPU
    if timeout 300 $PHPSTAN_CMD analyse $CHANGED --level=5 --no-progress --processes=1 --memory-limit=256M 2>/dev/null; then
        echo "  ✅ OK"
    else
        echo ""
        echo "  ❌ FAILED: PHPStan found errors"
        ERRORS=$((ERRORS + 1))
    fi
    rm -f /tmp/phpstan_files.txt
else
    echo "  ❌ FAIL: PHPStan not installed"
    echo "  💡 Install: composer require --dev phpstan/phpstan"
    echo "  💡 Or global: composer global require phpstan/phpstan"
    ERRORS=$((ERRORS + 1))
fi

# ═══════════════════════════════════════════════════════════════
# Level 3: Dependencies (composer validate)
# ═══════════════════════════════════════════════════════════════
echo ""
echo "[3/6] Dependencies (composer validate)..."
if [ -f "composer.json" ]; then
    if composer validate --no-check-all --no-check-publish --quiet 2>/dev/null; then
        echo "  ✅ OK"
    else
        echo "  ❌ FAILED: composer.json invalid"
        composer validate --no-check-all --no-check-publish 2>&1 | head -5 | sed 's/^/     /'
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  ⚠️ SKIP: No composer.json"
fi

# ═══════════════════════════════════════════════════════════════
# Level 4: Autoload test
# ═══════════════════════════════════════════════════════════════
echo ""
echo "[4/6] Autoload test..."
if [ -f "vendor/autoload.php" ]; then
    if php -r "require 'vendor/autoload.php';" 2>/dev/null; then
        echo "  ✅ OK"
    else
        echo "  ❌ FAILED: Autoload error"
        php -r "require 'vendor/autoload.php';" 2>&1 | head -5 | sed 's/^/     /'
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  ⚠️ SKIP: No vendor/autoload.php"
fi

# ═══════════════════════════════════════════════════════════════
# Level 5: Test run (if command provided)
# ═══════════════════════════════════════════════════════════════
echo ""
echo "[5/6] Test run..."
if [ -n "$1" ]; then
    echo "  Command: $1"
    echo "  ─────────────────────────────────────────"
    if eval "$1" 2>&1 | head -20 | sed 's/^/  /'; then
        echo "  ─────────────────────────────────────────"
        echo "  ✅ OK"
    else
        echo "  ─────────────────────────────────────────"
        echo "  ❌ FAILED: Command returned error"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo "  ⚠️ SKIP: No test command provided"
    echo "  💡 Usage: validate-code.sh 'php bin/cmd --dry-run'"
fi

# ═══════════════════════════════════════════════════════════════
# Level 6: Output validation
# ═══════════════════════════════════════════════════════════════
echo ""
echo "[6/6] Output validation..."
echo "  ⚠️ Manual check required by agent"

# ═══════════════════════════════════════════════════════════════
# FINAL RESULT
# ═══════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -gt 0 ]; then
        echo "⚠️ VALIDATION PASSED WITH WARNINGS ($WARNINGS)"
        echo ""
        echo "✅ Agent CAN claim DONE (but review warnings)"
    else
        echo "✅ VALIDATION PASSED — All checks OK"
        echo ""
        echo "✅ Agent CAN claim DONE"
    fi
    exit 0
else
    echo "❌ VALIDATION FAILED — $ERRORS error(s) found"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  🛑 AGENT CANNOT CLAIM 'DONE'                                ║"
    echo "║                                                              ║"
    echo "║  Fix all errors above and run validation again:             ║"
    echo "║  /root/workspaces/tools/acc1-scripts/scripts/validate-code.sh             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    exit 1
fi
