#!/bin/bash
# Port Inventory Scanner — автоматический реестр всех портов
# Сканирует: UFW, Docker, PM2, конфиги, NPM, systemd
# Результат: Redis + JSON файл

set -e

REDIS_KEY="ports:inventory"
OUTPUT_FILE="/root/workspaces/tools/acc1-scripts/data/port-inventory.json"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/port-inventory.log"

mkdir -p "$(dirname "$OUTPUT_FILE")" "$(dirname "$LOG_FILE")"

echo "[$(date)] Starting port inventory scan..." | tee "$LOG_FILE"

# Временные файлы для сбора данных
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# 1. UFW порты
echo "Scanning UFW..." | tee -a "$LOG_FILE"
ufw status 2>/dev/null | grep -E "^[0-9]+" | while read line; do
    port=$(echo "$line" | awk '{print $1}' | grep -oE '^[0-9]+')
    [ -z "$port" ] && continue
    comment=$(echo "$line" | sed 's/.*#//' | xargs)
    echo "{\"port\":$port,\"source\":\"ufw\",\"comment\":\"$comment\"}"
done > "$TMP_DIR/ufw.json"

# 2. Docker контейнеры (все, включая остановленные)
echo "Scanning Docker..." | tee -a "$LOG_FILE"
docker ps -a --format "{{.Names}}|{{.Ports}}|{{.Status}}" 2>/dev/null | while IFS='|' read name ports status; do
    echo "$ports" | grep -oE '0\.0\.0\.0:[0-9]+' | while read p; do
        port=$(echo "$p" | grep -oE '[0-9]+$')
        echo "{\"port\":$port,\"source\":\"docker\",\"container\":\"$name\",\"status\":\"$status\"}"
    done
done > "$TMP_DIR/docker.json"

# 3. PM2 процессы
echo "Scanning PM2..." | tee -a "$LOG_FILE"
pm2 jlist 2>/dev/null | jq -r '.[] | "\(.name)|\(.pm2_env.PORT // "")|\(.pm2_env.status)"' | while IFS='|' read name port status; do
    [ -z "$port" ] && continue
    echo "{\"port\":$port,\"source\":\"pm2\",\"process\":\"$name\",\"status\":\"$status\"}"
done > "$TMP_DIR/pm2.json"

# 4. Docker-compose файлы
echo "Scanning docker-compose files..." | tee -a "$LOG_FILE"
find /root -name "docker-compose*.yml" -o -name "docker-compose*.yaml" 2>/dev/null | while read file; do
    grep -E '^\s*-\s*"?[0-9]+:' "$file" 2>/dev/null | while read line; do
        port=$(echo "$line" | grep -oE '[0-9]+:' | head -1 | tr -d ':')
        [ -z "$port" ] && continue
        echo "{\"port\":$port,\"source\":\"docker-compose\",\"file\":\"$file\"}"
    done
done > "$TMP_DIR/compose.json"

# 5. NPM Proxy Hosts
echo "Scanning NPM..." | tee -a "$LOG_FILE"
docker exec npm-app cat /data/nginx/proxy_host/*.conf 2>/dev/null | grep -oE 'proxy_pass[^;]+' | while read line; do
    port=$(echo "$line" | grep -oE ':[0-9]+' | tr -d ':')
    [ -z "$port" ] && continue
    echo "{\"port\":$port,\"source\":\"npm-proxy\"}"
done 2>/dev/null > "$TMP_DIR/npm.json"

# 6. Nginx конфиги
echo "Scanning Nginx..." | tee -a "$LOG_FILE"
find /etc/nginx -name "*.conf" 2>/dev/null | xargs grep -h "listen\|proxy_pass" 2>/dev/null | while read line; do
    port=$(echo "$line" | grep -oE ':[0-9]+|listen\s+[0-9]+' | grep -oE '[0-9]+')
    [ -z "$port" ] && continue
    echo "{\"port\":$port,\"source\":\"nginx\"}"
done > "$TMP_DIR/nginx.json"

# 7. Активно слушающие порты
echo "Scanning listening ports..." | tee -a "$LOG_FILE"
ss -tlnp 2>/dev/null | grep LISTEN | while read line; do
    port=$(echo "$line" | awk '{print $4}' | grep -oE '[0-9]+$')
    process=$(echo "$line" | grep -oE 'users:\("[^"]+' | tr -d 'users:("')
    [ -z "$port" ] && continue
    echo "{\"port\":$port,\"source\":\"listening\",\"process\":\"$process\"}"
done > "$TMP_DIR/listening.json"

# Объединяем все данные
echo "Building inventory..." | tee -a "$LOG_FILE"

# Собираем уникальные порты и их источники
cat "$TMP_DIR"/*.json 2>/dev/null | jq -s '
    group_by(.port) |
    map({
        port: .[0].port,
        sources: [.[] | {source: .source, details: (. | del(.port, .source))}],
        in_ufw: (map(select(.source == "ufw")) | length > 0),
        in_docker: (map(select(.source == "docker" or .source == "docker-compose")) | length > 0),
        in_pm2: (map(select(.source == "pm2")) | length > 0),
        is_listening: (map(select(.source == "listening")) | length > 0)
    }) |
    sort_by(.port)
' > "$OUTPUT_FILE"

# Находим сиротские порты (в UFW, но нигде больше)
ORPHANS=$(cat "$OUTPUT_FILE" | jq -r '.[] | select(.in_ufw == true and .in_docker == false and .in_pm2 == false and .is_listening == false) | .port')

# Сохраняем в Redis
echo "Saving to Redis..." | tee -a "$LOG_FILE"
redis-cli DEL "$REDIS_KEY" > /dev/null 2>&1
cat "$OUTPUT_FILE" | jq -c '.[]' | while read item; do
    port=$(echo "$item" | jq -r '.port')
    redis-cli HSET "$REDIS_KEY" "$port" "$item" > /dev/null 2>&1
done
redis-cli EXPIRE "$REDIS_KEY" 86400 > /dev/null 2>&1

# Сохраняем сиротские отдельно
redis-cli SET "ports:orphans" "$(echo $ORPHANS | tr '\n' ',')" EX 86400 > /dev/null 2>&1

# Статистика
TOTAL=$(cat "$OUTPUT_FILE" | jq 'length')
UFW_COUNT=$(cat "$OUTPUT_FILE" | jq '[.[] | select(.in_ufw == true)] | length')
ORPHAN_COUNT=$(echo "$ORPHANS" | wc -w)

echo "" | tee -a "$LOG_FILE"
echo "=== INVENTORY COMPLETE ===" | tee -a "$LOG_FILE"
echo "Total unique ports: $TOTAL" | tee -a "$LOG_FILE"
echo "Ports in UFW: $UFW_COUNT" | tee -a "$LOG_FILE"
echo "Orphan ports (UFW only, no service): $ORPHAN_COUNT" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Orphan ports:" | tee -a "$LOG_FILE"
echo "$ORPHANS" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full inventory: $OUTPUT_FILE" | tee -a "$LOG_FILE"
echo "Redis key: $REDIS_KEY" | tee -a "$LOG_FILE"
