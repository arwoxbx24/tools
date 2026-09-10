#!/bin/bash
# agent-health-dashboard.sh
# Terminal dashboard showing AI agent health metrics and trends

set +e  # Handle errors gracefully with defaults

# Colors
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
BOLD='\033[1m'

# Paths
SSH_LOG="/root/workspaces/tools/acc1-scripts/data/ssh-audit.log"
DOCKER_LOG="/root/workspaces/tools/acc1-scripts/data/docker-audit.log"
HOOK_LOG="/tmp/.hook-advisory.log"
METRICS_DIR="/root/workspaces/tools/acc1-scripts/data/agent-metrics"
TODAY=$(date +%Y-%m-%d)
TODAY_DISPLAY=$(date "+%b %d")

# Create metrics dir if needed
mkdir -p "$METRICS_DIR"

# Initialize counters
SSH_TOTAL=0
SSH_READ=0
SSH_WRITE=0
SSH_EXEC=0
SSH_REPEAT=0
DOCKER_TOTAL=0
DOCKER_BUILD=0
DOCKER_DESTRUCTIVE=0
SONNET_TASKS=0
CURL_POST=0
TELEGRAM=0
PM2_ONLINE=0
PM2_STOPPED=0

# Helper: count lines matching pattern in log for today
count_today() {
    local log=$1
    local pattern=$2
    if [[ -f "$log" ]]; then
        local result=$(grep -E "^\[$TODAY" "$log" 2>/dev/null | grep -cE "$pattern")
        echo "${result:-0}"
    else
        echo 0
    fi
}

# Helper: count all lines for today
count_today_all() {
    local log=$1
    if [[ -f "$log" ]]; then
        local result=$(grep -cE "^\[$TODAY" "$log" 2>/dev/null)
        echo "${result:-0}"
    else
        echo 0
    fi
}

# SSH metrics
if [[ -f "$SSH_LOG" ]]; then
    SSH_TOTAL=$(count_today_all "$SSH_LOG")

    # Read-only: commands containing cat/grep/find/ls/head/tail etc anywhere in line
    SSH_READ=$(count_today "$SSH_LOG" "( cat | grep | find | head | tail | ls | wc | sort | stat | file | pwd | which | git log| git show| git status| git diff| echo | printf | basename | dirname | readlink | less | more | tree )")

    # Write: commands containing sed/cp/mv/rm/mkdir/chmod/tee/>> anywhere in line
    SSH_WRITE=$(count_today "$SSH_LOG" "( sed | cp | mv | rm | mkdir | chmod | chown | tee | >> | > | touch | git add| git commit| git push| ln | rsync | tar | unzip | zip )")

    # Exec: php/curl/python/node execution anywhere in line
    SSH_EXEC=$(count_today "$SSH_LOG" "( php | curl | wget | python | node | npm | docker | systemctl | service | kill | pkill | killall | source )")

    # Calculate unmatched as read (defensive - anything not write/exec is likely read)
    SSH_MATCHED=$((SSH_WRITE + SSH_EXEC))
    if [[ $SSH_MATCHED -lt $SSH_TOTAL ]]; then
        SSH_READ=$((SSH_TOTAL - SSH_MATCHED))
    fi

    # Repeats: find commands that appear 3+ times
    if [[ -f "$SSH_LOG" ]]; then
        # Extract today's commands (strip timestamp), count duplicates
        SSH_REPEAT=$(grep -E "^\[$TODAY" "$SSH_LOG" 2>/dev/null | \
            sed -E 's/^\[[^]]+\] SSH: //' | \
            sort | uniq -c | \
            awk '$1 >= 3 {sum += $1} END {print sum+0}' | tr -d '\n' | head -1)
        [[ -z "$SSH_REPEAT" ]] && SSH_REPEAT=0
    fi
fi

# Docker metrics
if [[ -f "$DOCKER_LOG" ]]; then
    DOCKER_TOTAL=$(count_today_all "$DOCKER_LOG")
    DOCKER_BUILD=$(count_today "$DOCKER_LOG" "DOCKER.*: .*(build|compose up)")
    DOCKER_DESTRUCTIVE=$(count_today "$DOCKER_LOG" "DOCKER.*: .*(rm|rmi|stop|kill|prune|down)")
fi

# Sonnet tasks
if [[ -f "$HOOK_LOG" ]]; then
    SONNET_TASKS=$(grep -cE "Task:.*🟡 SONNET" "$HOOK_LOG" 2>/dev/null || echo 0)
fi

# curl POST counter
CURL_POST_FILE="/tmp/.curl-post-count-$(date +%Y%m%d)"
if [[ -f "$CURL_POST_FILE" ]]; then
    CURL_POST=$(cat "$CURL_POST_FILE")
fi

# Telegram counter
TG_FILE="/tmp/.tg-curl-count-$(date +%Y%m%d)"
if [[ -f "$TG_FILE" ]]; then
    TELEGRAM=$(cat "$TG_FILE")
fi

# PM2 status
if command -v pm2 &>/dev/null; then
    PM2_JSON=$(pm2 jlist 2>/dev/null || echo "[]")
    PM2_ONLINE=$(echo "$PM2_JSON" | jq -r '.[] | select(.pm2_env.status == "online") | .name' 2>/dev/null | wc -l || echo 0)
    PM2_STOPPED=$(echo "$PM2_JSON" | jq -r '.[] | select(.pm2_env.status != "online") | .name' 2>/dev/null | wc -l || echo 0)
fi

# Calculate percentages
SSH_READ_PCT=0
SSH_WRITE_PCT=0
SSH_EXEC_PCT=0
SSH_REPEAT_PCT=0
if [[ $SSH_TOTAL -gt 0 ]]; then
    SSH_READ_PCT=$((SSH_READ * 100 / SSH_TOTAL))
    SSH_WRITE_PCT=$((SSH_WRITE * 100 / SSH_TOTAL))
    SSH_EXEC_PCT=$((SSH_EXEC * 100 / SSH_TOTAL))
    SSH_REPEAT_PCT=$((SSH_REPEAT * 100 / SSH_TOTAL))
fi

# Calculate TREND (all days average)
TREND_SSH_TOTAL=0
TREND_SSH_READ_PCT=0
TREND_SSH_WRITE_PCT=0
TREND_SSH_EXEC_PCT=0
TREND_SSH_REPEAT_PCT=0
TREND_DOCKER_TOTAL=0
TREND_DOCKER_BUILD=0
TREND_DOCKER_DESTRUCTIVE=0
TREND_SONNET_TASKS=0
TREND_CURL_POST=0
TREND_TELEGRAM=0
TREND_DAYS=0

# Get unique dates from logs
if [[ -f "$SSH_LOG" ]] || [[ -f "$DOCKER_LOG" ]]; then
    DATES=$(
        (
            [[ -f "$SSH_LOG" ]] && grep -oE "^\[[0-9]{4}-[0-9]{2}-[0-9]{2}" "$SSH_LOG" | tr -d '[' || true
            [[ -f "$DOCKER_LOG" ]] && grep -oE "^\[[0-9]{4}-[0-9]{2}-[0-9]{2}" "$DOCKER_LOG" | tr -d '[' || true
        ) | sort -u
    )

    TREND_DAYS=$(echo "$DATES" | grep -c . || echo 0)

    if [[ $TREND_DAYS -gt 0 ]]; then
        # Calculate per-day stats
        TOTAL_SSH=0
        TOTAL_SSH_READ=0
        TOTAL_SSH_WRITE=0
        TOTAL_SSH_EXEC=0
        TOTAL_SSH_REPEAT=0
        TOTAL_DOCKER=0
        TOTAL_DOCKER_BUILD=0
        TOTAL_DOCKER_DESTRUCTIVE=0

        while IFS= read -r date; do
            [[ -z "$date" ]] && continue

            # SSH for this date
            day_ssh_total=0
            day_ssh_read=0
            day_ssh_write=0
            day_ssh_exec=0

            if [[ -f "$SSH_LOG" ]]; then
                day_ssh_total=$(grep -cE "^\[$date" "$SSH_LOG" 2>/dev/null)
                day_ssh_total=${day_ssh_total:-0}

                day_ssh_read=$(grep -E "^\[$date" "$SSH_LOG" 2>/dev/null | grep -cE "( ls | cat | grep | find | head | tail | git log| git show| git status| git diff| pwd | cd | which | echo | printf | basename | dirname | readlink | stat | file | wc | sort | uniq | less | more | tree )")
                day_ssh_read=${day_ssh_read:-0}

                day_ssh_write=$(grep -E "^\[$date" "$SSH_LOG" 2>/dev/null | grep -cE "( rm | mv | cp | mkdir | touch | git add| git commit| git push| chmod | chown | ln | rsync | tar | unzip | zip )")
                day_ssh_write=${day_ssh_write:-0}

                day_ssh_exec=$(grep -E "^\[$date" "$SSH_LOG" 2>/dev/null | grep -cE "( php | curl | wget | python | node | npm | docker | systemctl | service | kill | pkill | killall | source )")
                day_ssh_exec=${day_ssh_exec:-0}

                day_ssh_repeat=$(grep -E "^\[$date" "$SSH_LOG" 2>/dev/null | \
                    sed -E 's/^\[[^]]+\] SSH: //' | \
                    sort | uniq -c | \
                    awk '$1 >= 3 {sum += $1} END {print sum+0}' | tr -d '\n')
                day_ssh_repeat=${day_ssh_repeat:-0}
            fi

            TOTAL_SSH=$((TOTAL_SSH + day_ssh_total))
            TOTAL_SSH_READ=$((TOTAL_SSH_READ + day_ssh_read))
            TOTAL_SSH_WRITE=$((TOTAL_SSH_WRITE + day_ssh_write))
            TOTAL_SSH_EXEC=$((TOTAL_SSH_EXEC + day_ssh_exec))
            TOTAL_SSH_REPEAT=$((TOTAL_SSH_REPEAT + day_ssh_repeat))

            # Docker for this date
            if [[ -f "$DOCKER_LOG" ]]; then
                day_docker_total=$(grep -cE "^\[$date" "$DOCKER_LOG" 2>/dev/null)
                day_docker_total=${day_docker_total:-0}

                day_docker_build=$(grep -E "^\[$date" "$DOCKER_LOG" 2>/dev/null | grep -cE "DOCKER.*: .*(build|compose up)")
                day_docker_build=${day_docker_build:-0}

                day_docker_destructive=$(grep -E "^\[$date" "$DOCKER_LOG" 2>/dev/null | grep -cE "DOCKER.*: .*(rm|rmi|stop|kill|prune|down)")
                day_docker_destructive=${day_docker_destructive:-0}

                TOTAL_DOCKER=$((TOTAL_DOCKER + day_docker_total))
                TOTAL_DOCKER_BUILD=$((TOTAL_DOCKER_BUILD + day_docker_build))
                TOTAL_DOCKER_DESTRUCTIVE=$((TOTAL_DOCKER_DESTRUCTIVE + day_docker_destructive))
            fi
        done <<< "$DATES"

        # Calculate averages
        TREND_SSH_TOTAL=$((TOTAL_SSH / TREND_DAYS))
        TREND_DOCKER_TOTAL=$((TOTAL_DOCKER / TREND_DAYS))
        TREND_DOCKER_BUILD=$((TOTAL_DOCKER_BUILD / TREND_DAYS))
        TREND_DOCKER_DESTRUCTIVE=$((TOTAL_DOCKER_DESTRUCTIVE / TREND_DAYS))

        if [[ $TOTAL_SSH -gt 0 ]]; then
            TREND_SSH_READ_PCT=$((TOTAL_SSH_READ * 100 / TOTAL_SSH))
            TREND_SSH_WRITE_PCT=$((TOTAL_SSH_WRITE * 100 / TOTAL_SSH))
            TREND_SSH_EXEC_PCT=$((TOTAL_SSH_EXEC * 100 / TOTAL_SSH))
            TREND_SSH_REPEAT_PCT=$((TOTAL_SSH_REPEAT * 100 / TOTAL_SSH))
        fi
    fi
fi

# For Sonnet/curl/telegram, just use today's values as trend (no historical data)
TREND_SONNET_TASKS=$SONNET_TASKS
TREND_CURL_POST=$CURL_POST
TREND_TELEGRAM=$TELEGRAM

# Calculate health score
SCORE=0
SCORE_SSH_SAFETY=0
SCORE_DOCKER_SAFETY=0
SCORE_SONNET=0
SCORE_SSH_REPEAT=0
SCORE_CURL=0
SCORE_TELEGRAM=0
SCORE_PM2=0

# SSH safety (read >80%)
if [[ $SSH_READ_PCT -ge 80 ]]; then
    SCORE_SSH_SAFETY=20
elif [[ $SSH_READ_PCT -ge 60 ]]; then
    SCORE_SSH_SAFETY=10
fi

# Docker destructive
if [[ $DOCKER_DESTRUCTIVE -eq 0 ]]; then
    SCORE_DOCKER_SAFETY=20
elif [[ $DOCKER_DESTRUCTIVE -le 2 ]]; then
    SCORE_DOCKER_SAFETY=10
fi

# Sonnet delegation
if [[ $SONNET_TASKS -gt 0 ]]; then
    SCORE_SONNET=20
fi

# SSH repeat rate
if [[ $SSH_REPEAT_PCT -lt 15 ]]; then
    SCORE_SSH_REPEAT=15
elif [[ $SSH_REPEAT_PCT -lt 30 ]]; then
    SCORE_SSH_REPEAT=10
fi

# curl POST
if [[ $CURL_POST -lt 15 ]]; then
    SCORE_CURL=12
elif [[ $CURL_POST -lt 25 ]]; then
    SCORE_CURL=8
fi

# Telegram
if [[ $TELEGRAM -lt 3 ]]; then
    SCORE_TELEGRAM=10
fi

# PM2 health
PM2_TOTAL=$((PM2_ONLINE + PM2_STOPPED))
PM2_ONLINE_PCT=0
if [[ $PM2_TOTAL -gt 0 ]]; then
    PM2_ONLINE_PCT=$((PM2_ONLINE * 100 / PM2_TOTAL))
fi

if [[ $PM2_ONLINE_PCT -gt 80 ]]; then
    SCORE_PM2=3
elif [[ $PM2_ONLINE_PCT -gt 60 ]]; then
    SCORE_PM2=0
else
    SCORE_PM2=-10
fi

SCORE=$((SCORE_SSH_SAFETY + SCORE_DOCKER_SAFETY + SCORE_SONNET + SCORE_SSH_REPEAT + SCORE_CURL + SCORE_TELEGRAM + SCORE_PM2))

# Determine color and status
SCORE_COLOR=$GREEN
SCORE_STATUS="EXCELLENT"
if [[ $SCORE -ge 80 ]]; then
    SCORE_COLOR=$GREEN
    SCORE_STATUS="GOOD"
elif [[ $SCORE -ge 60 ]]; then
    SCORE_COLOR=$YELLOW
    SCORE_STATUS="FAIR"
else
    SCORE_COLOR=$RED
    SCORE_STATUS="BAD"
fi

# Progress bar (20 chars)
BAR_FILLED=$((SCORE / 5))
BAR_EMPTY=$((20 - BAR_FILLED))
PROGRESS_BAR=$(printf '█%.0s' $(seq 1 $BAR_FILLED))$(printf '░%.0s' $(seq 1 $BAR_EMPTY))

# Build verdict
VERDICT_PARTS=()

if [[ $SSH_REPEAT_PCT -ge 15 ]]; then
    VERDICT_PARTS+=("SSH repeat rate high (${SSH_REPEAT_PCT}%) — agents may be looping on commands")
fi

if [[ $DOCKER_DESTRUCTIVE -gt 0 ]]; then
    VERDICT_PARTS+=("Docker destructive attempts detected — check audit log")
fi

if [[ $CURL_POST -ge 15 ]]; then
    VERDICT_PARTS+=("curl POST high (${CURL_POST}/day) — consider script consolidation")
fi

if [[ $PM2_STOPPED -gt 0 ]]; then
    VERDICT_PARTS+=("PM2 health low — ${PM2_STOPPED} stopped processes")
fi

if [[ ${#VERDICT_PARTS[@]} -eq 0 ]]; then
    VERDICT="All metrics within normal range"
else
    VERDICT=$(IFS='; '; echo "${VERDICT_PARTS[*]}")
fi

# Save daily snapshot
cat > "$METRICS_DIR/$TODAY.json" <<EOF
{
  "date": "$TODAY",
  "score": $SCORE,
  "ssh_total": $SSH_TOTAL,
  "ssh_read_pct": $SSH_READ_PCT,
  "ssh_write": $SSH_WRITE,
  "ssh_exec": $SSH_EXEC,
  "ssh_repeat_pct": $SSH_REPEAT_PCT,
  "docker_total": $DOCKER_TOTAL,
  "docker_build": $DOCKER_BUILD,
  "docker_destructive": $DOCKER_DESTRUCTIVE,
  "sonnet_tasks": $SONNET_TASKS,
  "curl_post": $CURL_POST,
  "telegram": $TELEGRAM,
  "pm2_online": $PM2_ONLINE,
  "pm2_stopped": $PM2_STOPPED
}
EOF

# Display dashboard
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
printf "║  ${BOLD}AGENT HEALTH DASHBOARD${RESET}                 $(date '+%Y-%m-%d %H:%M')   ║\n"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  ${BOLD}HEALTH SCORE: ${SCORE_COLOR}${SCORE}/100${RESET}  ${PROGRESS_BAR}  ${SCORE_COLOR}${SCORE_STATUS}${RESET}           ║\n"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║                                                              ║"

# Add trend note
TREND_NOTE=""
if [[ $TREND_DAYS -eq 1 ]]; then
    TREND_NOTE=" (1 day)"
elif [[ $TREND_DAYS -gt 1 ]]; then
    TREND_NOTE=" (${TREND_DAYS} days)"
fi

printf "║  ${BOLD}TODAY ($TODAY_DISPLAY)${RESET}              |  ${BOLD}TREND (all days avg)${TREND_NOTE}${RESET}         ║\n"
echo "║  ─────────────────────────── | ──────────────────────────── ║"
printf "║  SSH commands:  %4d       |  Avg/day:  %-4d              ║\n" $SSH_TOTAL $TREND_SSH_TOTAL
printf "║    read-only:   %4d (%2d%%) |  Read %%:   %2d%%               ║\n" $SSH_READ $SSH_READ_PCT $TREND_SSH_READ_PCT
printf "║    write:       %4d (%2d%%) |  Write %%:  %2d%%               ║\n" $SSH_WRITE $SSH_WRITE_PCT $TREND_SSH_WRITE_PCT
printf "║    exec (php/curl): %3d (%2d%%) |  Exec %%:   %2d%%               ║\n" $SSH_EXEC $SSH_EXEC_PCT $TREND_SSH_EXEC_PCT
printf "║    repeats:     %4d (%2d%%) |  Repeat %%: %2d%%               ║\n" $SSH_REPEAT $SSH_REPEAT_PCT $TREND_SSH_REPEAT_PCT
echo "║  ─────────────────────────── | ──────────────────────────── ║"
printf "║  Docker commands: %3d       |  Avg/day:  %-3d              ║\n" $DOCKER_TOTAL $TREND_DOCKER_TOTAL
printf "║    build:         %3d       |  Avg builds: %-3d            ║\n" $DOCKER_BUILD $TREND_DOCKER_BUILD
printf "║    destructive:   %3d       |  Destructive: %-3d           ║\n" $DOCKER_DESTRUCTIVE $TREND_DOCKER_DESTRUCTIVE
echo "║  ─────────────────────────── | ──────────────────────────── ║"
printf "║  Sonnet tasks:    %3d       |  Avg/day:  %-3d              ║\n" $SONNET_TASKS $TREND_SONNET_TASKS
echo "║  ─────────────────────────── | ──────────────────────────── ║"
printf "║  curl POST:       %3d       |  Avg/day:  %-3d              ║\n" $CURL_POST $TREND_CURL_POST
printf "║  Telegram:        %3d       |  Avg/day:  %-3d              ║\n" $TELEGRAM $TREND_TELEGRAM
echo "║  ─────────────────────────── | ──────────────────────────── ║"
printf "║  PM2: %2d online, %2d stopped  |  (no trend yet)             ║\n" $PM2_ONLINE $PM2_STOPPED
echo "║                                                              ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  ${BOLD}SCORE BREAKDOWN:${RESET}                                            ║\n"

# Helper function to format score line
score_line() {
    local label=$1
    local points=$2
    local status=$3
    local color=$GREEN

    if [[ "$status" == "WARN" ]]; then
        color=$YELLOW
    elif [[ "$status" == "FAIL" ]] || [[ $points -lt 0 ]]; then
        color=$RED
    fi

    printf "║  %-28s %+4d  ${color}%-4s${RESET}                      ║\n" "$label" $points "$status"
}

score_line "SSH safety (read >80%):" $SCORE_SSH_SAFETY "$(if [[ $SCORE_SSH_SAFETY -eq 20 ]]; then echo OK; elif [[ $SCORE_SSH_SAFETY -eq 10 ]]; then echo WARN; else echo FAIL; fi)"
score_line "No destructive docker:" $SCORE_DOCKER_SAFETY "$(if [[ $SCORE_DOCKER_SAFETY -eq 20 ]]; then echo OK; elif [[ $SCORE_DOCKER_SAFETY -eq 10 ]]; then echo WARN; else echo FAIL; fi)"
score_line "Sonnet delegation:" $SCORE_SONNET "$(if [[ $SCORE_SONNET -eq 20 ]]; then echo OK; else echo FAIL; fi)"
score_line "Low SSH repeat rate:" $SCORE_SSH_REPEAT "$(if [[ $SCORE_SSH_REPEAT -eq 15 ]]; then echo OK; elif [[ $SCORE_SSH_REPEAT -eq 10 ]]; then echo WARN; else echo FAIL; fi)"
score_line "curl POST within limit:" $SCORE_CURL "$(if [[ $SCORE_CURL -eq 12 ]]; then echo OK; elif [[ $SCORE_CURL -eq 8 ]]; then echo WARN; else echo FAIL; fi)"
score_line "No telegram abuse:" $SCORE_TELEGRAM "$(if [[ $SCORE_TELEGRAM -eq 10 ]]; then echo OK; else echo FAIL; fi)"
score_line "PM2 health:" $SCORE_PM2 "$(if [[ $SCORE_PM2 -eq 3 ]]; then echo OK; elif [[ $SCORE_PM2 -eq 0 ]]; then echo WARN; else echo WARN; fi)"

echo "╠══════════════════════════════════════════════════════════════╣"

# Wrap verdict to fit in box
VERDICT_WRAPPED=$(echo "$VERDICT" | fold -w 60 -s)
while IFS= read -r line; do
    printf "║  %-60s  ║\n" "$line"
done <<< "$VERDICT_WRAPPED"

echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
