#!/bin/bash
# V080: FREE_PORT_ALLOCATOR — автоматический выбор свободного порта
# Usage: find-free-port.sh [service_name] [min_port] [max_port]

SERVICE_NAME="${1:-default}"
MIN_PORT="${2:-20000}"
MAX_PORT="${3:-30000}"
REDIS_DB=1

# Получить порт из Redis если уже выделен
EXISTING=$(redis-cli -n $REDIS_DB GET "ports:allocated:$SERVICE_NAME" 2>/dev/null)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "(nil)" ]; then
    # Проверить что порт свободен
    if ! ss -tlnp | grep -q ":$EXISTING "; then
        echo "$EXISTING"
        exit 0
    fi
fi

# Найти свободный порт
for PORT in $(seq $MIN_PORT $MAX_PORT); do
    # Проверить ss
    if ss -tlnp | grep -q ":$PORT "; then
        continue
    fi

    # Проверить Redis (не занят другим сервисом)
    TAKEN=$(redis-cli -n $REDIS_DB KEYS "ports:allocated:*" 2>/dev/null | \
            xargs -I{} redis-cli -n $REDIS_DB GET {} 2>/dev/null | \
            grep -w "$PORT")
    if [ -n "$TAKEN" ]; then
        continue
    fi

    # Выделить порт
    redis-cli -n $REDIS_DB SET "ports:allocated:$SERVICE_NAME" "$PORT" EX 604800 > /dev/null
    echo "$PORT"
    exit 0
done

echo "ERROR: No free port found in range $MIN_PORT-$MAX_PORT" >&2
exit 1
