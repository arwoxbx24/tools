#!/usr/bin/env bash
# Аварийный откат пульта БЕЗ пересборки: перепубликация artifacts/last-good.html
# Режим --dry-run по умолчанию; реальный режим только с --apply.
set -euo pipefail
cd "$(dirname "$0")/../.."

DRY_RUN=true
APPLY=false

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --apply)
            APPLY=true
            DRY_RUN=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            APPLY=false
            shift
            ;;
        *)
            echo "Неизвестный аргумент: $1" >&2
            exit 1
            ;;
    esac
done

# Guard: проверка наличия artifacts/last-good.html
if [ ! -f "artifacts/last-good.html" ]; then
    if [ "$APPLY" = true ]; then
        echo "❌ ОШИБКА: artifacts/last-good.html отсутствует" >&2
        echo "   Артефакт появится после первого успешного выполнения tag_last_good --apply" >&2
        exit 1
    else
        echo "⚠️  WARNING: artifacts/last-good.html отсутствует" >&2
        echo "   В реальном режиме это будет ошибкой" >&2
        exit 0
    fi
fi

# Режим --branch: создание новой ветки от тега last-good
if [ "$APPLY" = true ]; then
    echo "Создание ветки hotfix от тега last-good..."
    git switch -c "hotfix-$(date +%s)" last-good
else
    echo "[dry-run] Создана бы ветка: hotfix-$(date +%s) от тега last-good"
fi

# Перепубликация artifacts/last-good.html тем же механизмом, что и publish_hub.sh
if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Бэкап data/dashboard.html в data/dashboard.pre-rollback.html (если существует)"
    echo "[dry-run] Копирование artifacts/last-good.html в data/dashboard.html"
    echo "[dry-run] Выполнение механизма публикации из scripts/publish_hub.sh"
    echo "[dry-run] Файл был бы опубликован на тот же URL тем же каналом"
else
    echo "Бэкап текущего data/dashboard.html..."
    if [ -f "data/dashboard.html" ]; then
        cp data/dashboard.html data/dashboard.pre-rollback.html
    fi
    echo "Копирование artifacts/last-good.html в data/dashboard.html..."
    cp artifacts/last-good.html data/dashboard.html
    
    # Выполнение только шагов публикации из publish_hub.sh (без сборки и проверок)
    echo "Публикация через механизм scripts/publish_hub.sh..."
    
    # Динамический резолв IP MinIO
    _MINIO_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' minio 2>/dev/null | tr -d '[:space:]' || true)
    if [ -n "$_MINIO_IP" ]; then
        _MINIO_URL="http://${_MINIO_IP}:9000"
    else
        _MINIO_URL="https://io.b244.ru"
    fi
    _MC_CFG="${HOME}/.mc/config.json"
    if [ -f "$_MC_CFG" ] && command -v jq >/dev/null 2>&1; then
        jq --arg url "$_MINIO_URL" '.aliases.b244now.url = $url' "$_MC_CFG" > "${_MC_CFG}.tmp" \
            && mv "${_MC_CFG}.tmp" "$_MC_CFG" || rm -f "${_MC_CFG}.tmp"
    fi

    # Пропускаем шаги сборки и проверок, сразу к публикации
    echo "4/5 заливка..."
    HUB_NAME=$(cat data/hub_name.txt)
    mc cp --attr "Content-Type=text/html;Cache-Control=no-store, no-cache, must-revalidate" \
      data/dashboard.html "b244now/files/${HUB_NAME}" >/dev/null

    mc tag set "b244now/files/${HUB_NAME}" "permanent=true" >/dev/null

    echo "5/5 сверка через mc..."
    LOCAL_MD5=$(md5sum data/dashboard.html | cut -d' ' -f1)
    REMOTE_MD5=$(mc cat "b244now/files/${HUB_NAME}" 2>/dev/null | md5sum | cut -d' ' -f1)
    if [ "$LOCAL_MD5" != "$REMOTE_MD5" ]; then
        echo "❌ PUBLISH_MISMATCH: md5 локально=${LOCAL_MD5} бакет=${REMOTE_MD5}" >&2
        exit 1
    fi
    echo "✅ откат выполнен успешно, md5 ${LOCAL_MD5}"
fi
