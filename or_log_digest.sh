#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/root/workspaces/projects/hh-scoring"
DB="$ROOT_DIR/data/screening.db"
OUT="$ROOT_DIR/data/or_digest_last.txt"

if [[ ! -f "$DB" ]]; then
  echo "ERROR: БД не найдена: $DB" >&2
  exit 1
fi

readonly_query="SELECT code, COUNT(*) AS count
FROM incidents
WHERE created_at >= datetime('now', '-1 day', 'localtime')
GROUP BY code
ORDER BY COUNT(*) DESC, code ASC;"

summary_file="$(mktemp)"
cleanup() {
  rm -f "$summary_file"
}
trap cleanup EXIT

sqlite3 -readonly "$DB" "$readonly_query" > "$summary_file"

if [[ ! -s "$summary_file" ]]; then
  {
    echo "Инциденты OR за последние 24ч: нет записей."
    echo "Всего записей: 0"
  } > "$summary_file"
fi

{
  echo "Сводка инцидентов (24ч):"
  cat "$summary_file" | awk '{ printf "%s ×%s\n", $1, $2 }'
} > "$OUT"

cat "$OUT"

if command -v bash >/dev/null 2>&1; then
  if [[ -x "$ROOT_DIR/tools/llm-providers/failover.sh" ]]; then
    FAILOVER="$ROOT_DIR/tools/llm-providers/failover.sh"
  elif [[ -x "/root/workspaces/tools/llm-providers/failover.sh" ]]; then
    FAILOVER="/root/workspaces/tools/llm-providers/failover.sh"
  else
    echo "ERROR: failover.sh не найден" >&2
    exit 1
  fi

  prompt="Найди паттерны/аномалии в сводке инцидентов. Выведи ровно 5 строк вывода, только по кодам инцидентов и их частоте."
  INPUT="$(cat "$OUT")"
  bash "$FAILOVER" --role analyze "$prompt" <<EOF_IN
$INPUT

$prompt
EOF_IN
else
  echo "ERROR: bash недоступен" >&2
  exit 1
fi
