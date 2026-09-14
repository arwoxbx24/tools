#!/usr/bin/env bash
# tools/llm-providers/git_agent.sh — git-рутина через провайдер-цепочку
#
# ИСПОЛЬЗОВАНИЕ:
#   git_agent.sh <режим> [файлы...]
#   git diff HEAD~1 | git_agent.sh <режим>
#
# РЕЖИМЫ:
#   commit-msg   — сообщение коммита по диффу (stdin или git diff HEAD)
#   branch-name  — имя ветки по описанию задачи (stdin = описание)
#   pr-text      — заголовок + тело PR по диффу (stdin или git diff HEAD)
#   review       — ревью диффа построчно (stdin или git diff HEAD)
#
# ПРИМЕРЫ:
#   git diff HEAD~1 | ./tools/llm-providers/git_agent.sh commit-msg
#   echo "добавить идемпотентный ключ для видеокомнат" | ./tools/llm-providers/git_agent.sh branch-name
#   git diff main...HEAD | ./tools/llm-providers/git_agent.sh review
#
# EXIT CODES:
#   0 — успех, нужная секция выведена в stdout
#   1 — ошибка аргументов или нет диффа
#   2 — все провайдеры исчерпаны
#   3 — YAML промпта не найден

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FAILOVER="/root/workspaces/tools/llm-providers/failover.sh"
PROMPT_YAML="$REPO_ROOT/prompts/openrouter_git_agent.yaml"

# --- Проверки ---
MODE="${1:-}"
if [[ -z "$MODE" ]]; then
  echo "ERROR: укажи режим: commit-msg | branch-name | pr-text | review" >&2
  exit 1
fi

case "$MODE" in
  commit-msg|branch-name|pr-text|review) ;;
  *)
    echo "ERROR: неизвестный режим '$MODE'. Допустимые: commit-msg | branch-name | pr-text | review" >&2
    exit 1
    ;;
esac

if [[ ! -f "$FAILOVER" ]]; then
  echo "ERROR: failover.sh не найден: $FAILOVER" >&2
  exit 2
fi

if [[ ! -f "$PROMPT_YAML" ]]; then
  echo "ERROR: промпт не найден: $PROMPT_YAML" >&2
  exit 3
fi

# --- Извлечь system_prompt из YAML ---
extract_system_prompt() {
  python3 - <<'PYEOF'
import sys, yaml, pathlib
y = yaml.safe_load(pathlib.Path("$PROMPT_YAML").read_text())
print(y.get("system_prompt", ""))
PYEOF
}

# Простой парсер: берём блок под ключом system_prompt:
SYSTEM_PROMPT=$(python3 -c "
import yaml, pathlib, sys
try:
    y = yaml.safe_load(pathlib.Path('$PROMPT_YAML').read_text())
    print(y.get('system_prompt', ''))
except Exception as e:
    print(f'ERROR parsing YAML: {e}', file=sys.stderr)
    sys.exit(3)
")

if [[ -z "$SYSTEM_PROMPT" ]]; then
  echo "ERROR: system_prompt пуст в $PROMPT_YAML" >&2
  exit 3
fi

# --- Получить диф / контекст ---
get_diff() {
  if [[ ! -t 0 ]]; then
    # Данные пришли через stdin
    cat
  else
    # Fallback: последний коммит
    git -C "$REPO_ROOT" diff HEAD~1 2>/dev/null || git -C "$REPO_ROOT" diff HEAD 2>/dev/null || echo ""
  fi
}

INPUT=$(get_diff)

if [[ -z "$INPUT" && "$MODE" != "branch-name" ]]; then
  echo "ERROR: нет данных на stdin и нет diff HEAD~1. Передай диф через pipe." >&2
  exit 1
fi

# --- Собрать промпт ---
case "$MODE" in
  commit-msg)
    TASK="Режим: commit-msg. Напиши сообщение коммита для следующего диффа. Оберни результат маркерами [BEGIN:COMMIT_MSG] и [END:COMMIT_MSG]."
    ;;
  branch-name)
    TASK="Режим: branch-name. По описанию задачи ниже придумай имя ветки формата task/<латиница>. Оберни результат маркерами [BEGIN:BRANCH] и [END:BRANCH]."
    ;;
  pr-text)
    TASK="Режим: pr-text. Напиши заголовок и тело PR для следующего диффа. Используй маркеры [BEGIN:PR_TITLE]/[END:PR_TITLE] и [BEGIN:PR_BODY]/[END:PR_BODY]."
    ;;
  review)
    TASK="Режим: review. Сделай построчное ревью диффа: file:line | проблема | фикс | severity BLOCK/WARN/NOTE. Оберни в [BEGIN:REVIEW] и [END:REVIEW]."
    ;;
esac

# Лимит диффа: берём первые 6000 символов, чтобы не перегружать контекст
INPUT_TRIMMED="${INPUT:0:6000}"
if [[ "${#INPUT}" -gt 6000 ]]; then
  INPUT_TRIMMED="${INPUT_TRIMMED}
[...диф обрезан, показано 6000 из ${#INPUT} символов...]"
fi

FULL_PROMPT="=== СИСТЕМНЫЕ ИНСТРУКЦИИ ===
${SYSTEM_PROMPT}

=== ЗАДАЧА ===
${TASK}

=== ДАННЫЕ (диф / описание) ===
${INPUT_TRIMMED}"

# --- Вызвать failover (review-режим → OpenRouter первым) ---
FAILOVER_ROLE="generate"
[[ "$MODE" == "review" ]] && FAILOVER_ROLE="review"
MAX_TOKENS=1200 RESULT=$(bash "$FAILOVER" --role "$FAILOVER_ROLE" "$FULL_PROMPT" 2>/tmp/git_agent_failover.log)
FAILOVER_RC=$?

if [[ $FAILOVER_RC -ne 0 ]]; then
  echo "ERROR: все провайдеры вернули ошибку (rc=$FAILOVER_RC). Лог: /tmp/git_agent_failover.log" >&2
  cat /tmp/git_agent_failover.log >&2
  exit 2
fi

# Определить активного провайдера из лога
PROVIDER=$(grep -oE 'FAILOVER [^ ]+ → [^ ]+' /tmp/git_agent_failover.log | tail -1 || true)
if [[ -z "$PROVIDER" ]]; then
  # Нет failover-записей — значит первый провайдер ответил
  PROVIDER=$(grep -oE 'kimi|codex|openrouter' /tmp/git_agent_failover.log | head -1 || echo "unknown")
fi

# --- Определить активного провайдера ---
detect_provider() {
  local log="$1"
  # Сначала смотрим [provider: NAME] метку — точная идентификация
  local prov_tag
  prov_tag=$(grep -oP '\[provider: \K[^ \]]+' "$log" | tail -1 || true)
  if [[ -n "$prov_tag" ]]; then
    echo "$prov_tag"
    return
  fi
  # Fallback: FAILOVER-строка — победил следующий провайдер
  local last_to
  last_to=$(grep -oP 'FAILOVER \S+ → \K\S+' "$log" | tail -1 || true)
  if [[ -n "$last_to" ]]; then
    echo "$last_to"
    return
  fi
  # Нет меток — угадываем по роли
  echo "unknown"
}

PROVIDER=$(detect_provider /tmp/git_agent_failover.log)

# --- Извлечь нужную секцию ---
extract_section() {
  local tag="$1"
  python3 -c "
import sys, re
text = sys.stdin.read()
# Берём последнее вхождение — оно содержит ответ модели, не пример из промпта
matches = list(re.finditer(r'\[BEGIN:${tag}\](.*?)\[END:${tag}\]', text, re.DOTALL))
if matches:
    print(matches[-1].group(1).strip())
else:
    # fallback: весь ответ без маркеров
    clean = re.sub(r'\[BEGIN:\w+\]|\[END:\w+\]', '', text)
    print(clean.strip())
" <<< "$RESULT"
}

echo ""
case "$MODE" in
  commit-msg)
    echo "# --- COMMIT MESSAGE (провайдер: $PROVIDER) ---"
    extract_section "COMMIT_MSG"
    ;;
  branch-name)
    echo "# --- BRANCH NAME (провайдер: $PROVIDER) ---"
    extract_section "BRANCH"
    ;;
  pr-text)
    echo "# --- PR TITLE (провайдер: $PROVIDER) ---"
    extract_section "PR_TITLE"
    echo ""
    echo "# --- PR BODY ---"
    extract_section "PR_BODY"
    ;;
  review)
    echo "# --- REVIEW (провайдер: $PROVIDER) ---"
    extract_section "REVIEW"
    ;;
esac
