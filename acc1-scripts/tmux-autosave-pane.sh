#!/bin/bash
# Автосохранение tmux pane каждые 30 секунд в файл
# Запуск: bash /root/workspaces/tools/acc1-scripts/scripts/tmux-autosave-pane.sh &
LOGDIR="/root/claude-projects/.teamlead-agent/.tmp/pane-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/pane-$(date +%Y%m%d-%H%M%S).log"
echo "=== Pane log started $(date) ===" > "$LOGFILE"
while true; do
    tmux capture-pane -p -S -5000 >> "$LOGFILE" 2>/dev/null
    echo "=== SNAPSHOT $(date +%H:%M:%S) ===" >> "$LOGFILE"
    sleep 30
done
