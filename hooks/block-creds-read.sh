#!/usr/bin/env bash
# Блокирует чтение файлов с секретами через Read и Bash-инструменты агента.
#
# Инцидент 31.07: агент прочитал ~/.mc/config.json и напечатал ключи/секреты MinIO в лог.
# Этот хук закрывает механику: агент видит ИМЯ переменной, но не значение.
#
# Срабатывает на:
#   - Read tool: любой путь из списка секретных
#   - Bash tool: cat/less/head/tail/jq на секретных файлах
#
# Выход 2 = блок (агент видит сообщение из stderr), 0 = пропустить.

set -uo pipefail

# Читаем весь JSON один раз
INPUT_JSON="$(cat)"

TOOL_NAME="$(jq -r '.tool_name // ""' 2>/dev/null <<< "$INPUT_JSON" || echo "")"

_is_secret_path() {
    local path="$1"
    case "$path" in
        */.mc/config.json|\
        */data/notify.env|\
        */data/cabinet.env|\
        */data/hub_api.env|\
        */data/litestream.env|\
        */data/*.env|\
        */secrets/*|\
        */.env|\
        */.netrc|\
        */tokens*)
            return 0 ;;
    esac
    [[ "$path" == "/root/.mc/config.json" ]] && return 0
    return 1
}

_block() {
    cat >&2 <<'MSG'
ЗАБЛОКИРОВАНО: чтение файла с секретами запрещено.

Агент видит ИМЯ переменной/действия, но НЕ значение ключа.
Для действий с внешними сервисами используй обёртки:
  MinIO:  bash tools/secure/publish_page.sh <файл.html> <имя>
  B24:    tools/b24 <метод> <параметры>    (ключ в B24_WEBHOOK — только для демона)
  HH:     hhkit.send_message()             (токен читает hhkit, агенту не нужен)
  TG:     lib/tg_alerts.py                 (токен читает из data/notify.env сам модуль)
  Почта:  arwox-mail <кому> <тема> <файл-текста>   (глобальная обёртка отправки почты)

Если нужного действия нет — добавь обёртку в tools/secure/, не обходи это правило.
Документ: docs/CREDENTIALS-GUIDE.md
MSG
    exit 2
}



if [[ "$TOOL_NAME" == "Bash" ]]; then
    CMD="$(jq -r '.tool_input.command // ""' 2>/dev/null <<< "$INPUT_JSON" || echo "")"
    # Команды чтения на секретных файлах
    if echo "$CMD" | grep -qE '\b(cat|less|head|tail|jq)\b'; then
        # Проверяем вхождение паттернов секретных путей
        if echo "$CMD" | grep -qE '\.mc/config|data/(notify|cabinet|hub_api|litestream)\.env|data/[^/]+\.env|secrets/'; then
            _block
        fi
    fi
fi

exit 0
