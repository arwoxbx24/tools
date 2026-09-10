#!/bin/bash
# Освобождает порт сервиса
# Usage: release-port.sh [service_name]

SERVICE_NAME="$1"
if [ -z "$SERVICE_NAME" ]; then
    echo "Usage: release-port.sh <service_name>"
    exit 1
fi

redis-cli -n 1 DEL "ports:allocated:$SERVICE_NAME" > /dev/null
echo "Port released for $SERVICE_NAME"
