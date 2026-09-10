#!/bin/bash
# PM2 Report Generator - multiple formats
# Usage: pm2-report.sh [format]
# Formats: summary, memory, cpu, restarts, categories, all

FORMAT="${1:-summary}"

report_header() {
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    printf "║  📊 %-72s ║\n" "$1"
    echo "╚══════════════════════════════════════════════════════════════════════════════╝"
    echo ""
}

report_summary() {
    report_header "СВОДНЫЙ ОТЧЁТ PM2 — $(date '+%H:%M:%S')"
    
    TOTAL=$(pm2 jlist | jq 'length')
    ONLINE=$(pm2 jlist | jq '[.[] | select(.pm2_env.status == "online")] | length')
    TOTAL_MEM=$(pm2 jlist | jq '[.[].monit.memory] | add')
    TOTAL_MB=$(echo "scale=0; $TOTAL_MEM / 1024 / 1024" | bc)
    RESTARTS=$(pm2 jlist | jq '[.[].pm2_env.restart_time] | add')
    
    echo "┌───────────────┬───────────────┬───────────────┬───────────────┐"
    echo "│  Процессов    │   Online      │  Память PM2   │   Рестарты    │"
    echo "├───────────────┼───────────────┼───────────────┼───────────────┤"
    printf "│      %2s       │      %2s       │    %4s MB    │      %2s       │\n" "$TOTAL" "$ONLINE" "$TOTAL_MB" "$RESTARTS"
    echo "└───────────────┴───────────────┴───────────────┴───────────────┘"
}

report_memory() {
    report_header "TOP ПО ПАМЯТИ"
    pm2 jlist | jq -r 'sort_by(-.monit.memory) | .[] | "\(.monit.memory)\t\(.name)"' | while read mem name; do
        mem_mb=$(echo "scale=1; $mem / 1024 / 1024" | bc)
        bar_len=$(echo "$mem_mb / 5" | bc)
        bar=$(printf '█%.0s' $(seq 1 $bar_len 2>/dev/null) || echo "▏")
        printf "%-25s %7s MB  %s\n" "$name" "$mem_mb" "$bar"
    done
}

report_categories() {
    report_header "КАТЕГОРИИ ПРОЦЕССОВ"
    APP_MEM=0; MON_MEM=0; SCHED_MEM=0
    while IFS='|' read name mem; do
        case "$name" in
            sched-*) SCHED_MEM=$((SCHED_MEM + mem)) ;;
            *exporter*|prometheus|pm2-conductor) MON_MEM=$((MON_MEM + mem)) ;;
            *) APP_MEM=$((APP_MEM + mem)) ;;
        esac
    done < <(pm2 jlist | jq -r '.[] | "\(.name)|\(.monit.memory)"')
    
    echo "🔷 Приложения:   $(echo "scale=1; $APP_MEM / 1024 / 1024" | bc) MB"
    echo "📈 Мониторинг:   $(echo "scale=1; $MON_MEM / 1024 / 1024" | bc) MB"
    echo "⏰ Планировщики: $(echo "scale=1; $SCHED_MEM / 1024 / 1024" | bc) MB"
}

report_restarts() {
    report_header "РЕСТАРТЫ"
    pm2 jlist | jq -r 'sort_by(-.pm2_env.restart_time) | .[] | "\(.pm2_env.restart_time)|\(.name)"' | while IFS='|' read r name; do
        [ "${r:-0}" -gt 0 ] && icon="⚠️ " || icon="✅"
        printf "%s %-25s %s рестартов\n" "$icon" "$name" "${r:-0}"
    done
}

case "$FORMAT" in
    summary) report_summary ;;
    memory) report_memory ;;
    categories) report_categories ;;
    restarts) report_restarts ;;
    all) report_summary; echo ""; report_memory; echo ""; report_categories; echo ""; report_restarts ;;
    *) echo "Usage: $0 [summary|memory|categories|restarts|all]" ;;
esac
