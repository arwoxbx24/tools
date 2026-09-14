#!/usr/bin/env bash

set -euo pipefail

# Переходим в корень репозитория
cd "$(dirname "$(realpath "$0")")/../.." || exit 1

# Функция для показа справки
usage() {
    echo "Usage: $0 [--dry-run]"
    echo "  --dry-run    Показать действия без реального выполнения"
    exit 0
}

# Функция post_smoke (A3)
# Принимает обязательный аргумент: номер строки с которой начинать читать лог
post_smoke() {
    local log_offset="${1:-1}"
    echo "=== ПОСТ-СМОК ПРОВЕРКА ==="
    local failure_reason=""

    # Проверка 1: pm2 describe 81 содержит "online"
    if ! pm2 describe 81 2>/dev/null | grep -q "online"; then
        failure_reason="pm2 процесс 81 не в состоянии online"
    fi

    # Проверка 2: ждём "smoke: OK" в новых строках лога (только после деплоя)
    local log_file="/root/.pm2/logs/hh-pipeline-out.log"
    if [[ -f "$log_file" ]]; then
        local smoke_result=""
        local deadline=$((SECONDS + 120))
        echo "Ожидаем smoke OK/FAIL в логе с офсета ${log_offset} (таймаут 120с)..."
        while [[ $SECONDS -lt $deadline ]]; do
            local new_lines
            new_lines=$(tail -n +"${log_offset}" "$log_file" 2>/dev/null || true)
            if echo "$new_lines" | grep -q "smoke: OK"; then
                smoke_result="OK"
                echo "smoke: OK обнаружен в новых строках лога"
                break
            elif echo "$new_lines" | grep -q "smoke: FAIL"; then
                smoke_result="FAIL"
                echo "smoke: FAIL обнаружен в новых строках лога" >&2
                break
            fi
            sleep 5
        done
        if [[ "$smoke_result" != "OK" ]]; then
            failure_reason="${failure_reason}smoke check не прошёл (результат='${smoke_result:-timeout}', ждали 120с)"
        fi
    else
        failure_reason="${failure_reason}файл лога $log_file не существует"
    fi

    # Проверка 3: data/dashboard.html существует и >500000 байт
    local dashboard="data/dashboard.html"
    if [[ ! -f "$dashboard" ]]; then
        failure_reason="${failure_reason}файл $dashboard не существует"
    else
        local size
        size=$(stat -c%s "$dashboard" 2>/dev/null || wc -c < "$dashboard")
        if [[ ! $size -gt 500000 ]]; then
            failure_reason="${failure_reason}файл $dashboard имеет размер $size байт (требуется >500000)"
        fi
    fi

    if [[ -n "$failure_reason" ]]; then
        echo "ОШИБКА ПОСТ-СМОКА: $failure_reason" >&2
        echo "Запуск автоматического отката..."
        bash tools/release/rollback.sh --apply

        # Перезапись receipt status=rolled_back
        local receipt_file="data/deploy_receipt.json"
        if [[ -f "$receipt_file" ]]; then
            local tmp_receipt
            tmp_receipt=$(mktemp "${receipt_file}.tmp.XXXXXX")
            python3 -c "
import json
with open('${receipt_file}', 'r') as f:
    data = json.load(f)
data['status'] = 'rolled_back'
with open('${tmp_receipt}', 'w') as f:
    json.dump(data, f, indent=2)
import os
os.rename('${tmp_receipt}', '${receipt_file}')
"
            echo "Receipt обновлён: status=rolled_back"
        fi
        exit 1
    fi

    # Всё зелёное
    local prod_sha8=""
    if [[ -d "/root/workspaces/projects/hh-scoring-prod" ]]; then
        prod_sha8=$(git -C /root/workspaces/projects/hh-scoring-prod rev-parse --short=8 HEAD 2>/dev/null || echo "")
    fi
    echo "SHIP OK: прод=${prod_sha8}, смок PASS"

    # Обновление receipt status=ok
    local receipt_file="data/deploy_receipt.json"
    if [[ -f "$receipt_file" ]]; then
        local tmp_receipt
        tmp_receipt=$(mktemp "${receipt_file}.tmp.XXXXXX")
        python3 -c "
import json
with open('${receipt_file}', 'r') as f:
    data = json.load(f)
data['status'] = 'ok'
with open('${tmp_receipt}', 'w') as f:
    json.dump(data, f, indent=2)
import os
os.rename('${tmp_receipt}', '${receipt_file}')
"
    fi
}

# Парсим аргументы (как в rollback.sh)
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Неизвестный аргумент: $1"
            usage
            ;;
    esac
done

echo "=== STAGE-ГЕЙТ ПРОВЕРКА ==="

# 1. Определяем пути к файлам
HASH_FILE="data/publish_stage.hash"
DASHBOARD_FILE="data/dashboard-stage.html"

# 2. Проверяем наличие hash-файла (если не dry-run)
if [[ "$DRY_RUN" != "true" ]]; then
    if [[ ! -f "$HASH_FILE" ]]; then
        echo "ОШИБКА: Файл $HASH_FILE не найден" >&2
        exit 1
    fi

    # 3. Проверяем наличие dashboard-stage.html
    if [[ ! -f "$DASHBOARD_FILE" ]]; then
        echo "ОШИБКА: Файл $DASHBOARD_FILE не найден" >&2
        exit 1
    fi

    # 4. Проверяем возраст dashboard-stage.html (максимум 6 часов)
    CURRENT_TIME=$(date +%s)
    FILE_MTIME=$(stat -c %Y "$DASHBOARD_FILE")
    AGE_SECONDS=$((CURRENT_TIME - FILE_MTIME))
    MAX_AGE=$((6 * 60 * 60))  # 6 часов в секундах

    if [[ $AGE_SECONDS -gt $MAX_AGE ]]; then
        echo "ОШИБКА: Файл $DASHBOARD_FILE слишком старый (возраст: ${AGE_SECONDS}с, максимум: ${MAX_AGE}с)" >&2
        exit 1
    fi

    # 5. Читаем хэш
    STAGE_HASH=$(cat "$HASH_FILE")

    # 6. Всё зелёное - выводим OK
    echo "STAGE-ГЕЙТ OK (hash=${STAGE_HASH}, возраст=${AGE_SECONDS}с)"
else
    echo "[DRY-RUN] STAGE-ГЕЙТ пропускается (проверка файлов и возраста)"
fi

# --- A2: deploy step ---
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY-RUN] План выполнения:"
    echo "1. Запуск деплоя: bash scripts/deploy.sh --allow-send"
    echo "2. Замер:"
    echo "   - Получить prod_head: git -C /root/workspaces/projects/hh-scoring-prod rev-parse HEAD"
    echo "   - Проверить pm2 статус id 81: pm2 describe 81 | grep -c online"
    echo "3. Запись receipt: data/deploy_receipt.json"
    echo "   {commit: prod_head, ts: ISO, pm2_81: online|down, status: ok|fail}"
    echo "   (атомарно через python3 -c json.dump: tmp-файл + mv)"
    echo "4. Пост-смок: TODO: post-smoke (A3)"
    exit 0
else
    echo "=== ЗАПУСК ДЕПЛОЯ ==="
    # Фиксируем офсет лога ДО деплоя — post_smoke будет читать только новые строки
    LOG_FILE="/root/.pm2/logs/hh-pipeline-out.log"
    LOG_OFFSET=1
    if [[ -f "$LOG_FILE" ]]; then
        LOG_OFFSET=$(wc -l < "$LOG_FILE")
        LOG_OFFSET=$((LOG_OFFSET + 1))
    fi
    echo "Лог офсет до деплоя: ${LOG_OFFSET}"
    if ! bash scripts/deploy.sh --allow-send; then
        echo "ОШИБКА: Деплой завершился с ошибкой (rc≠0)" >&2
        exit 1
    fi
    
    echo "=== ЗАМЕР ПОСЛЕ ДЕПЛОЯ ==="
    PROD_HEAD=""
    if [[ -d "/root/workspaces/projects/hh-scoring-prod" ]]; then
        PROD_HEAD=$(git -C /root/workspaces/projects/hh-scoring-prod rev-parse HEAD 2>/dev/null || echo "")
    else
        echo "Предупреждение: директория /root/workspaces/projects/hh-scoring-prod не найдена" >&2
    fi
    
    PM2_STATUS="down"
    if pm2 describe 81 2>/dev/null | grep -q online; then
        PM2_STATUS="online"
    fi
    
    RECEIPT_FILE="data/deploy_receipt.json"
    TMP_RECEIPT=$(mktemp "${RECEIPT_FILE}.tmp.XXXXXX")
    
    python3 -c "
import json, datetime, os
data = {
    'commit': '${PROD_HEAD}',
    'ts': datetime.datetime.utcnow().isoformat() + 'Z',
    'pm2_81': '${PM2_STATUS}',
    'status': 'ok' if '${PM2_STATUS}' == 'online' else 'fail'
}
with open('${TMP_RECEIPT}', 'w') as f:
    json.dump(data, f, indent=2)
os.rename('${TMP_RECEIPT}', '${RECEIPT_FILE}')
"
    
    echo "Receipt записан в ${RECEIPT_FILE}"
    echo "=== ПОСТ-СМОК ==="
    post_smoke "${LOG_OFFSET}"
fi
