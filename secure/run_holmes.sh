#!/usr/bin/env bash
# Запускает HolmesGPT CLI с API-ключом из secrets/services/openrouter.env
# без раскрытия значений ключей агенту.
#
# Usage: bash tools/secure/run_holmes.sh [holmes_args...]
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="/root/workspaces/secrets/services/openrouter.env"
HOLMES=/root/workspaces/projects/pilot-sandbox/holmesgpt/.venv/bin/holmes

[[ -f "$ENV_FILE" ]] || { echo "Ошибка: $ENV_FILE не найден" >&2; exit 1; }
[[ -x "$HOLMES" ]] || { echo "Ошибка: holmes не найден: $HOLMES" >&2; exit 1; }

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

export HOME=/root/workspaces/projects/pilot-sandbox/holmesgpt

exec "$HOLMES" "$@"
