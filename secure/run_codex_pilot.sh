#!/usr/bin/env bash
# Запускает codex_split.py с API-ключом из secrets/projects/openai.env
# без раскрытия значений ключей агенту.
#
# Использование: bash tools/secure/run_codex_pilot.sh <путь_к_скрипту>
set -euo pipefail

SCRIPT="${1:?Ошибка: укажи путь к скрипту}"
BASE="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="/root/workspaces/secrets/projects/openai.env"

[[ -f "$ENV_FILE" ]] || { echo "Ошибка: $ENV_FILE не найден" >&2; exit 1; }
[[ -f "$SCRIPT" ]] || { echo "Ошибка: скрипт не найден: $SCRIPT" >&2; exit 1; }

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

exec "$BASE/.venv/bin/python" "$SCRIPT"
