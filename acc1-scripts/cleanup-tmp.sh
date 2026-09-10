#!/bin/bash
# Автоочистка .tmp папки - удаляет файлы и папки старше 2 часов
TMP_DIR="/root/claude-projects/.tmp"
LOG="/root/workspaces/tools/acc1-scripts/logs/cleanup.log"

if [ -d "$TMP_DIR" ]; then
    # Удаляем файлы старше 2 часов
    files=$(find "$TMP_DIR" -type f -mmin +120 2>/dev/null | wc -l)
    find "$TMP_DIR" -type f -mmin +120 -delete 2>/dev/null
    
    # Удаляем пустые папки старше 2 часов
    dirs=$(find "$TMP_DIR" -mindepth 1 -type d -mmin +120 2>/dev/null | wc -l)
    find "$TMP_DIR" -mindepth 1 -type d -mmin +120 -empty -delete 2>/dev/null
    
    if [ "$files" -gt 0 ] || [ "$dirs" -gt 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Удалено: $files файлов, $dirs папок (старше 2ч)" >> "$LOG"
    fi
fi
