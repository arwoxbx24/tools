#!/bin/bash
# ============================================================================
# hooks-killswitch.sh — Аварийный рубильник хуков
# Временно отключает опасные хуки чтобы не парализовать работу
#
# Использование:
#   bash hooks-killswitch.sh off PASSPHRASE   — ВЫКЛЮЧИТЬ опасные хуки
#   bash hooks-killswitch.sh on PASSPHRASE    — ВКЛЮЧИТЬ обратно
#   bash hooks-killswitch.sh status           — Показать состояние (без пароля)
#
# Безопасные хуки (защита IP, PM2, credentials) НЕ ТРОГАЕТ
# ДОСТУП: Только Opus Expert агенты (пароль в CLAUDE.md Expert аккаунта)
# ============================================================================

set +e

HOOKS_DIR="/root/workspaces/tools/acc1-scripts/hooks"
KILLSWITCH_KEY="9deff5cb5a97cd65"

# Проверка пароля для off/on команд
check_auth() {
    local provided_key="$1"
    if [[ "$provided_key" != "$KILLSWITCH_KEY" ]]; then
        echo "============================================" >&2
        echo "  ⛔ ДОСТУП ЗАПРЕЩЁН" >&2
        echo "  Рубильник доступен только Opus Expert" >&2
        echo "  Требуется: bash $0 {off|on} PASSPHRASE" >&2
        echo "============================================" >&2
        exit 2
    fi
}

# Опасные хуки — те что блокируют Write/Edit и могут парализовать работу
DANGEROUS_HOOKS=(
    "enforce-v102-delegation.sh"
    "enforce-sonnet-delegation.sh"
    "enforce-generator-only.sh"
    "enforce-xml-tags.sh"
    "enforce-xml-tags-wrapper.sh"
    "enforce-web-integrity.sh"
    "enforce-template-system.sh"
    "enforce-zero-error.sh"
    "enforce-delegation.sh"
    "block-without-issue.sh"
    "block-non-prompteng-rules-access.sh"
    "enforce-scaffold.sh"
    "enforce-github-issue.sh"
    "v142-task-blocker.sh"
    "validate-requirements.sh"
    "enforce-task-model.sh"
    "enforce-oom-protection.sh"
    "enforce-delegation-counter.sh"
    "enforce-tool-budget.sh"
    "auto-brainstorm.sh"
    "enforce-fix-loop-detection.sh"
    "enforce-session-init.sh"
    "frustration-stop-guard.sh"
    "frustration-detector.sh"
    "enforce-project-context-read.sh"
)

ACTION="${1:-status}"
AUTH_KEY="${2:-}"

case "$ACTION" in
    off|OFF|0)
        check_auth "$AUTH_KEY"
        echo "============================================" >&2
        echo "  РУБИЛЬНИК: ВЫКЛЮЧАЮ опасные хуки" >&2
        echo "============================================" >&2
        disabled=0
        for hook in "${DANGEROUS_HOOKS[@]}"; do
            if [ -f "$HOOKS_DIR/$hook" ]; then
                mv "$HOOKS_DIR/$hook" "$HOOKS_DIR/$hook.disabled"
                echo "  OFF: $hook" >&2
                disabled=$((disabled + 1))
            fi
        done
        echo "--------------------------------------------" >&2
        echo "  Отключено: $disabled хуков" >&2
        echo "  Безопасные хуки — работают" >&2
        echo "  Включить обратно: bash $0 on" >&2
        echo "============================================" >&2
        ;;

    on|ON|1)
        check_auth "$AUTH_KEY"
        echo "============================================" >&2
        echo "  РУБИЛЬНИК: ВКЛЮЧАЮ хуки обратно" >&2
        echo "============================================" >&2
        enabled=0
        for hook in "${DANGEROUS_HOOKS[@]}"; do
            if [ -f "$HOOKS_DIR/$hook.disabled" ]; then
                mv "$HOOKS_DIR/$hook.disabled" "$HOOKS_DIR/$hook"
                echo "  ON:  $hook" >&2
                enabled=$((enabled + 1))
            fi
        done
        echo "--------------------------------------------" >&2
        echo "  Включено: $enabled хуков" >&2
        echo "============================================" >&2
        ;;

    status|STATUS|s)
        echo "============================================" >&2
        echo "  РУБИЛЬНИК: Состояние хуков" >&2
        echo "============================================" >&2
        on_count=0
        off_count=0
        for hook in "${DANGEROUS_HOOKS[@]}"; do
            if [ -f "$HOOKS_DIR/$hook" ]; then
                echo "  ON:  $hook" >&2
                on_count=$((on_count + 1))
            elif [ -f "$HOOKS_DIR/$hook.disabled" ]; then
                echo "  OFF: $hook" >&2
                off_count=$((off_count + 1))
            else
                echo "  ???: $hook (не найден)" >&2
            fi
        done
        echo "--------------------------------------------" >&2
        echo "  Включено: $on_count | Выключено: $off_count" >&2
        if [ $off_count -gt 0 ]; then
            echo "  ⚠️  РЕЖИМ ОБСЛУЖИВАНИЯ — часть хуков OFF" >&2
        else
            echo "  Все хуки активны" >&2
        fi
        echo "============================================" >&2
        ;;

    *)
        echo "Использование: $0 {off|on|status}" >&2
        echo "  off    — выключить опасные хуки" >&2
        echo "  on     — включить обратно" >&2
        echo "  status — показать состояние" >&2
        exit 1
        ;;
esac

exit 0
