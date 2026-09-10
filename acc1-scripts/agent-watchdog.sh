#!/bin/bash
# Agent Watchdog — автоматический kill зависших SUBAGENT'ов
# НЕ УБИВАЕТ интерактивные сессии (с TTY)
# Запуск: pm2 start agent-watchdog.sh --name agent-watchdog

LOG="/root/workspaces/tools/acc1-scripts/logs/agent-watchdog.log"
MAX_RUNTIME_MIN=120  # Максимум 2 часа для subagent'ов
CHECK_INTERVAL=60    # Проверка каждую минуту

mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

is_interactive() {
    local pid=$1
    # Проверяем наличие TTY — интерактивные сессии имеют pts/X
    local tty=$(ps -p $pid -o tty --no-headers 2>/dev/null | tr -d ' ')
    if [[ "$tty" != "?" && "$tty" != "" ]]; then
        return 0  # true - интерактивная
    fi
    return 1  # false - subagent
}

log "Watchdog started. Max runtime: ${MAX_RUNTIME_MIN}min (subagents only)"

while true; do
    ps -eo pid,etimes,comm --no-headers 2>/dev/null | grep -E "claude$" | while read PID SECONDS COMM; do
        MINUTES=$((SECONDS / 60))

        # Пропускаем короткие процессы
        if [ "$MINUTES" -lt 5 ]; then
            continue
        fi

        # КРИТИЧНО: НЕ трогаем интерактивные сессии
        if is_interactive $PID; then
            continue
        fi

        CPU=$(ps -p $PID -o %cpu --no-headers 2>/dev/null | tr -d ' ' | cut -d'.' -f1)

        if [ -z "$CPU" ]; then
            continue
        fi

        SHOULD_KILL=false
        REASON=""

        # Только subagent'ы с превышенным временем
        if [ "$MINUTES" -ge "$MAX_RUNTIME_MIN" ]; then
            SHOULD_KILL=true
            REASON="subagent runtime ${MINUTES}min > ${MAX_RUNTIME_MIN}min"
        fi

        # Zero CPU более 10 минут = завис
        if [ "$MINUTES" -ge 10 ] && [ "$CPU" = "0" ]; then
            SHOULD_KILL=true
            REASON="subagent zero CPU for ${MINUTES}min"
        fi

        if [ "$SHOULD_KILL" = true ]; then
            log "KILLING PID $PID: $REASON"
            kill -9 $PID 2>/dev/null
            if [ $? -eq 0 ]; then
                log "✅ Killed subagent PID $PID"
            else
                log "❌ Failed to kill PID $PID"
            fi
        fi
    done

    sleep $CHECK_INTERVAL
done
