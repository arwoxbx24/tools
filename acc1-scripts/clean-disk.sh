#!/bin/bash

BACKUP_DIR="/var/backups/docker-clean"
LOG_FILE="/var/log/clean-disk.log"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
CURRENT_BACKUP="$BACKUP_DIR/backup-$TIMESTAMP"
RECENT_BACKUP=$(ls -d $BACKUP_DIR/backup-* 2>/dev/null | tail -n 1)
MAX_BACKUPS=3

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" | tee -a "$LOG_FILE"
}

info() {
    log "[ИНФО] $1"
}

warning() {
    log "[ПРЕДУПРЕЖДЕНИЕ] $1"
}

error() {
    log "[ОШИБКА] $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "Пожалуйста, запустите скрипт с правами суперпользователя (sudo)."
        exit 1
    fi
}

clean_old_backups() {
    local backups=($(ls -d $BACKUP_DIR/backup-* 2>/dev/null | sort))
    local count=${#backups[@]}
    if [ "$count" -gt "$MAX_BACKUPS" ]; then
        local remove_count=$((count - MAX_BACKUPS))
        info "Удаление старых бэкапов (оставляем $MAX_BACKUPS из $count)..."
        for ((i=0; i<remove_count; i++)); do
            rm -rf "${backups[i]}"
            info "Удалён старый бэкап: ${backups[i]}"
        done
    fi
}

backup_before_cleanup() {
    info "Создание резервной копии в $CURRENT_BACKUP"
    mkdir -p "$CURRENT_BACKUP"

    docker ps -a > "$CURRENT_BACKUP/containers-list.txt"
    docker images > "$CURRENT_BACKUP/images-list.txt"
    docker volume ls > "$CURRENT_BACKUP/volumes-list.txt"
    docker network ls > "$CURRENT_BACKUP/networks-list.txt"

    mapfile -t exited_containers < <(docker ps -a -q -f status=exited)
    for cid in "${exited_containers[@]}"; do
        docker export "$cid" > "$CURRENT_BACKUP/container-${cid}.tar"
    done

    mapfile -t dangling_images < <(docker images -f "dangling=true" -q)
    for img in "${dangling_images[@]}"; do
        docker save "$img" > "$CURRENT_BACKUP/image-${img}.tar"
    done

    [ -f /etc/docker/daemon.json ] && cp /etc/docker/daemon.json "$CURRENT_BACKUP/"
    tar czf "$CURRENT_BACKUP/docker-logs.tar.gz" /var/lib/docker/containers/*/*-json.log 2>/dev/null || true

    info "Резервная копия завершена."
    clean_old_backups
}

recover_from_backup() {
    check_root
    if [ ! -d "$RECENT_BACKUP" ]; then
        error "Бэкап не найден в $BACKUP_DIR"
        exit 1
    fi

    info "Восстановление из $RECENT_BACKUP"

    if [ -f "$RECENT_BACKUP/daemon.json" ]; then
        cp "$RECENT_BACKUP/daemon.json" /etc/docker/daemon.json
        systemctl restart docker
        info "Файл конфигурации Docker восстановлен."
    fi

    for image_tar in "$RECENT_BACKUP"/image-*.tar; do
        [ -f "$image_tar" ] && docker load -i "$image_tar"
    done

    for container_tar in "$RECENT_BACKUP"/container-*.tar; do
        [ -f "$container_tar" ] && docker import "$container_tar"
    done

    info "Восстановление завершено."
    exit 0
}

dry_run_preview() {
    info "🔍 D R Y   R U N 🔍 — только просмотр, без удаления"
    docker system df

    echo -e "\n-- Список остановленных контейнеров:"
    docker ps -a -f status=exited

    echo -e "\n-- Список неиспользуемых образов:"
    docker images -f dangling=true

    echo -e "\n-- Список неиспользуемых томов:"
    docker volume ls -f dangling=true

    echo -e "\n-- Список старых логов Docker:"
    find /var/lib/docker/containers/ -type f -name "*-json.log" -size +10M

    echo -e "\n-- Временные файлы в /tmp старше 10 дней:"
    find /tmp -type f -atime +10

    echo -e "\n-- Журнал systemd старше 7 дней будет удалён"
    echo -e "\n✅ Для реального удаления запустите скрипт без --dry-run"
    exit 0
}

main_cleanup() {
    check_root
    backup_before_cleanup

    info "Очистка ресурсов Docker..."
    docker system prune -a --volumes -f

    info "Очистка логов Docker > 10MB..."
    find /var/lib/docker/containers/ -type f -name "*-json.log" -size +10M -exec truncate -s 0 {} \;

    info "Ограничение логов Docker..."
    daemon_json="/etc/docker/daemon.json"
    if [ -f "$daemon_json" ]; then
        if ! grep -q '"max-size":' "$daemon_json"; then
            cp "$daemon_json" "${daemon_json}.bak"
            jq '. + {"log-opts": {"max-size": "10m", "max-file": "3"}}' "$daemon_json" > tmp.$$.json && mv tmp.$$.json "$daemon_json"
            systemctl restart docker
        fi
    else
        cat <<EOF > "$daemon_json"
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
        systemctl restart docker
    fi

    info "Очистка systemd-журнала..."
    journalctl --vacuum-time=7d

    info "Очистка кэша и мусора..."
    apt-get clean
    apt-get autoremove -y
    find /tmp -type f -atime +10 -delete

    info "Очистка завершена. Бэкап: $CURRENT_BACKUP"
}

# ===== Обработка аргументов =====

case "$1" in
  --recovery)
    recover_from_backup
    ;;
  --dry-run)
    dry_run_preview
    ;;
  *)
    main_cleanup
    ;;
esac
