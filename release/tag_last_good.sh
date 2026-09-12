#!/usr/bin/env bash
# Фиксация last-good версии (тег + артефакт)
set -euo pipefail
cd "$(dirname "$0")/../.."

DRY_RUN=true
APPLY=false

# Парсинг аргументов
for arg in "$@"; do
    case "$arg" in
        --apply)
            APPLY=true
            DRY_RUN=false
            ;;
        --dry-run)
            DRY_RUN=true
            ;;
        *)
            echo "Неизвестный аргумент: $arg" >&2
            exit 1
            ;;
    esac
done

# Определяем путь к опубликованному HTML пульту (из логики publish_hub.sh)
HUB_NAME_FILE="data/hub_name.txt"
if [ ! -f "$HUB_NAME_FILE" ]; then
    echo "Ошибка: файл $HUB_NAME_FILE не найден" >&2
    exit 1
fi

HUB_NAME=$(cat "$HUB_NAME_FILE")
PUBLISHED_HTML="data/dashboard.html"

# Guard: проверка существования исходного HTML
if [ ! -f "$PUBLISHED_HTML" ]; then
    echo "Ошибка: исходный HTML файл $PUBLISHED_HTML отсутствует" >&2
    exit 1
fi

# Dry-run режим: печатаем шаги
if $DRY_RUN; then
    echo "=== DRY RUN ==="
    echo "Копируем: $PUBLISHED_HTML -> artifacts/last-good.html"
    echo "Тегируем коммит: $(git rev-parse HEAD) тегом last-good"
    echo "Пушим тег: git push --force-with-lease origin last-good"
    echo "=== КОНЕЦ DRY RUN ==="
    exit 0
fi

# Реальный режим с --apply
if $APPLY; then
    echo "Создаём artifacts/last-good.html..."
    mkdir -p artifacts
    cp "$PUBLISHED_HTML" artifacts/last-good.html
    
    echo "Создаём тег last-good..."
    git tag -f last-good HEAD
    git push --force-with-lease origin last-good
    
    echo "Готово: last-good зафиксирован"
    exit 0
fi

# По умолчанию ничего не делаем (только dry-run)
echo "Запустите с --dry-run для предварительного просмотра или --apply для выполнения"
exit 0
