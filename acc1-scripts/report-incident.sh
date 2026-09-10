#!/bin/bash
# report-incident.sh — Agent Incident Report System (AIRS)
# Creates structured incident reports when hooks block agent actions
# Usage: report-incident.sh <rule_code> <hook_name> <description> [blocked_command] [classification]
# classification: true_positive | false_positive | unknown (default: auto-detect)
# Called by blocking hooks before exit 2 (runs in background via &)
# Issue: #230

set +e

RULE="${1:-V000}"
HOOK="${2:-unknown}"
DESC="${3:-No description}"
BLOCKED_CMD="${4:-}"
CLASSIFICATION="${5:-auto}"

REPORTS_DIR="/root/workspaces/tools/acc1-scripts/agent-reports"
REDIS_DB=2
DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M:%S')
DATETIME=$(date '+%Y-%m-%d %H:%M:%S')
FILENAME_TS=$(date '+%Y-%m-%d-%H-%M')
SESSION_ID="${CLAUDE_SESSION_ID:-$(cat /tmp/.claude-session-id 2>/dev/null || echo 'unknown')}"

mkdir -p "$REPORTS_DIR"

# ── RATE LIMIT: 1 report per rule per minute ──
RATE_FILE="/tmp/.airs-rate-${RULE}"
if [ -f "$RATE_FILE" ]; then
    LAST_TS=$(cat "$RATE_FILE" 2>/dev/null || echo "0")
    NOW_TS=$(date +%s)
    DIFF=$((NOW_TS - LAST_TS))
    if [ "$DIFF" -lt 300 ]; then
        # Rate limit: 1 report per rule per 5 min — only count in Redis, skip file
        redis-cli -n $REDIS_DB INCR "acs:incident-count:${RULE}:${DATE}" >/dev/null 2>&1
        exit 0
    fi
fi
date +%s > "$RATE_FILE"

# ── ROOT CAUSE LOOKUP TABLE ──
RULE_NAME=""
ROOT_CAUSE=""
SUGGESTED_FIX=""
SEVERITY="MEDIUM"

case "$RULE" in
    V070)
        RULE_NAME="Tests Required"
        ROOT_CAUSE="Агент правит код или коммитит без запуска тестов. V070 требует тесты перед коммитом и предупреждает после 3+ правок без тестов."
        SUGGESTED_FIX="1) Запустить тесты проекта (pytest/phpunit/jest). 2) Проверить что агент включает тесты в план работ."
        SEVERITY="HIGH" ;;
    V020)
        RULE_NAME="File Sharing — b244.ru Only"
        ROOT_CAUSE="Агент выводит локальные пути файлов (/root/, /tmp/) в текстовый ответ. Пользователь удалённый и не может открыть локальные файлы."
        SUGGESTED_FIX="Усилить V020 в CLAUDE.md. Добавить примеры правильного поведения (share-file.sh → b244.ru ссылка)."
        SEVERITY="LOW" ;;
    V025)
        RULE_NAME="Directory Limits"
        ROOT_CAUSE="Агент пытается выйти за разрешённые директории (/root/claude-projects/, /root/workspaces/tools/acc1-scripts/, /tmp/claude-*/)."
        SUGGESTED_FIX="Проверить промпт агента — возможно запрос пользователя привёл к попытке доступа вне границ."
        SEVERITY="MEDIUM" ;;
    V101)
        RULE_NAME="PM2 Protection"
        ROOT_CAUSE="Агент пытается управлять PM2 напрямую (stop/delete/kill). Не знает о pm2-controlled-restart.sh обёртке."
        SUGGESTED_FIX="1) Усилить V101 в CLAUDE.md. 2) Добавить pm2-controlled-restart.sh в раздел Quick Commands."
        SEVERITY="HIGH" ;;
    V102)
        RULE_NAME="Opus Delegation Required"
        ROOT_CAUSE="Opus пишет код напрямую (Edit/Write .py/.js/.ts/.php/.go/.sh) вместо делегирования Sonnet."
        SUGGESTED_FIX="1) Проверить delegation counter. 2) Усилить V102 в промпте. 3) Проверить что Task tool доступен."
        SEVERITY="MEDIUM" ;;
    V109)
        RULE_NAME="Zero Questions Policy"
        ROOT_CAUSE="Агент задаёт вопросы пользователю (AskUserQuestion) вместо автономного решения. V109 запрещает любые вопросы."
        SUGGESTED_FIX="1) Усилить V109 behavioral override в CLAUDE.md. 2) Добавить больше примеров автономных решений."
        SEVERITY="LOW" ;;
    V113)
        RULE_NAME="Infrastructure Protection"
        ROOT_CAUSE="Агент модифицирует защищённые инфраструктурные файлы (docker-compose.yml, nginx.conf, .env) или выполняет docker-compose down/rm."
        SUGGESTED_FIX="1) Ограничить scope задачи. 2) Явно указать агенту что инфраструктура PROTECTED."
        SEVERITY="CRITICAL" ;;
    V120)
        RULE_NAME="Data Falsification Ban"
        ROOT_CAUSE="Агент пытается изменить данные валидации/статуса напрямую (UPDATE/INSERT для progress/status/count)."
        SUGGESTED_FIX="1) Проверить что агент понимает что данные readonly. 2) Усилить V120 в промпте."
        SEVERITY="CRITICAL" ;;
    V160)
        RULE_NAME="PE Code Ban"
        ROOT_CAUSE="Prompt Engineer роль пытается писать/редактировать код. В PE mode код запрещён (V160)."
        SUGGESTED_FIX="1) Проверить role detector (/tmp/.teamlead-agent-session). 2) Убедиться что PE работает только с документацией."
        SEVERITY="MEDIUM" ;;
    V162)
        RULE_NAME="Anti-Fabrication"
        ROOT_CAUSE="Агент выдумывает объяснения без проверки фактами. Представляет теории как факты. Экстраполирует из 1 случая на все. Заполняет пробелы фантазией."
        SUGGESTED_FIX="1) Усилить V162 в промпте. 2) Проверить что агент следует алгоритму: Evidence → Statement. 3) Добавить примеры правильного поведения в промпт."
        SEVERITY="CRITICAL" ;;
    V165)
        RULE_NAME="Mandatory Sonnet Delegation"
        ROOT_CAUSE="Task делегирован без model:sonnet. Правило V165 требует все кодовые задачи отправлять Sonnet (бюджет-оптимизация)."
        SUGGESTED_FIX="1) Усилить V165 в CLAUDE.md. 2) Рассмотреть auto-fix в хуке (подставлять model:sonnet)."
        SEVERITY="LOW" ;;
    V168)
        RULE_NAME="Rules Access Control"
        ROOT_CAUSE="Не-PE агент пытается редактировать hooks/reference/rules. Только PROMPT-ENGINEER может менять правила."
        SUGGESTED_FIX="Проверить role detector. Агент не должен пытаться менять системные файлы."
        SEVERITY="HIGH" ;;
    V169)
        RULE_NAME="Anti-Bypass Prohibition"
        ROOT_CAUSE="Агент пытается обойти проверку: отключить хук, подменить данные, использовать python -c вместо файла, обойти guard."
        SUGGESTED_FIX="КРИТИЧНО: 1) Логировать все bypass-попытки. 2) Усилить защиту хуков. 3) Проверить промпт на инструкции обхода."
        SEVERITY="CRITICAL" ;;
    V173)
        RULE_NAME="Consequence Awareness"
        ROOT_CAUSE="Агент пытается отправить внешнее сообщение (curl POST telegram/slack/webhook, sendmail)."
        SUGGESTED_FIX="1) Проверить что агент не имеет доступа к API-ключам. 2) Усилить V173 в промпте."
        SEVERITY="CRITICAL" ;;
    V180)
        RULE_NAME="Methodology Required"
        ROOT_CAUSE="Task делегирован без указания методологии (FMEA/Risk Matrix/Error-Triage/etc). Все задачи ОБЯЗАНЫ включать методологию."
        SUGGESTED_FIX="1) Добавить шаблон делегирования с полем Methodology. 2) Усилить примеры в CLAUDE.md."
        SEVERITY="MEDIUM" ;;
    V185)
        RULE_NAME="Secrets Search Path"
        ROOT_CAUSE="Агент ищет секреты (credentials, tokens, api keys) вне папки secrets/ или читает .env файлы вне secrets/."
        SUGGESTED_FIX="1) Проверить что агент знает путь /root/workspaces/secrets/. 2) Усилить V185 в промпте."
        SEVERITY="HIGH" ;;
    V191)
        RULE_NAME="Hierarchical Plans"
        ROOT_CAUSE="Агент создал плоский план для сложного проекта (complexity >= 6) без разбиения на подпланы. План обрезан или потерял детали."
        SUGGESTED_FIX="1) Усилить V191 в промпте. 2) Проверить что агент использует шаблон мастер-план + подпланы для сложных проектов."
        SEVERITY="LOW" ;;
    V189)
        RULE_NAME="Task Queue Management"
        ROOT_CAUSE="Агент создаёт слишком много задач не завершая текущие. Задачи зависают как in_progress/pending без TaskUpdate(completed)."
        SUGGESTED_FIX="1) Усилить V189 в промпте — ОБЯЗАТЕЛЬНО завершать задачи. 2) Проверить что агент вызывает TaskUpdate(completed) после работы."
        SEVERITY="MEDIUM" ;;
    *)
        RULE_NAME="Unknown Rule ($RULE)"
        ROOT_CAUSE="Правило $RULE не имеет описания в lookup-таблице. Требуется добавить root cause анализ."
        SUGGESTED_FIX="Добавить описание правила $RULE в report-incident.sh lookup-таблицу."
        SEVERITY="MEDIUM" ;;
esac

# ── AUTO-CLASSIFICATION ──
# Determines if incident is true_positive, false_positive, or unknown
# Heuristics based on rule + hook + command patterns
if [ "$CLASSIFICATION" = "auto" ]; then
    CLASSIFICATION="unknown"

    # ALWAYS true_positive: destructive actions, data falsification, messaging
    case "$RULE" in
        V120|V162) CLASSIFICATION="true_positive" ;;
        V113)
            # Docker rm/rmi/prune/stop/kill = TP. Read-only blocked = likely FP
            if echo "$BLOCKED_CMD" | grep -qE '\b(rm|rmi|prune|stop|kill|down)\b'; then
                CLASSIFICATION="true_positive"
            fi ;;
        V173)
            # Actual messaging URLs = TP
            if echo "$BLOCKED_CMD" | grep -qEi '(telegram|slack|discord|webhook|sendmail)'; then
                CLASSIFICATION="true_positive"
            fi ;;
        V169)
            # Bash comment triggered detection = FP (safety net for any remaining)
            if echo "$BLOCKED_CMD" | grep -qE '^\s*#'; then
                CLASSIFICATION="false_positive"
            fi
            # cp/mv to tests/ or /tmp/ = FP
            if echo "$BLOCKED_CMD" | grep -qE '\b(cp|mv)\b.*(/tests?/|/tmp/)'; then
                CLASSIFICATION="false_positive"
            fi ;;
        V025)
            # Read-only commands to protected dirs = likely FP (diagnostics)
            if echo "$BLOCKED_CMD" | grep -qE '\b(cat|tail|head|grep|less|ls|stat|file|wc)\b'; then
                CLASSIFICATION="false_positive"
            fi ;;
        V102)
            # Opus writing code = always TP (should delegate)
            CLASSIFICATION="true_positive" ;;
    esac
fi

# ── CLASSIFICATION REDIS COUNTERS ──
redis-cli -n $REDIS_DB INCR "acs:class:${CLASSIFICATION}:${DATE}" >/dev/null 2>&1
redis-cli -n $REDIS_DB EXPIRE "acs:class:${CLASSIFICATION}:${DATE}" 604800 >/dev/null 2>&1
# Per-rule classification counter
redis-cli -n $REDIS_DB INCR "acs:class:${RULE}:${CLASSIFICATION}:${DATE}" >/dev/null 2>&1
redis-cli -n $REDIS_DB EXPIRE "acs:class:${RULE}:${CLASSIFICATION}:${DATE}" 604800 >/dev/null 2>&1

# ── FREQUENCY CHECK ──
TODAY_COUNT=$(redis-cli -n $REDIS_DB INCR "acs:incident-count:${RULE}:${DATE}" 2>/dev/null || echo "1")
redis-cli -n $REDIS_DB EXPIRE "acs:incident-count:${RULE}:${DATE}" 604800 >/dev/null 2>&1

# Check last 7 days
WEEK_TOTAL=0
for i in $(seq 0 6); do
    D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    CNT=$(redis-cli -n $REDIS_DB GET "acs:incident-count:${RULE}:${D}" 2>/dev/null || echo "0")
    [ -z "$CNT" ] && CNT=0
    WEEK_TOTAL=$((WEEK_TOTAL + CNT))
done

# Determine trend
PREV_WEEK=0
for i in $(seq 7 13); do
    D=$(date -d "-${i} days" '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')
    CNT=$(redis-cli -n $REDIS_DB GET "acs:incident-count:${RULE}:${D}" 2>/dev/null || echo "0")
    [ -z "$CNT" ] && CNT=0
    PREV_WEEK=$((PREV_WEEK + CNT))
done

if [ "$WEEK_TOTAL" -gt "$((PREV_WEEK + 3))" ]; then
    TREND="РАСТЁТ"
elif [ "$WEEK_TOTAL" -lt "$((PREV_WEEK - 3))" ]; then
    TREND="СНИЖАЕТСЯ"
else
    TREND="СТАБИЛЬНО"
fi

# ── SEVERITY → RPN ──
case "$SEVERITY" in
    CRITICAL) SEV_NUM=5 ;;
    HIGH) SEV_NUM=4 ;;
    MEDIUM) SEV_NUM=3 ;;
    LOW) SEV_NUM=2 ;;
    *) SEV_NUM=1 ;;
esac

if [ "$TODAY_COUNT" -gt 5 ]; then FREQ_NUM=5
elif [ "$TODAY_COUNT" -gt 2 ]; then FREQ_NUM=3
else FREQ_NUM=1; fi

RPN=$((SEV_NUM * FREQ_NUM))

# ── GENERATE REPORT FILE ──
REPORT_FILE="${REPORTS_DIR}/${FILENAME_TS}-${RULE}-${HOOK}.md"

cat > "$REPORT_FILE" << REPORT_EOF
# Incident Report: ${RULE} — ${RULE_NAME}

## Метаданные
| Поле | Значение |
|------|----------|
| Дата | ${DATETIME} |
| Правило | ${RULE} — ${RULE_NAME} |
| Хук | ${HOOK} |
| Сессия | ${SESSION_ID:0:12}... |
| Серьёзность | ${SEVERITY} |
| Классификация | ${CLASSIFICATION} |

## 1. Что произошло
Агент заблокирован хуком \`${HOOK}\`.
Описание: ${DESC}
Команда: \`$(echo "$BLOCKED_CMD" | head -c 300)\`

## 2. Почему это произошло (Root Cause)
${ROOT_CAUSE}

## 3. Частота и тренд
- Сегодня: ${TODAY_COUNT} раз (${RULE})
- За 7 дней: ${WEEK_TOTAL} раз
- Предыдущие 7 дней: ${PREV_WEEK} раз
- Тренд: **${TREND}**

## 4. Предложение по исправлению
${SUGGESTED_FIX}

## 5. Оценка рисков
| Метрика | Значение |
|---------|----------|
| Серьёзность | ${SEVERITY} (${SEV_NUM}/5) |
| Частота | ${TODAY_COUNT} сегодня |
| RPN | ${RPN} |
| Тренд | ${TREND} |
REPORT_EOF

# ── LOG TO REDIS ──
INCIDENT_ENTRY="${TIME}|${RULE}|${HOOK}|${SEVERITY}|${CLASSIFICATION}|${DESC}"
redis-cli -n $REDIS_DB RPUSH "acs:incidents:${DATE}" "$INCIDENT_ENTRY" >/dev/null 2>&1
redis-cli -n $REDIS_DB EXPIRE "acs:incidents:${DATE}" 2592000 >/dev/null 2>&1

# ── THRESHOLD ALERT (Variant C) ──
# Creates alert file when incidents cross threshold.
# health-check.sh reads this at session start (Variant A).
# Priority: CRITICAL > HIGH. Never overwrite CRITICAL with HIGH.
AIRS_ALERT_FILE="/root/workspaces/tools/acc1-scripts/data/airs-alert.txt"
AIRS_NEW_ALERT=""
if [ "$SEVERITY" = "CRITICAL" ] && [ "$TODAY_COUNT" -ge 3 ]; then
    AIRS_NEW_ALERT="${DATE}|CRITICAL: ${RULE} (${RULE_NAME}) — ${TODAY_COUNT} incidents today, trend: ${TREND}"
elif [ "$TODAY_COUNT" -ge 10 ]; then
    AIRS_NEW_ALERT="${DATE}|HIGH: ${RULE} (${RULE_NAME}) — ${TODAY_COUNT} incidents today, trend: ${TREND}"
fi
if [ -n "$AIRS_NEW_ALERT" ]; then
    if [ -f "$AIRS_ALERT_FILE" ] && grep -q "|CRITICAL:" "$AIRS_ALERT_FILE" 2>/dev/null && echo "$AIRS_NEW_ALERT" | grep -q "|HIGH:"; then
        : # Keep existing CRITICAL, don't downgrade to HIGH
    else
        echo "$AIRS_NEW_ALERT" > "$AIRS_ALERT_FILE"
    fi
fi

exit 0
